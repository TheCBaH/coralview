[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

let of_string ?select s =
  Hwfrp.Trace.of_parse ?select ~format:`Vcd (fun select -> Vcd.parse_string ?select s)

let of_channel ?select ic =
  Hwfrp.Trace.of_parse ?select ~format:`Vcd (fun select ->
      Vcd.parse_channel ?select ~strict:true ic)
