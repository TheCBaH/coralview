[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

type instruction = { mnemonic : string; feature : string option }

type t = {
  driver : (module Target_intf.Target.DRIVER);
  features : Target_config.spec option;
  cache : (int, string) Hashtbl.t;
  instruction : int -> (instruction, string) result;
  decoded : (int, (instruction, string) result) Hashtbl.t;
}

let word_bytes word =
  let b = Bytes.create 4 in
  Bytes.set_int32_le b 0 (Int32.of_int word);
  Bytes.to_string b

let driver definition spec =
  let module C =
    Riscv_family.Make_with
      (Riscv32_encode.Profile)
      (struct
        let definition = definition
      end)
  in
  let module D = Driver.Pipeline.Make (C) in
  let instruction =
    match Target_config.resolve C.components spec with
    | Error e -> fun _ -> Error e
    | Ok config -> (
        let state = C.initial_state config in
        fun word ->
          match C.decode { C.state; address = 0L } (word_bytes word) ~pos:0 with
          | Ok (i, _, _) ->
              let feature =
                match i.op with C.Opcode.Table r -> Some C.table_rows.(r).feature | _ -> None
              in
              Ok { mnemonic = C.Opcode.name i.op; feature }
          | Error _ -> Error (Printf.sprintf "no instruction form for %08x" word))
  in
  ((module D : Target_intf.Target.DRIVER), instruction)

let create ?(features = "+" ^ Coral_zvt.feature) () =
  match Coral_zvt.definition () with
  | Error e -> Error e
  | Ok definition -> (
      match Target_config.parse_spec features with
      | Error e -> Error e
      | Ok spec ->
          let driver, instruction = driver definition spec in
          Ok
            {
              driver;
              features = Some spec;
              cache = Hashtbl.create 256;
              instruction;
              decoded = Hashtbl.create 256;
            })

let decode t word =
  let (module D) = t.driver in
  match D.dump_disasm_canonical ?features:t.features ~address:0L (word_bytes word) with
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

let instruction t word =
  match Hashtbl.find_opt t.decoded word with
  | Some r -> r
  | None ->
      let r = t.instruction word in
      Hashtbl.add t.decoded word r;
      r
