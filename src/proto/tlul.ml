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
  outstanding : int;
}

let is_get r = r.opcode = 4

let value ~data_bytes r data =
  let lane = r.address land (data_bytes - 1) in
  Bits.field_int data ~lo:(8 * lane) ~width:(8 * min 8 (min r.size (data_bytes - lane)))

type event = Accepted of transaction | Responded of transaction | Unmatched of int
type sample = (bool * bool * request) * (int * Bits.t * bool) option
type 'c t = { sample : (sample, 'c) Sig.t; data_bytes : int }

module IM = Map.Make (Int)

type state = { pending : transaction IM.t; since : int option; max : int }

let init = { pending = IM.empty; since = None; max = 0 }

type names = { prefix : string; d_ready : bool }

let bind sc (p : names) ~data_bytes =
  let n x = p.prefix ^ x in
  let b x = Bind.signal sc (n x) Bind.bool and u x = Bind.signal sc (n x) Bind.uint in
  let data x = Bind.signal sc (n x) { Bind.bits with dwidth = Exact (8 * data_bytes) } in
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
    and+ ready = if p.d_ready then b "d_ready" else Sig.const (Bind.clock_of sc) true
    and+ source = u "d_bits_source"
    and+ data = data "d_bits_data"
    and+ error = b "d_bits_error" in
    if valid && ready then Some (source, data, error) else None
  in
  { sample = Sig.map2 (fun a d -> (a, d)) a d; data_bytes }

let sample t = t.sample

let step t s cycle ((valid, fire, req), d) =
  let pending, responded =
    match d with
    | None -> (s.pending, [])
    | Some (source, response, error) -> (
        match IM.find_opt source s.pending with
        | None -> (s.pending, [ Unmatched source ])
        | Some x ->
            ( IM.remove source s.pending,
              [ Responded { x with responded = Some cycle; response; error } ] ))
  in
  let pending, accepted =
    if fire then
      let x =
        {
          request = req;
          requested = Option.value s.since ~default:cycle;
          accepted = cycle;
          responded = None;
          response = Bits.zero (8 * t.data_bytes);
          error = false;
          outstanding = (IM.cardinal pending + 1 - if IM.mem req.source pending then 1 else 0);
        }
      in
      (IM.add req.source x pending, [ Accepted x ])
    else (pending, [])
  in
  let since = if valid && not fire then Some (Option.value s.since ~default:cycle) else None in
  ({ pending; since; max = max s.max (IM.cardinal pending) }, accepted @ responded)

let max_outstanding s = s.max

let to_transaction t =
  {
    Transaction.id = t.request.source;
    write = not (is_get t.request);
    address = t.request.address;
    bytes = t.request.size;
    beats = 1;
    requested = t.requested;
    accepted = t.accepted;
    first_data = (if is_get t.request then t.responded else Some t.accepted);
    completed = t.responded;
    status = (if t.error then 2 else 0);
    outstanding = t.outstanding;
  }
