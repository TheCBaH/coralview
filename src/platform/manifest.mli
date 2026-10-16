[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** The parts of a devcontainer.coralnpu archive's [hardware-configurations.json] (schema 1.0) that
    coralview uses: each configuration's RTL top level, ISA extensions, tile register count and memory
    regions. Other members are skipped. *)

type region = { region : string; base : int; size : int }

type configuration = {
  name : string;
  top_level : string option;  (** [None] for the instruction-set simulators. *)
  extensions : string list;
  tile_registers : int option;
  regions : region list;
}

type t = { configurations : configuration list }

val jsont : t Jsont.t
val load : string -> (t, string) result
val find : t -> string -> configuration option

val region_of : configuration -> int -> region option
(** The region holding an address. *)

val validate : t -> Platform.t -> (configuration, string) result
(** The platform's configuration, which must exist with its [top_level]; a VME block must have the
    configuration's tile register count. *)
