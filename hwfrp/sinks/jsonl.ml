[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

let lines ?header records =
  let records = Seq.map Json.to_string records in
  match header with None -> records | Some h -> Seq.cons (Json.to_string h) records

let to_string ?header records = Lines.to_string (lines ?header records)
let output oc ?header records = Lines.output oc (lines ?header records)
