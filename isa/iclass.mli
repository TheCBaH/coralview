[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(** The class of an instruction, by what its cost depends on: for a cycle model fitted per class. *)

type t =
  | Alu  (** Scalar integer, including multiply and divide. *)
  | Fp  (** Scalar floating point arithmetic and conversions. *)
  | Mem  (** Scalar loads, stores and atomics, floating point ones included. *)
  | Branch  (** Branches and jumps. *)
  | Vector  (** Vector arithmetic, moves and configuration. *)
  | Vector_mem  (** Vector loads and stores. *)
  | Tile  (** Coral's Zvt matrix instructions ({!Coral_zvt.feature}). *)
  | System  (** CSR, fences, traps, [wfi], [mpause]. *)

val all : t list
val name : t -> string
val of_name : string -> t option

val of_mnemonic : ?feature:string -> string -> t
(** The class of a mnemonic, with the Rivet feature of its table row when it has one: every
    {!Coral_zvt.feature} row is a {!Tile}, whatever its name. *)

val of_instruction : Rivet_decode.instruction -> t
