[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** 4-state vectors. [unknown] has a 1 for every bit that is not 0 or 1 (X, Z, U, W, L, H, -); for those bits
    [bits] holds the weak value (L is 0, H is 1, the others 0). *)

type t = private { bits : Bits.t; unknown : Bits.t }

type decode_error =
  | Not_a_vector of Vcd_types.Value.t  (** Real, String, Port or Other. *)
  | Too_wide of { width : int; bytes : int }  (** A [Bytes] value with a 1 at or above [width]. *)

val known : Bits.t -> t
val unknown : int -> t
val width : t -> int
val is_known : t -> bool
val to_known : t -> Bits.t option

val of_value : width:int -> Vcd_types.Value.t -> (t, decode_error) result
(** Records shorter than [width] are extended as VCD specifies: with X or Z when their leftmost bit is X or
    Z, otherwise with 0. *)

val to_string : t -> string
(** MSB first; unknown bits print as [x], or [h] when their weak value is 1. *)

val pp_decode_error : Format.formatter -> decode_error -> unit
