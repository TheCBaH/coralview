[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(** The analyses a platform can have, in one list: each as a first-class {!Analysis.S} with how the common
    options configure it and which views it has. *)

type opts = {
  region : Region.t;
  features : string option;  (** Rivet's feature spec for disassembly. *)
  window : Text.window;
  limit : int;
  profile : int;  (** Rows; 0 for none. *)
  at : int option;
  beats : int;
  ops : Ops.Config.t;
}
(** What the common options of a command say to an analysis. A command that has no such option leaves its
    default. *)

val default : opts

type t =
  | M : {
      a : (module Analysis.S with type Config.t = 'k and type Event.t = 'e and type Summary.t = 's);
      cfg : opts -> 'k;
      text : opts -> Text.ctx -> Format.formatter -> (unit -> 's) -> 'e Text.sink;
      status : 's -> int;  (** The exit status the summary asks for. *)
      profile : (Text.ctx -> Format.formatter -> (unit -> 's) -> 'e Text.sink) option;
      perfetto : (Text.ctx -> 'e Seq.t -> 's -> Perfetto.process) option;
    }
      -> t

val all : t list
(** In the order [platforms] and [check] list them. *)

val name : t -> string
val needs : t -> string list
val find : string -> t option

val available : Platform.t -> t list
(** Those whose blocks the platform describes. *)

val subscribe : t -> 'c Core.t -> unit
(** Builds the analysis in a core's net with its default configuration and ignores the events: binding
    proves the platform's description against the trace. *)
