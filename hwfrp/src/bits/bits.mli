[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** Immutable 2-state bit vectors. Bit 0 is the LSB. Widths up to 62 bits are held in a native int, wider
    values in little-endian bytes. *)

type t

val width : t -> int
val zero : int -> t

val of_int : width:int -> int -> t
(** The value modulo [2^width]. For widths above 62 the int must be non-negative. *)

val of_int64 : width:int -> int64 -> t
(** The 64-bit pattern, unsigned, truncated to [width]. *)

val of_bytes_le : width:int -> bytes -> t

val of_bytes_be : width:int -> bytes -> t option
(** A big-endian number, as ovcd's [Value.Bytes]; [None] when a bit at or above [width] is set. *)

val to_int : t -> int option
(** [None] when a bit at or above 62 is set. *)

val to_int_exn : t -> int
val to_int64 : t -> int64 option
val to_bytes_le : t -> bytes
val is_zero : t -> bool
val bit : t -> int -> bool
val field : t -> lo:int -> width:int -> t
val field_int : t -> lo:int -> width:int -> int

val concat : t list -> t
(** The first element is the most significant. *)

val equal : t -> t -> bool
val compare : t -> t -> int
val popcount : t -> int

val to_hex : t -> string
(** Zero-padded to the width. *)

val pp : Format.formatter -> t -> unit
