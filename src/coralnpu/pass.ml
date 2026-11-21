[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

type 'r builder = { build : 'c. 'c Core.t -> Hwfrp.Sched.run_stats -> 'r }

let run ?gate p tr ~model b =
  let (Core.Any c) = Core.bind p tr ~model in
  let read = b.build c in
  let stats = Core.run ?gate c in
  let r = read stats in
  (r, List.of_seq (Hwfrp.Diag.stream c.net))

let collect (type k e s)
    (module A : Analysis.S with type Config.t = k and type Event.t = e and type Summary.t = s)
    (cfg : k) (c : _ Core.t) =
  let events = ref [] in
  let summary =
    Analysis.subscribe (module A) cfg { c with model = A.name } (fun e -> events := e :: !events)
  in
  fun stats -> (List.rev !events, summary stats)

let commits c =
  let read = collect (module Commits) () c in
  fun stats -> Commits.commits (fst (read stats))
