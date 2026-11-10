[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

let output oc lines =
  Seq.iter
    (fun l ->
      output_string oc l;
      output_char oc '\n')
    lines

let to_string lines =
  let b = Buffer.create 4096 in
  Seq.iter
    (fun l ->
      Buffer.add_string b l;
      Buffer.add_char b '\n')
    lines;
  Buffer.contents b
