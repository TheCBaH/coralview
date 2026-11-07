[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

let open_file ?select path =
  Hwfrp.Trace.of_parse ?select ~format:(Vcd_fst.detect_file path) (fun select ->
      Vcd_fst.open_file ?select path)

let open_string ?select s =
  Hwfrp.Trace.of_parse ?select ~format:(Vcd_fst.detect_string s) (fun select ->
      Vcd_fst.open_string ?select s)

let open_input ?select path =
  if path = "-" then begin
    set_binary_mode_in stdin true;
    Hwfrp_vcd.of_channel ?select stdin
  end
  else open_file ?select path

let wall_clock = Unix.gettimeofday
