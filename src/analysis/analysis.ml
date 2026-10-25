[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Hwfrp

module type S = sig
  val name : string
  val doc : string
  val needs : string list

  module Config : sig
    type t

    val default : t
  end

  module Event : sig
    type t

    val jsont : t Jsont.t
    val cycle : t -> int
    val pc : t -> int option
  end

  module Summary : sig
    type t

    val jsont : t Jsont.t
  end

  val build : Config.t -> 'c Core.t -> (Event.t list, 'c) Ev.t * (Sched.run_stats -> Summary.t)
end

type ('e, 's) t = (module S with type Event.t = 'e and type Summary.t = 's)

type ('e, 's) pulled = {
  events : 'e Seq.t;
  summary : unit -> 's;
  diags : unit -> Diag.t list;
  stats : unit -> Sched.run_stats;
}

let pull (type k e s)
    (module A : S with type Config.t = k and type Event.t = e and type Summary.t = s) (cfg : k) p tr
    : (e, s) pulled =
  let (Core.Any c) = Core.bind p tr ~model:A.name in
  let ev, summary = A.build cfg c in
  let port = Port.create ev in
  let run = Core.start c in
  let summary = lazy (summary (Run.finish run)) in
  {
    events = Seq.concat_map List.to_seq (Port.seq run port);
    summary = (fun () -> Lazy.force summary);
    diags = (fun () -> List.of_seq (Diag.stream c.net));
    stats = (fun () -> Run.finish run);
  }

let subscribe (type k e s)
    (module A : S with type Config.t = k and type Event.t = e and type Summary.t = s) (cfg : k) c f
    =
  let ev, summary = A.build cfg c in
  Ev.subscribe ev (List.iter f);
  summary

let shared (c : _ Core.t) name ~inj ~prj build =
  match Option.bind (Hashtbl.find_opt c.deps name) prj with
  | Some x -> x
  | None ->
      let x = build () in
      Hashtbl.replace c.deps name (inj x);
      x

type ('e, 's) stream = {
  events : 'e Seq.t;
  diags : unit -> Diag.t list;
  stats : unit -> Sched.run_stats;
  summary : unit -> 's;
  pending : unit -> int;
  finish : unit -> unit;
}

let stream (type k e s)
    (module A : S with type Config.t = k and type Event.t = e and type Summary.t = s) (cfg : k) p tr
    : (e, s) stream =
  let (Core.Any c) = Core.bind p tr ~model:A.name in
  let ev, summary = A.build cfg c in
  let port = Port.create ev in
  let run = Core.start c in
  let next = Seq.to_dispenser (Seq.concat_map List.to_seq (Port.seq run port)) in
  let finished = ref false in
  let finish () =
    while (not !finished) && Option.is_some (next ()) do
      ()
    done;
    finished := true
  in
  let stats () =
    finish ();
    Run.finish run
  in
  {
    events = Seq.of_dispenser (fun () -> if !finished then None else next ());
    diags = (fun () -> List.of_seq (Diag.stream c.net));
    stats;
    summary = (fun () -> summary (stats ()));
    pending = (fun () -> Port.pending port);
    finish;
  }

let events_file m cfg p path = stream m cfg p (Trace.open_input path)
