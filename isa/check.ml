[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

let () =
  match Coral_isa.Roundtrip.run () with
  | checked, [] -> Printf.printf "%d Zvt words round-trip through Rivet\n" checked
  | _, failures ->
      List.iter prerr_endline failures;
      Printf.eprintf "%d failures\n" (List.length failures);
      exit 1
