[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

type t = {
  driver : (module Target_intf.Target.DRIVER);
  features : Target_config.spec option;
  cache : (int, string) Hashtbl.t;
}

let driver definition =
  let module C =
    Riscv_family.Make_with
      (Riscv32_encode.Profile)
      (struct
        let definition = definition
      end)
  in
  let module D = Driver.Pipeline.Make (C) in
  (module D : Target_intf.Target.DRIVER)

let create ?(features = "+" ^ Coral_zvt.feature) () =
  match Coral_zvt.definition () with
  | Error e -> Error e
  | Ok definition -> (
      match Target_config.parse_spec features with
      | Error e -> Error e
      | Ok spec ->
          Ok { driver = driver definition; features = Some spec; cache = Hashtbl.create 256 })

let decode t word =
  let (module D) = t.driver in
  let b = Bytes.create 4 in
  Bytes.set_int32_le b 0 (Int32.of_int word);
  match D.dump_disasm_canonical ?features:t.features ~address:0L (Bytes.to_string b) with
  | Ok s -> Ok (String.trim s)
  | Error e ->
      Error (String.trim (Foundation.Diagnostic.render_all (Foundation.Diag.diagnostics e)))

let disasm t word =
  match Hashtbl.find_opt t.cache word with
  | Some s -> s
  | None ->
      let s =
        match decode t word with Ok s -> s | Error _ -> Printf.sprintf ".word 0x%08x" word
      in
      Hashtbl.add t.cache word s;
      s
