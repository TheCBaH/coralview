[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** A Chrome trace (JSON trace event format), which ui.perfetto.dev and chrome://tracing load: one
    process per analysis, a named track (thread) per hardware stream, slices for spans and counters.
    Time is in cycles, written as microseconds. *)

type slice = {
  track : string;  (** E.g. ["axi id 0 lsu"], ["lane 1"]. *)
  name : string;
  start : int;
  stop : int;  (** Included. *)
  args : (string * string) list;
}

type counter = { c_track : string; cycle : int; value : int }
type process = { process : string; slices : slice list; counters : counter list }

val write : out_channel -> process list -> unit
(** Tracks are numbered in order of first use within each process. *)

val occupancy : track:string -> (int * int option) list -> last:int -> counter list
(** The count of intervals (start, stop included; [None] runs to [last]) open at each cycle where it
    changes. *)
