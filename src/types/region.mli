[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** The memory regions of a platform, from an archive's [hardware-configurations.json]. *)

type t

val none : t
(** No manifest: no address has a region. *)

val of_manifest : Manifest.configuration -> t
val find : t -> int -> string option

val suffix : t -> int -> string
(** The text form: [""] without a manifest, else [" (name)"] or [" (unmapped)"]. *)
