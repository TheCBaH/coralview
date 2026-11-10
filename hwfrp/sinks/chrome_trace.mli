[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(** A Chrome trace (the JSON trace event format), which ui.perfetto.dev and chrome://tracing load: one
    process per analysis, a named lane (thread) per stream, spans, instants and counters. Time is an
    integer, whatever unit the caller uses (cycles, T-states, nanoseconds). *)

type event =
  | Span of { lane : string; name : string; start : int; stop : int; args : (string * Json.t) list }
      (** [stop] is included, so a span of one sample is [start = stop]. Drawn at least one unit wide. *)
  | Instant of { lane : string; name : string; at : int; args : (string * Json.t) list }
  | Counter of { name : string; at : int; value : int }
      (** A track of its own per name within the process. *)

type process = {
  name : string;
  lanes : string list;
      (** Numbered in this order from 1, ahead of the lanes first used by an event. *)
  events : event list;  (** Written in this order. *)
}

val to_string : ?time_unit:string -> process list -> string
(** [time_unit] is the viewer's display unit (["ms"], ["ns"]; default ["ns"]). Processes are numbered
    from 1; a lane's name is written the first time it is used. *)

val output : out_channel -> ?time_unit:string -> process list -> unit

val occupancy : name:string -> (int * int option) list -> last:int -> event list
(** The count of intervals open at each time where it changes, as {!Counter}s. An interval is
    (start, stop included); [None] runs to [last]. *)
