[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Hwfrp

type 'c t = {
  net : Net.t;
  trace : Trace.t;
  clk : 'c Clock.t;
  platform : Platform.t;
  model : string;
}

type any = Any : 'c t -> any

exception No_block of string * string

let bind (p : Platform.t) tr ~model =
  let net = Net.create () in
  let (Clock.Any clk) =
    Bind.clock net tr ~model ~purpose:"core clock" ~name:p.clock p.sample
      (Platform.scope p [ p.clock ])
  in
  Any { net; trace = tr; clk; platform = p; model }

let block c name = function Some b -> b | None -> raise (No_block (c.platform.name, name))
let scope c rel = Bind.root c.net c.trace c.clk ~model:c.model (Platform.scope c.platform rel)

let run c =
  match Sched.compile c.net with
  | Ok sched -> Sched.run sched (Sampler.create c.trace (Net.domains c.net))
  | Error _ -> invalid_arg "Core.run: the net does not compile"

let lane_sig valid payload =
  let open Sig in
  let+ v = valid and+ p = payload in
  if v then Some p else None

type dispatched = { d_lane : int; d_pc : int; d_word : int }

let dispatch c =
  let b = block c "dispatch_debug" c.platform.blocks.dispatch_debug in
  let sc = scope c b.dd_scope in
  List.init b.dd_lanes (fun i ->
      let p = Printf.sprintf "io_debug_dispatch_%d_inst" i in
      let valid = Bind.signal sc (p ^ "Fire") Bind.bool ~purpose:"dispatch lane fires" in
      let pc = Bind.signal sc (p ^ "Addr") Bind.uint ~purpose:"dispatched PC" in
      let word = Bind.signal sc (p ^ "Inst") Bind.uint ~purpose:"dispatched word" in
      lane_sig valid
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
      let rb =
        Bundle.valid sc ~purpose:"retirement lane valid" (Printf.sprintf "io_debug_rb_inst_%d" i)
      in
      let pc = Bundle.get rb.v_bits "pc" Bind.uint ~purpose:"retired PC" in
      let idx =
        Bundle.get rb.v_bits "idx"
          { Bind.uint with dwidth = Exact b.idx_width }
          ~purpose:"retired destination index"
      in
      let trap =
        if b.trap then Bundle.get rb.v_bits "trap" Bind.bool ~purpose:"retired with a trap"
        else Sig.const c.clk false
      in
      lane_sig rb.v_valid
        (let open Sig in
         let+ pc = pc and+ idx = idx and+ trap = trap in
         { r_lane = i; r_pc = pc; r_idx = idx; r_trap = trap }))

type write = { reg : int; value : int }

let write_ports c group base (b : Platform.writeback) =
  let sc = scope c b.wb_scope in
  List.init b.ports (fun i ->
      let p = Printf.sprintf "io_debug_%s_writeData_%d" group i in
      let w = Bundle.valid sc ~purpose:(group ^ " writeback") p in
      let addr = Bundle.get w.v_bits "addr" Bind.uint ~purpose:"written register" in
      let data = Bundle.get w.v_bits "data" Bind.uint ~purpose:"written value" in
      lane_sig w.v_valid
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
