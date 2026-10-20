[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Vcd_types

type t = { bits : Bits.t; unknown : Bits.t }
type decode_error = Not_a_vector of Value.t | Too_wide of { width : int; bytes : int }

let known bits = { bits; unknown = Bits.zero (Bits.width bits) }
let width t = Bits.width t.bits

let unknown w =
  let ones = Bytes.make ((w + 7) / 8) '\255' in
  { bits = Bits.zero w; unknown = Bits.of_bytes_le ~width:w ones }

let is_known t = Bits.is_zero t.unknown
let to_known t = if is_known t then Some t.bits else None

let of_value ~width (v : Value.t) =
  match v with
  | Int n -> Ok (known (Bits.of_int ~width n))
  | Int64 n -> Ok (known (Bits.of_int64 ~width n))
  | Bytes _ | Scalar _ | Scalars _ -> (
      match Packed.of_value ~width v with
      | Ok { bits; unknown } ->
          Ok { bits = Bits.of_bytes_le ~width bits; unknown = Bits.of_bytes_le ~width unknown }
      | Error (Not_a_vector v) -> Error (Not_a_vector v)
      | Error (Too_wide { width; bytes }) -> Error (Too_wide { width; bytes }))
  | Real _ | Other _ | Port _ | String _ -> Error (Not_a_vector v)

let to_string t =
  String.init (width t) (fun i ->
      let k = width t - 1 - i in
      match (Bits.bit t.unknown k, Bits.bit t.bits k) with
      | false, false -> '0'
      | false, true -> '1'
      | true, false -> 'x'
      | true, true -> 'h')

let pp_decode_error ppf = function
  | Not_a_vector v -> Format.fprintf ppf "not a bit vector: %s" (Value.to_string v)
  | Too_wide { width; bytes } ->
      Format.fprintf ppf "%d-byte value wider than its %d-bit signal" bytes width
