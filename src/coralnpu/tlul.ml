[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Hwfrp

type request = { opcode : int; size : int; source : int; address : int; mask : int; data : Bits.t }

type transaction = {
  request : request;
  requested : int;
  accepted : int;
  responded : int option;
  response : Bits.t;
  error : bool;
}

let is_get r = r.opcode = 4

let value ~data_bytes r data =
  let lane = r.address land (data_bytes - 1) in
  Bits.field_int data ~lo:(8 * lane) ~width:(8 * min 8 (min r.size (data_bytes - lane)))

type event = Accepted of transaction | Responded of transaction | Unmatched of int
type sample = (bool * bool * request) * (int * Bits.t * bool) option

type 'c t = {
  sample : (sample, 'c) Sig.t;
  data_bytes : int;
  pending : (int, transaction) Hashtbl.t;
  mutable since : int option;
  mutable max : int;
}

let bind (c : _ Core.t) scope (p : Platform.tlul) =
  let sc = Core.scope c scope in
  let n x = p.tl_prefix ^ x in
  let b x = Bind.signal sc (n x) Bind.bool and u x = Bind.signal sc (n x) Bind.uint in
  let data x = Bind.signal sc (n x) { Bind.bits with dwidth = Exact (8 * p.tl_data_bytes) } in
  let a =
    let open Sig in
    let+ valid = b "a_valid"
    and+ ready = b "a_ready"
    and+ opcode = u "a_bits_opcode"
    and+ size = u "a_bits_size"
    and+ source = u "a_bits_source"
    and+ address = u "a_bits_address"
    and+ mask = u "a_bits_mask"
    and+ data = data "a_bits_data" in
    (valid, valid && ready, { opcode; size = 1 lsl size; source; address; mask; data })
  in
  let d =
    let open Sig in
    let+ valid = b "d_valid"
    and+ ready = if p.d_ready then b "d_ready" else Sig.const c.clk true
    and+ source = u "d_bits_source"
    and+ data = data "d_bits_data"
    and+ error = b "d_bits_error" in
    if valid && ready then Some (source, data, error) else None
  in
  {
    sample = Sig.map2 (fun a d -> (a, d)) a d;
    data_bytes = p.tl_data_bytes;
    pending = Hashtbl.create 4;
    since = None;
    max = 0;
  }

let sample t = t.sample

let step t cycle ((valid, fire, req), d) =
  let responded =
    match d with
    | None -> []
    | Some (source, response, error) -> (
        match Hashtbl.find_opt t.pending source with
        | None -> [ Unmatched source ]
        | Some x ->
            Hashtbl.remove t.pending source;
            [ Responded { x with responded = Some cycle; response; error } ])
  in
  let accepted =
    if fire then begin
      let x =
        {
          request = req;
          requested = Option.value t.since ~default:cycle;
          accepted = cycle;
          responded = None;
          response = Bits.zero (8 * t.data_bytes);
          error = false;
        }
      in
      Hashtbl.replace t.pending req.source x;
      t.max <- max t.max (Hashtbl.length t.pending);
      [ Accepted x ]
    end
    else []
  in
  t.since <- (if valid && not fire then Some (Option.value t.since ~default:cycle) else None);
  accepted @ responded

let max_outstanding t = t.max
