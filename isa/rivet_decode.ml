[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

module Cls = Rivet_riscv_family_encode.Riscv_types.Cls

type instruction = { mnemonic : string; feature : string option; cls : Cls.t }

type t = {
  driver : (module Rivet_target_intf.Target.DRIVER);
  features : Rivet_target_features.Config.spec option;
  cache : (int, string) Hashtbl.t;
  instruction : int -> (instruction, string) result;
  decoded : (int, (instruction, string) result) Hashtbl.t;
  assemble : string -> (string, string) result;
  needs : int -> string list;
}

let render e =
  String.trim (Rivet_foundation.Diagnostic.render_all (Rivet_foundation.Diag.diagnostics e))

let word_bytes word =
  let b = Bytes.create 4 in
  Bytes.set_int32_le b 0 (Int32.of_int word);
  Bytes.to_string b

let driver definition spec =
  let module C =
    Rivet_riscv_family.Make_with
      (Rivet_riscv32_encode.Profile)
      (struct
        let definition = definition
      end) in
  let module D = Rivet_text_pipeline.Pipeline.Make (C) in
  let decode_under config word =
    let state = C.initial_state config in
    match C.decode { C.state; address = 0L } (word_bytes word) ~pos:0 with
    | Ok (i, _, _) ->
        let feature = match i.op with C.Opcode.Table r -> Some (C.Row.feature r) | _ -> None in
        let cls = Cls.of_word ~xlen:32 (Int64.of_int word) in
        Ok { mnemonic = C.Opcode.name i.op; feature; cls }
    | Error _ -> Error (Printf.sprintf "no instruction form for %08x" word)
  in
  let instruction =
    match Rivet_target_features.Config.resolve C.components spec with
    | Error e -> fun _ -> Error e
    | Ok config -> decode_under config
  in
  (* The features that, each added to the spec alone, make the word decode. *)
  let needs word =
    let known =
      Rivet_target_features.Config.features (Rivet_target_features.Config.all_enabled C.components)
    in
    List.filter
      (fun f ->
        match
          Rivet_target_features.Config.resolve C.components
            (spec @ [ Rivet_target_features.Config.Enable f ])
        with
        | Error _ -> false
        | Ok config -> Result.is_ok (decode_under config word))
      known
  in
  let assemble text =
    let source = Rivet_foundation.Span.source ~name:"coral.s" ~contents:(".text\n" ^ text) in
    let features = Option.some spec in
    match D.assemble ?features ~unit_name:"coral" ~source () with
    | Error e -> Error (render e)
    | Ok laid_out -> (
        let plan = Rivet_image.plan_of laid_out in
        let addresses =
          List.map
            (fun (s : Rivet_image.segment_plan) -> (s.Rivet_image.seg_name, 0L))
            plan.Rivet_image.segments
        in
        match Rivet_image.bind_image laid_out ~addresses with
        | Error e -> Error (render e)
        | Ok img -> (
            match img.Rivet_image.segments with s :: _ -> Ok s.Rivet_image.bytes | [] -> Ok ""))
  in
  ((module D : Rivet_target_intf.Target.DRIVER), instruction, assemble, needs)

let create ?(features = "+" ^ Coral_zvt.feature ^ ",+" ^ Coral_zvt.system_feature) () =
  match Coral_zvt.definition () with
  | Error e -> Error e
  | Ok definition -> (
      match Rivet_target_features.Config.parse_spec features with
      | Error e -> Error e
      | Ok spec ->
          let driver, instruction, assemble, needs = driver definition spec in
          Ok
            {
              driver;
              features = Some spec;
              cache = Hashtbl.create 256;
              instruction;
              decoded = Hashtbl.create 256;
              assemble;
              needs;
            })

let decode t word =
  let (module D) = t.driver in
  match D.dump_disasm_canonical ?features:t.features ~address:0L (word_bytes word) with
  | Ok s -> Ok (String.trim s)
  | Error e -> Error (render e)

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

let assemble t text = t.assemble text
let needs t word = if Result.is_ok (instruction t word) then [] else t.needs word

let spec_of_extensions ~extensions ~matrix =
  let known = List.filter (fun e -> e <> "i") extensions in
  String.concat ","
    (("none" :: List.map (fun e -> "+" ^ e) known)
    @ [ "+system"; "+" ^ Coral_zvt.system_feature ]
    @ if matrix then [ "+" ^ Coral_zvt.feature ] else [])
