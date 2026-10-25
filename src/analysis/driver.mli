[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(** A trace producer that coralview starts and waits for. [start] runs a shell command with a pipe on
    its descriptor 3 and makes the pipe's read end the standard input, so that the trace [-] is the
    producer's VCD stream. How the producer ended is part of the output, because the end of a stream
    does not say whether the run completed. *)

type outcome =
  | Complete  (** The stream ended and the producer exited with status 0. *)
  | Cancelled  (** The consumer stopped reading first; the producer was ended by the closed pipe. *)
  | Failed  (** The producer exited with a nonzero status or was killed. *)

type format = [ `Text | `Jsonl | `Stderr ]
(** Where {!finish} writes: the standard output in the command's format, or the standard error. *)

val start : string -> unit
(** Runs the command with [sh -c]. Its descriptor 3 is the write end of the stream; its other
    descriptors are the caller's. *)

val active : unit -> bool

type record = {
  command : string;
  outcome : outcome;
  status : int option;  (** The exit status. *)
  signal : string option;  (** The signal that ended it. *)
}

val record_jsont : record Jsont.t
(** [{"type":"producer","command":…,"outcome":…,"status":…,"signal":…}]. *)

val to_text : record -> string
(** [# producer: …], one line. *)

val finish : format:format -> int -> int
(** Closes the stream, waits for the producer (ending it if it does not exit) and writes how it ended.
    Returns the exit code for the given one: [4] if the producer failed and the code was [0]. Does
    nothing, and returns the code, if no producer was started. *)
