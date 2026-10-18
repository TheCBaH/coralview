[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

type t = {
  id : int;
  write : bool;
  address : int;
  bytes : int;
  beats : int;
  requested : int;
  accepted : int;
  first_data : int option;
  completed : int option;
  status : int;
  outstanding : int;
}

let latency t = Option.map (fun c -> c - t.accepted) t.completed
let span t = { Span.start = t.requested; stop = t.completed }
let throughput t = Option.map (fun n -> float t.bytes /. float n) (Span.length (span t))
