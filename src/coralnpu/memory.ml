[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Hwfrp

let name = "memory"
let doc = "LSU data requests and faults, with PC, address and data."
let needs = [ "lsu" ]

module IM = Map.Make (Int)

module RM = Map.Make (struct
  type t = int * bool

  let compare = compare
end)

module Config = struct
  type t = { region : Region.t }

  let default = { region = Region.none }
end

module Event = struct
  type access = {
    cycle : int;  (** Of the request. *)
    pc : int;
    access : Access.t;  (** [bytes]: the lanes selected. *)
    lanes : int list;
    data : Bits.t;
  }

  type fault = {
    cycle : int;
    pc : int;
    address : int;
    write : bool;
    region : string option;
    request : (int * int) option;
  }

  type unmatched = { cycle : int; source : int }
  type t = Access of access | Fault of fault | Unmatched of unmatched

  let access =
    Codec.case "memory.access"
      (fun a -> Access a)
      (Jsont.Object.map (fun cycle pc access lanes data -> { cycle; pc; access; lanes; data })
      |> Jsont.Object.mem "cycle" Jsont.int ~enc:(fun (a : access) -> a.cycle)
      |> Jsont.Object.mem "pc" Jsont.int ~enc:(fun (a : access) -> a.pc)
      |> Jsont.Object.mem "access" Access.jsont ~enc:(fun a -> a.access)
      |> Jsont.Object.mem "lanes" Jsont.(list int) ~enc:(fun a -> a.lanes)
      |> Jsont.Object.mem "data" Codec.bits ~enc:(fun a -> a.data)
      |> Jsont.Object.finish)

  let request =
    Jsont.Object.map ~kind:"request" (fun cycle address -> (cycle, address))
    |> Jsont.Object.mem "cycle" Jsont.int ~enc:fst
    |> Jsont.Object.mem "address" Jsont.int ~enc:snd
    |> Jsont.Object.finish

  let fault =
    Codec.case "memory.fault"
      (fun f -> Fault f)
      (Jsont.Object.map (fun cycle pc address write region request ->
           { cycle; pc; address; write; region; request })
      |> Jsont.Object.mem "cycle" Jsont.int ~enc:(fun (f : fault) -> f.cycle)
      |> Jsont.Object.mem "pc" Jsont.int ~enc:(fun (f : fault) -> f.pc)
      |> Jsont.Object.mem "address" Jsont.int ~enc:(fun f -> f.address)
      |> Jsont.Object.mem "write" Jsont.bool ~enc:(fun f -> f.write)
      |> Codec.opt (fun f -> f.region) "region" Jsont.string
      |> Codec.opt (fun f -> f.request) "request" request
      |> Jsont.Object.finish)

  let unmatched =
    Codec.case "memory.unmatched"
      (fun u -> Unmatched u)
      (Jsont.Object.map (fun cycle source -> { cycle; source })
      |> Jsont.Object.mem "cycle" Jsont.int ~enc:(fun (u : unmatched) -> u.cycle)
      |> Jsont.Object.mem "source" Jsont.int ~enc:(fun u -> u.source)
      |> Jsont.Object.finish)

  let jsont =
    Codec.cases "memory.event"
      (function
        | Access a -> Jsont.Object.Case.value access a
        | Fault f -> Jsont.Object.Case.value fault f
        | Unmatched u -> Jsont.Object.Case.value unmatched u)
      Jsont.Object.Case.[ make access; make fault; make unmatched ]

  let cycle = function Access a -> a.cycle | Fault f -> f.cycle | Unmatched u -> u.cycle
  let pc = function Access a -> Some a.pc | Fault f -> Some f.pc | Unmatched _ -> None
end

module Summary = struct
  type t = { reads : int; writes : int; pcs : int; faults : int; unmatched : int }

  let jsont =
    Codec.record "memory.summary" (fun reads writes pcs faults unmatched ->
        { reads; writes; pcs; faults; unmatched })
    |> Jsont.Object.mem "reads" Jsont.int ~enc:(fun s -> s.reads)
    |> Jsont.Object.mem "writes" Jsont.int ~enc:(fun s -> s.writes)
    |> Jsont.Object.mem "pcs" Jsont.int ~enc:(fun s -> s.pcs)
    |> Jsont.Object.mem "faults" Jsont.int ~enc:(fun s -> s.faults)
    |> Jsont.Object.mem "unmatched" Jsont.int ~dec_absent:0 ~enc_omit:(( = ) 0) ~enc:(fun s ->
        s.unmatched)
    |> Jsont.Object.finish
end

let value (a : Event.access) =
  Bits.concat (List.rev_map (fun b -> Bits.field a.data ~lo:(8 * b) ~width:8) a.lanes)

let lanes_of_mask ~data_bytes m =
  List.filter (fun b -> (m lsr b) land 1 = 1) (List.init data_bytes Fun.id)

(* TileLink-UL masks the lanes of a read as it does a write's. *)
let lanes ~data_bytes (r : Tlul.request) =
  match lanes_of_mask ~data_bytes r.mask with
  | [] ->
      let lane = r.address land (data_bytes - 1) in
      List.init (min r.size (data_bytes - lane)) (fun k -> lane + k)
  | l -> l

type state = {
  tl : Tlul.state;
  pcs_of : int IM.t;  (** The PC of each request awaiting its response, by source. *)
  last_request : (int * int) RM.t;  (** By PC and direction: cycle and address. *)
  reads : int;
  writes : int;
  pcs : unit IM.t;
  faults : int;
  unmatched : int;
}

let access ~region ~data_bytes (t : Tlul.transaction) pc data =
  let lanes = lanes ~data_bytes t.request in
  {
    Event.cycle = t.accepted;
    pc;
    access =
      {
        address = t.request.address;
        bytes = List.length lanes;
        write = not (Tlul.is_get t.request);
        region = Region.find region t.request.address;
      };
    lanes;
    data;
  }

(* A write is complete at its request; a read, when its response brings the data. *)
let accesses ~region ~data_bytes s pc events =
  let pcs_of, out =
    List.fold_left
      (fun (pcs_of, out) -> function
        | Tlul.Accepted t ->
            let pcs_of = IM.add t.request.source pc pcs_of in
            if Tlul.is_get t.request then (pcs_of, out)
            else (pcs_of, access ~region ~data_bytes t pc t.request.data :: out)
        | Responded t ->
            let source = t.request.source in
            let at = Option.value (IM.find_opt source pcs_of) ~default:pc in
            let pcs_of = IM.remove source pcs_of in
            if Tlul.is_get t.request then (pcs_of, access ~region ~data_bytes t at t.response :: out)
            else (pcs_of, out)
        | Unmatched _ | Reopened _ -> (pcs_of, out))
      (s.pcs_of, []) events
  in
  (pcs_of, List.rev out)

let step ?(report = ignore) ~region ~data_bytes ~port s cycle (sample, pc, fault) =
  let tl, events = Tlul.step port s.tl cycle sample in
  List.iter report events;
  let pcs_of, accesses = accesses ~region ~data_bytes s pc events in
  let last_request =
    List.fold_left
      (fun m -> function
        | Tlul.Accepted t ->
            RM.add (pc, not (Tlul.is_get t.request)) (t.accepted, t.request.address) m
        | Responded _ | Unmatched _ | Reopened _ -> m)
      s.last_request events
  in
  let s = { s with tl; pcs_of; last_request } in
  let s =
    List.fold_left
      (fun s (a : Event.access) ->
        {
          s with
          reads = (s.reads + if a.access.write then 0 else 1);
          writes = (s.writes + if a.access.write then 1 else 0);
          pcs = IM.add a.pc () s.pcs;
        })
      s accesses
  in
  let unmatched =
    List.filter_map
      (function Tlul.Unmatched source -> Some { Event.cycle; source } | _ -> None)
      events
  in
  let s = { s with unmatched = s.unmatched + List.length unmatched } in
  let out =
    List.map (fun a -> Event.Access a) accesses @ List.map (fun u -> Event.Unmatched u) unmatched
  in
  match fault with
  | None -> (s, out)
  | Some (pc, address, write) ->
      ( { s with faults = s.faults + 1 },
        out
        @ [
            Event.Fault
              {
                cycle;
                pc;
                address;
                write;
                region = Region.find region address;
                request = RM.find_opt (pc, write) s.last_request;
              };
          ] )

let build (cfg : Config.t) (c : _ Core.t) =
  let l = Core.block c "lsu" c.platform.blocks.lsu in
  let sc = Core.scope c l.lsu_scope in
  let b n = Bind.signal sc n Bind.bool and u n = Bind.signal sc n Bind.uint in
  let pc = Core.signal c l.lsu_scope l.lsu_pc Bind.uint in
  let data_bytes = l.port.tl_data_bytes in
  let port = Tlul.bind sc { prefix = l.port.tl_prefix; d_ready = l.port.d_ready } ~data_bytes in
  let faults =
    let open Sig in
    let+ valid = b l.fault.f_valid
    and+ write = b l.fault.f_write
    and+ addr = u l.fault.f_addr
    and+ epc = u l.fault.f_epc in
    if valid then Some (epc, addr, write) else None
  in
  let input =
    let open Sig in
    let+ tl = Tlul.sample port and+ pc = pc and+ f = faults in
    (tl, pc, f)
  in
  let out, st =
    Machine.run
      {
        name;
        init =
          {
            tl = Tlul.init;
            pcs_of = IM.empty;
            last_request = RM.empty;
            reads = 0;
            writes = 0;
            pcs = IM.empty;
            faults = 0;
            unmatched = 0;
          };
        step =
          (fun ~tick s x ->
            let report e = Option.iter (Diag.report c.net) (Tlul.diagnostic port ~source:name e) in
            step ~report ~region:cfg.region ~data_bytes ~port s tick.index x);
        finish = (fun _ -> []);
        every_tick = true;
      }
      input
  in
  let summary _ =
    let s = Sig.peek st in
    {
      Summary.reads = s.reads;
      writes = s.writes;
      pcs = IM.cardinal s.pcs;
      faults = s.faults;
      unmatched = s.unmatched;
    }
  in
  (out, summary)

module Accumulator = struct
  type event = Event.t
  type snapshot = Summary.t

  type t = {
    mutable reads : int;
    mutable writes : int;
    mutable pcs : unit IM.t;
    mutable faults : int;
    mutable unmatched : int;
  }

  let create () = { reads = 0; writes = 0; pcs = IM.empty; faults = 0; unmatched = 0 }

  let add t = function
    | Event.Access a ->
        if a.access.write then t.writes <- t.writes + 1 else t.reads <- t.reads + 1;
        t.pcs <- IM.add a.pc () t.pcs
    | Event.Fault _ -> t.faults <- t.faults + 1
    | Event.Unmatched _ -> t.unmatched <- t.unmatched + 1

  let snapshot t =
    {
      Summary.reads = t.reads;
      writes = t.writes;
      pcs = IM.cardinal t.pcs;
      faults = t.faults;
      unmatched = t.unmatched;
    }
end

module KM = Map.Make (struct
  type t = int * int

  let compare = compare
end)

let text (ctx : Text.ctx) ppf summary : Event.t Text.sink =
  let region = Region.suffix ctx.region in
  (* A read is emitted with its response, after later writes: rows go in request order, ties in
     arrival order. Only the first [limit] requests are shown, so only that many are kept; the
     faults and unmatched responses, which are all shown, are kept all. *)
  let accesses = ref KM.empty and n = ref 0 and others = ref [] and seq = ref 0 in
  let acc = Accumulator.create () in
  let selected = Text.selected ctx.window in
  let selected_any_pc = Text.selected { ctx.window with pcs = [] } in
  let add e =
    incr seq;
    let key = (Event.cycle e, !seq) in
    match e with
    | Event.Fault f ->
        if selected ~cycle:f.cycle ~pc:f.pc then begin
          others := (key, e) :: !others;
          Accumulator.add acc e
        end
    | Unmatched u ->
        if selected_any_pc ~cycle:u.cycle ~pc:(-1) then begin
          others := (key, e) :: !others;
          Accumulator.add acc e
        end
    | Access a ->
        if selected ~cycle:a.cycle ~pc:a.pc then begin
          Accumulator.add acc e;
          accesses := KM.add key e !accesses;
          incr n;
          if !n > ctx.limit then begin
            accesses := KM.remove (fst (KM.max_binding !accesses)) !accesses;
            decr n
          end
        end
  in
  let finish () =
    let s : Summary.t = summary () in
    List.sort (fun (a, _) (b, _) -> compare a b) (KM.bindings !accesses @ !others)
    |> List.iter (function
      | _, Event.Fault f ->
          Format.fprintf ppf "%8d fault %s pc %08x addr %08x%s, %s\n" f.cycle
            (if f.write then "W" else "R")
            f.pc f.address (region f.address)
            (match f.request with
            | Some (cycle, addr) -> Printf.sprintf "requested at %d, addr %08x" cycle addr
            | None -> "no request seen")
      | _, Unmatched u ->
          Format.fprintf ppf "%8d unmatched response for source %d\n" u.cycle u.source
      | _, Access a ->
          Format.fprintf ppf "%8d %s pc %08x addr %08x%s %d bytes %s\n" a.cycle
            (if a.access.write then "W" else "R")
            a.pc a.access.address (region a.access.address) (List.length a.lanes)
            (Bits.to_hex (value a)));
    let unmatched n = if n = 0 then "" else Printf.sprintf ", %d unmatched" n in
    Format.fprintf ppf "root %s: %d read and %d write requests from %d PCs, %d faults%s\n" ctx.root
      s.reads s.writes s.pcs s.faults (unmatched s.unmatched);
    if Text.windowed ctx.window then begin
      let w = Accumulator.snapshot acc in
      Format.fprintf ppf "%s: %d read and %d write requests from %d PCs, %d faults%s\n"
        (Text.describe ctx.window) w.reads w.writes w.pcs w.faults (unmatched w.unmatched)
    end
  in
  { add; finish }
