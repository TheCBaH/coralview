[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Hwfrp

type 'c dep = ..

type 'c t = {
  net : Net.t;
  trace : Trace.t;
  clk : 'c Clock.t;
  platform : Platform.t;
  model : string;
  deps : (string, 'c dep) Hashtbl.t;
}

type any = Any : 'c t -> any

exception No_block of string * string

let bind ?(collect = false) ?max_diags (p : Platform.t) tr ~model =
  let net = Net.create ?max_diags () in
  if collect then Bind.collect net;
  let reset =
    Option.map
      (fun (r : Platform.reset) -> (Platform.scope p [ r.reset_signal ], r.reset_active))
      p.reset
  in
  let (Clock.Any clk) =
    Bind.clock net tr ~model ~purpose:"core clock" ~name:p.clock ?reset p.sample
      (Platform.scope p [ p.clock ])
  in
  Any { net; trace = tr; clk; platform = p; model; deps = Hashtbl.create 4 }

let block c name = function Some b -> b | None -> raise (No_block (c.platform.name, name))
let scope c rel = Bind.root c.net c.trace c.clk ~model:c.model (Platform.scope c.platform rel)

let signal c scope name d =
  match String.rindex_opt name '/' with
  | None ->
      Bind.signal
        (Bind.root c.net c.trace c.clk ~model:c.model (Platform.scope c.platform scope))
        name d
  | Some i ->
      let rel = scope @ String.split_on_char '/' (String.sub name 0 i) in
      Bind.signal
        (Bind.root c.net c.trace c.clk ~model:c.model (Platform.scope c.platform rel))
        (String.sub name (i + 1) (String.length name - i - 1))
        d

let start ?(gate = fun _ ~model:_ -> ()) c =
  gate c.trace ~model:c.model;
  match Sched.compile c.net with
  | Ok sched ->
      Run.start ~clock:Hwfrp_native.wall_clock sched (Sampler.create c.trace (Net.domains c.net))
  | Error _ -> invalid_arg "Core.start: the net does not compile"

let run ?gate c = Run.finish (start ?gate c)

let lane_sig c valid payload =
  let open Sig in
  match c.platform.reset with
  | None ->
      let+ v = valid and+ p = payload in
      if v then Some p else None
  | Some _ ->
      let+ v = valid and+ p = payload and+ in_reset = Sig.in_reset c.clk in
      if v && not in_reset then Some p else None

type dispatched = { d_lane : int; d_pc : int; d_word : int }

let dispatch c =
  let b = block c "dispatch_debug" c.platform.blocks.dispatch_debug in
  let sc = scope c b.dd_scope in
  List.init b.dd_lanes (fun i ->
      let name = Platform.name_of in
      let valid = Bind.signal sc (name b.dd_fire i) Bind.bool ~purpose:"dispatch lane fires" in
      let pc = Bind.signal sc (name b.dd_addr i) Bind.uint ~purpose:"dispatched PC" in
      let word = Bind.signal sc (name b.dd_inst i) Bind.uint ~purpose:"dispatched word" in
      lane_sig c valid
        (let open Sig in
         let+ pc = pc and+ word = word in
         { d_lane = i; d_pc = pc; d_word = word }))

type retired = { r_lane : int; r_pc : int; r_idx : int; r_trap : bool }

let float_base = 32
let vector_base = 64
let retirement c = block c "retirement_debug" c.platform.blocks.retirement_debug
let no_write c = (1 lsl (retirement c).idx_width) - 1
let store c = no_write c - 1

let retire c =
  let b = retirement c in
  let sc = scope c b.rd_scope in
  List.init b.rd_lanes (fun i ->
      let name = Platform.name_of in
      let valid = Bind.signal sc (name b.rd_valid i) Bind.bool ~purpose:"retirement lane valid" in
      let pc = Bind.signal sc (name b.rd_pc i) Bind.uint ~purpose:"retired PC" in
      let idx =
        Bind.signal sc (name b.rd_idx i)
          { Bind.uint with dwidth = Exact b.idx_width }
          ~purpose:"retired destination index"
      in
      let trap =
        match b.rd_trap with
        | Some t -> Bind.signal sc (name t i) Bind.bool ~purpose:"retired with a trap"
        | None -> Sig.const c.clk false
      in
      lane_sig c valid
        (let open Sig in
         let+ pc = pc and+ idx = idx and+ trap = trap in
         { r_lane = i; r_pc = pc; r_idx = idx; r_trap = trap }))

type write = { reg : int; value : int }

let write_ports c group base (b : Platform.writeback) =
  let sc = scope c b.wb_scope in
  List.init b.ports (fun i ->
      let name = Platform.name_of in
      let valid = Bind.signal sc (name b.wb_valid i) Bind.bool ~purpose:(group ^ " writeback") in
      let addr = Bind.signal sc (name b.wb_addr i) Bind.uint ~purpose:"written register" in
      let data = Bind.signal sc (name b.wb_data i) Bind.uint ~purpose:"written value" in
      lane_sig c valid
        (let open Sig in
         let+ addr = addr and+ data = data in
         { reg = base + addr; value = data }))

let writes c =
  write_ports c "regfile" 0 (block c "regfile_writeback" c.platform.blocks.regfile_writeback)
  @
  match c.platform.blocks.float_writeback with
  | Some b -> write_ports c "float" float_base b
  | None -> []

let present c = function
  | [] -> Sig.const c.clk []
  | l -> Sig.map (List.filter_map Fun.id) (Sig.all l)

let reg_name r =
  if r < float_base then Printf.sprintf "x%d" r
  else if r < vector_base then Printf.sprintf "f%d" (r - float_base)
  else Printf.sprintf "v%d" (r - vector_base)

let cycles c (st : Sched.run_stats) = st.ticks.(Clock.index c.clk)
