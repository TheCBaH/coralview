[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

type t = { start : int; stop : int option }

let length s = Option.map (fun e -> e - s.start + 1) s.stop
