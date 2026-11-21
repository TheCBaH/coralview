[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(** The window [--between-pc], [--around-symbol] and [--entry] name: found in the retired instructions of a
    run, which the run that prints the window supplies, so the trace is read once. *)

type spec =
  | Between of int * int
      (** From the Nth retirement of the first PC to the next one of the second. *)
  | Around of string  (** From a function's entry to the first [ret] retired inside it. *)
  | Entry of string
      (** From a function's entry to the [ret] that pops its frame, or to the end if there is none. *)

type t

val make : spec -> nth:int -> Symbols.t option -> (t, int * string) result
(** [Error (code, message)]: a function that needs an ELF and has none, or is not in it, or is not one. *)

val find : t -> Commits.commit list -> (int * int, int * string) result
(** The first and last retire cycle of the window, from all the retirements in order; the last is [max_int]
    for an [Entry] that never returns. [Error] when the start retires fewer times than asked or the end
    never follows it. *)

val narrow : Text.window -> int * int -> Text.window
(** The cycles both the window and the markers select. *)

val resolve : t -> Text.window -> Commits.commit list -> (Text.window, int * string) result
(** {!find} and {!narrow}. *)
