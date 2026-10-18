[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Hwfrp

type addr = {
  a_fire : bool;
  a_valid : bool;
  a_addr : int;
  a_id : int;
  a_len : int;
  a_size : int;
  a_burst : int;
}

type rdata = { r_fire : bool; r_id : int; r_resp : int; r_last : bool }
type wdata = { w_fire : bool; w_strb : int; w_last : bool }
type bresp = { b_fire : bool; b_id : int; b_resp : int }

let b sc n = Bind.signal sc n Bind.bool
let u sc n = Bind.signal sc n Bind.uint
let fire sc ch = Sig.map2 ( && ) (b sc (ch ^ "_valid")) (b sc (ch ^ "_ready"))

let addr sc ch =
  let open Sig in
  let+ valid = b sc (ch ^ "_valid")
  and+ ready = b sc (ch ^ "_ready")
  and+ addr = u sc (ch ^ "_bits_addr")
  and+ id = u sc (ch ^ "_bits_id")
  and+ len = u sc (ch ^ "_bits_len")
  and+ size = u sc (ch ^ "_bits_size")
  and+ burst = u sc (ch ^ "_bits_burst") in
  {
    a_fire = valid && ready;
    a_valid = valid;
    a_addr = addr;
    a_id = id;
    a_len = len;
    a_size = size;
    a_burst = burst;
  }

let rdata sc ch =
  let open Sig in
  let+ fire = fire sc ch
  and+ id = u sc (ch ^ "_bits_id")
  and+ resp = u sc (ch ^ "_bits_resp")
  and+ last = b sc (ch ^ "_bits_last") in
  { r_fire = fire; r_id = id; r_resp = resp; r_last = last }

let wdata sc ch ~data_bytes =
  let open Sig in
  let+ fire = fire sc ch
  and+ strb = Bind.signal sc (ch ^ "_bits_strb") { Bind.uint with dwidth = Exact data_bytes }
  and+ last = b sc (ch ^ "_bits_last") in
  { w_fire = fire; w_strb = strb; w_last = last }

let bresp sc ch =
  let open Sig in
  let+ fire = fire sc ch and+ id = u sc (ch ^ "_bits_id") and+ resp = u sc (ch ^ "_bits_resp") in
  { b_fire = fire; b_id = id; b_resp = resp }

type names = {
  read_addr : string;
  write_addr : string;
  read_data : string;
  write_data : string;
  write_resp : string;
}

let chisel p =
  {
    read_addr = p ^ "read_addr";
    write_addr = p ^ "write_addr";
    read_data = p ^ "read_data";
    write_data = p ^ "write_data";
    write_resp = p ^ "write_resp";
  }

type 'c channels = {
  ar : (addr, 'c) Sig.t;
  aw : (addr, 'c) Sig.t;
  r : (rdata, 'c) Sig.t;
  w : (wdata, 'c) Sig.t;
  b : (bresp, 'c) Sig.t;
}

let bind sc n ~data_bytes =
  let r = rdata sc n.read_data in
  let w = wdata sc n.write_data ~data_bytes in
  let b = bresp sc n.write_resp in
  let ar = addr sc n.read_addr in
  let aw = addr sc n.write_addr in
  { ar; aw; r; w; b }

type extra = { serial : int; burst : int; beat_bytes : int }

type event =
  | Accepted of Transaction.t * extra
  | Done of Transaction.t * extra
  | Open_at_end of Transaction.t * extra
  | Unmatched of { cycle : int; write : bool; id : int; what : string }

type counts = { max_reads : int; max_writes : int }

module IM = Map.Make (Int)

(* A write data burst, possibly ahead of its address. *)
type wburst = { wb_first : int; wb_bytes : int; wb_beats : int }
type pending = { t : Transaction.t; x : extra }

type state = {
  live : pending IM.t;  (** Outstanding, by serial: acceptance order. *)
  reads : int list IM.t;  (** Per ID, the serials outstanding, oldest first. *)
  writes : int list IM.t;
  need_data : int list;  (** Writes accepted before their data, oldest first. *)
  early : wburst list;  (** Data bursts ahead of their address, oldest first. *)
  burst : wburst option;  (** The data burst in progress. *)
  serial : int;
  reads_out : int;
  writes_out : int;
  max_reads : int;
  max_writes : int;
  ar_since : int option;
  aw_since : int option;
}

let init =
  {
    live = IM.empty;
    reads = IM.empty;
    writes = IM.empty;
    need_data = [];
    early = [];
    burst = None;
    serial = 0;
    reads_out = 0;
    writes_out = 0;
    max_reads = 0;
    max_writes = 0;
    ar_since = None;
    aw_since = None;
  }

let popcount n =
  let rec go n k = if n = 0 then k else go (n land (n - 1)) (k + 1) in
  go n 0

let oldest q id = match IM.find_opt id q with Some (s :: _) -> Some s | _ -> None
let pop q id = IM.update id (function Some (_ :: (_ :: _ as rest)) -> Some rest | _ -> None) q
let push q id s = IM.update id (fun l -> Some (Option.value l ~default:[] @ [ s ])) q
let set s k f = { s with live = IM.add k (f (IM.find k s.live)) s.live }

let attach s k wb =
  set s k (fun p -> { p with t = { p.t with bytes = wb.wb_bytes; first_data = Some wb.wb_first } })

(* One cycle: responses first, as none can belong to an address accepted in the same cycle. *)
let step s cycle (ar, aw, r, w, bch) =
  let out = ref [] in
  let emit e = out := e :: !out in
  let miss write id what = emit (Unmatched { cycle; write; id; what }) in
  let complete s k =
    let p = IM.find k s.live in
    let t = { p.t with completed = Some cycle } in
    emit (Done (t, p.x));
    { s with live = IM.remove k s.live }
  in
  let s =
    if not r.r_fire then s
    else
      match oldest s.reads r.r_id with
      | None ->
          miss false r.r_id "read data with no outstanding read";
          s
      | Some k ->
          let s =
            set s k (fun p ->
                let t = p.t in
                let first_data = if t.first_data = None then Some cycle else t.first_data in
                {
                  p with
                  t =
                    {
                      t with
                      first_data;
                      bytes = t.bytes + p.x.beat_bytes;
                      status = max t.status r.r_resp;
                    };
                })
          in
          if r.r_last then
            complete { s with reads = pop s.reads r.r_id; reads_out = s.reads_out - 1 } k
          else s
  in
  let s =
    if not bch.b_fire then s
    else
      match oldest s.writes bch.b_id with
      | None ->
          miss true bch.b_id "write response with no outstanding write";
          s
      | Some k ->
          let s =
            set s k (fun p -> { p with t = { p.t with status = max p.t.status bch.b_resp } })
          in
          complete { s with writes = pop s.writes bch.b_id; writes_out = s.writes_out - 1 } k
  in
  let s =
    if not w.w_fire then s
    else
      let wb =
        match s.burst with
        | Some wb -> wb
        | None -> { wb_first = cycle; wb_bytes = 0; wb_beats = 0 }
      in
      let wb = { wb with wb_bytes = wb.wb_bytes + popcount w.w_strb; wb_beats = wb.wb_beats + 1 } in
      if not w.w_last then { s with burst = Some wb }
      else
        let s = { s with burst = None } in
        match s.need_data with
        | k :: rest -> attach { s with need_data = rest } k wb
        | [] -> { s with early = s.early @ [ wb ] }
  in
  let accept s (ch : addr) ~write ~since =
    let reads_out = if write then s.reads_out else s.reads_out + 1
    and writes_out = if write then s.writes_out + 1 else s.writes_out in
    let p =
      {
        t =
          {
            Transaction.id = ch.a_id;
            write;
            address = ch.a_addr;
            bytes = 0;
            beats = ch.a_len + 1;
            requested = Option.value since ~default:cycle;
            accepted = cycle;
            first_data = None;
            completed = None;
            status = 0;
            outstanding = reads_out + writes_out;
          };
        x = { serial = s.serial; burst = ch.a_burst; beat_bytes = 1 lsl ch.a_size };
      }
    in
    ( {
        s with
        live = IM.add s.serial p s.live;
        serial = s.serial + 1;
        reads_out;
        writes_out;
        max_reads = max s.max_reads reads_out;
        max_writes = max s.max_writes writes_out;
      },
      s.serial )
  in
  let accepted s k =
    (let p = IM.find k s.live in
     emit (Accepted (p.t, p.x)));
    s
  in
  let s =
    if not ar.a_fire then s
    else
      let s, k = accept s ar ~write:false ~since:s.ar_since in
      accepted { s with reads = push s.reads ar.a_id k } k
  in
  let s =
    if not aw.a_fire then s
    else
      let s, k = accept s aw ~write:true ~since:s.aw_since in
      let s = { s with writes = push s.writes aw.a_id k } in
      let s =
        match s.early with
        | wb :: rest -> attach { s with early = rest } k wb
        | [] -> { s with need_data = s.need_data @ [ k ] }
      in
      accepted s k
  in
  let since r (ch : addr) =
    if ch.a_valid && not ch.a_fire then Some (Option.value r ~default:cycle) else None
  in
  let ar_since = since s.ar_since ar and aw_since = since s.aw_since aw in
  let s =
    if ar_since = s.ar_since && aw_since = s.aw_since then s else { s with ar_since; aw_since }
  in
  (s, List.rev !out)

let finish s =
  List.map
    (fun wb ->
      Unmatched
        { cycle = wb.wb_first; write = true; id = -1; what = "write data with no write address" })
    s.early
  @ List.map (fun (_, p) -> Open_at_end (p.t, p.x)) (IM.bindings s.live)

type sample = addr * addr * rdata * wdata * bresp

let sample ch =
  let open Sig in
  let+ ar = ch.ar and+ aw = ch.aw and+ r = ch.r and+ w = ch.w and+ b = ch.b in
  (ar, aw, r, w, b)

let counts s = { max_reads = s.max_reads; max_writes = s.max_writes }

let track ?(name = "axi4") ch =
  let out, st =
    Machine.run
      { name; init; step = (fun ~tick s x -> step s tick.index x); finish; every_tick = true }
      (sample ch)
  in
  (out, Sig.map counts st)
