[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

type outcome = Complete | Cancelled | Failed
type format = [ `Text | `Jsonl | `Stderr ]
type record = { command : string; outcome : outcome; status : int option; signal : string option }

let current : (string * int) option ref = ref None
let active () = !current <> None

(* The descriptor number the producer writes the trace to. *)
let trace_fd : Unix.file_descr = Obj.magic 3

let start command =
  let read_end, write_end = Unix.pipe ~cloexec:true () in
  flush_all ();
  match Unix.fork () with
  | 0 -> (
      try
        if write_end = trace_fd then Unix.clear_close_on_exec write_end
        else Unix.dup2 ~cloexec:false write_end trace_fd;
        Unix.execv "/bin/sh" [| "sh"; "-c"; command |]
      with _ -> Unix._exit 127)
  | pid ->
      Unix.close write_end;
      if read_end <> Unix.stdin then begin
        Unix.dup2 read_end Unix.stdin;
        Unix.close read_end
      end;
      current := Some (command, pid)

let signal_name n =
  List.assoc_opt n
    [
      (Sys.sigpipe, "SIGPIPE"); (Sys.sigterm, "SIGTERM"); (Sys.sigkill, "SIGKILL");
      (Sys.sigint, "SIGINT"); (Sys.sigabrt, "SIGABRT"); (Sys.sigsegv, "SIGSEGV");
    ]
  |> Option.value ~default:("signal " ^ string_of_int n)

let rec wait_until pid deadline =
  match Unix.waitpid [ WNOHANG ] pid with
  | 0, _ ->
      if Unix.gettimeofday () > deadline then None
      else begin
        ignore (Unix.select [] [] [] 0.05);
        wait_until pid deadline
      end
  | _, status -> Some status
  | exception Unix.Unix_error (EINTR, _, _) -> wait_until pid deadline

(* Whether the stream was read to its end: the pipe has nothing more and its writer has gone. *)
let at_end () =
  try
    Unix.set_nonblock Unix.stdin;
    Unix.read Unix.stdin (Bytes.create 1) 0 1 = 0
  with Unix.Unix_error ((EAGAIN | EWOULDBLOCK), _, _) -> false | Unix.Unix_error _ -> true

let describe = function
  | Unix.WEXITED n -> (Some n, None)
  | WSIGNALED n | WSTOPPED n -> (None, Some (signal_name n))

let to_text r =
  let how =
    match (r.status, r.signal) with
    | Some n, _ -> Printf.sprintf "exited with status %d" n
    | None, Some s -> "ended by " ^ s
    | None, None -> "ended"
  in
  match r.outcome with
  | Complete -> "# producer: complete, " ^ how ^ "\n"
  | Cancelled -> "# producer: cancelled by the consumer, " ^ how ^ "\n"
  | Failed -> "# producer: failed, " ^ how ^ "; the trace may be incomplete\n"

let outcome_name = function Complete -> "complete" | Cancelled -> "cancelled" | Failed -> "failed"

let record_jsont =
  Codec.record "producer" (fun command outcome status signal ->
      let outcome =
        match outcome with
        | "complete" -> Complete
        | "cancelled" -> Cancelled
        | _ -> Failed
      in
      { command; outcome; status; signal })
  |> Jsont.Object.mem "command" Jsont.string ~enc:(fun r -> r.command)
  |> Jsont.Object.mem "outcome" Jsont.string ~enc:(fun r -> outcome_name r.outcome)
  |> Codec.opt (fun r -> r.status) "status" Jsont.int
  |> Codec.opt (fun r -> r.signal) "signal" Jsont.string
  |> Jsont.Object.finish

let finish ~format code =
  match !current with
  | None -> code
  | Some (command, pid) ->
      current := None;
      let complete = at_end () in
      (* The producer sees the closed pipe at its next write. *)
      (try Unix.close Unix.stdin with Unix.Unix_error _ -> ());
      let status =
        match wait_until pid (Unix.gettimeofday () +. 10.) with
        | Some status -> status
        | None ->
            Unix.kill pid Sys.sigterm;
            (match wait_until pid (Unix.gettimeofday () +. 10.) with
            | Some status -> status
            | None ->
                Unix.kill pid Sys.sigkill;
                snd (Unix.waitpid [] pid))
      in
      let exit_status, signal = describe status in
      let outcome =
        match (exit_status, signal) with
        | Some 0, _ -> if complete then Complete else Cancelled
        | Some 141, _ | None, Some "SIGPIPE" -> if complete then Failed else Cancelled
        | _ -> Failed
      in
      let record = { command; outcome; status = exit_status; signal } in
      (match format with
      | `Text ->
          flush stdout;
          print_string (to_text record);
          flush stdout
      | `Jsonl ->
          flush stdout;
          print_endline (Codec.to_line record_jsont record)
      | `Stderr -> prerr_string (to_text record));
      if outcome = Failed && code = 0 then 4 else code
