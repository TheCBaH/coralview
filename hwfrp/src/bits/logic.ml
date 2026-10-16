[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Vcd_types

type t = { bits : Bits.t; unknown : Bits.t }
type decode_error = Not_a_vector of Value.t | Byte_count of { width : int; bytes : int }

let known bits = { bits; unknown = Bits.zero (Bits.width bits) }
let width t = Bits.width t.bits

let unknown w =
  let ones = Bytes.make ((w + 7) / 8) '\255' in
  { bits = Bits.zero w; unknown = Bits.of_bytes_le ~width:w ones }

let is_known t = Bits.is_zero t.unknown
let to_known t = if is_known t then Some t.bits else None

let of_logic_list ~width ls =
  let a = Array.of_list ls in
  let n = Array.length a in
  let ext =
    match a with
    | [||] -> Value.B0
    | _ -> ( match a.(0) with (Value.X | Value.Z) as l -> l | _ -> Value.B0)
  in
  let nb = (width + 7) / 8 in
  let bits = Bytes.make nb '\000' and unk = Bytes.make nb '\000' in
  let set b k =
    let i = k lsr 3 in
    Bytes.set_uint8 b i (Bytes.get_uint8 b i lor (1 lsl (k land 7)))
  in
  for k = 0 to width - 1 do
    match if k < n then a.(n - 1 - k) else ext with
    | Value.B0 -> ()
    | B1 -> set bits k
    | H ->
        set bits k;
        set unk k
    | X | Z | U | W | L | Dont_care -> set unk k
  done;
  { bits = Bits.of_bytes_le ~width bits; unknown = Bits.of_bytes_le ~width unk }

let of_value ~width (v : Value.t) =
  match v with
  | Int n -> Ok (known (Bits.of_int ~width n))
  | Int64 n -> Ok (known (Bits.of_int64 ~width n))
  | Bytes b ->
      if Bytes.length b = (width + 7) / 8 then Ok (known (Bits.of_bytes_msb_first ~width b))
      else Error (Byte_count { width; bytes = Bytes.length b })
  | Scalar l -> Ok (of_logic_list ~width [ l ])
  | Scalars ls -> Ok (of_logic_list ~width ls)
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
  | Byte_count { width; bytes } ->
      Format.fprintf ppf "%d-bit signal with a %d-byte value" width bytes
