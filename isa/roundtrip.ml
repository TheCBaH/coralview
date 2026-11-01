[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

let bytes word =
  let b = Bytes.create 4 in
  Bytes.set_int32_le b 0 (Int32.of_int word);
  Bytes.to_string b

let hex s =
  String.concat "" (List.init (String.length s) (fun i -> Printf.sprintf "%02x" (Char.code s.[i])))

(* Spellings of Coral's reference words (the matrix.elf release and the VME cocotb tests) and of
   standard words beside them. *)
let references =
  [
    (0x02a00513, "addi x10, x0, 42");
    (0x022180d7, "vadd.vv v1, v2, v3");
    (0x84b6f057, "msetmtype x13, x11");
    (0x880675d7, "msettn x11, x12");
    (0x881776d7, "msettm x13, x14");
    (0x882877d7, "msettk x15, x16");
    (0x8841f057, "msetmtypei 3, 0, 0");
    (0x9841f057, "msetmtypei 3, 0, 1");
    (0x43e06057, "vtzero mt0");
    (0x43c06057, "vtdiscard");
    (0x43fa6257, "vtmv.v.t v4, x20");
    (0x5e456057, "vtmv.t.v x10, v4");
    (0x12b57007, "vtle8 x11, 0(x10)");
    (0x52c17027, "vtse32 x12, 0(x2)");
    (0xf28800f7, "vtmms.tvv mt0, v8, v16");
    (0xf2881077, "vtfmm.tvv mt0, v8, v16");
    (0xf28810f7, "vtfmm.alt.tvv mt0, v8, v16");
    (0x08000073, "mpause");
    (0xb0002573, "csrr x10, mcycle");
    (0xb0205073, "csrwi minstret, 0");
    (0x34029073, "csrw mscratch, x5");
  ]

let run () =
  let failures = ref [] and checked = ref 0 in
  let fail fmt = Printf.ksprintf (fun s -> failures := s :: !failures) fmt in
  if Coral_zvt.zvt_version <> Coral_zvt.supported_zvt_version then
    fail "zvt.jsonl follows Zvt %s (coralnpu %s), but only %s is supported" Coral_zvt.zvt_version
      Coral_zvt.revision Coral_zvt.supported_zvt_version;
  (match Rivet_decode.create () with
  | Error e -> fail "create: %s" e
  | Ok d -> (
      let check ?mnemonic word =
        incr checked;
        match Rivet_decode.decode d word with
        | Error e -> fail "%08x: does not decode: %s" word e
        | Ok text -> (
            let name = List.hd (String.split_on_char ' ' text) in
            (match mnemonic with
            | Some m when m <> name -> fail "%08x: decodes as %s, not %s" word name m
            | _ -> ());
            match Rivet_decode.assemble d (text ^ "\n") with
            | Error e -> fail "%08x: %S does not assemble: %s" word text e
            | Ok b -> if b <> bytes word then fail "%08x: %S assembles to %s" word text (hex b))
      in
      let class_of word =
        match Rivet_decode.instruction d word with
        | Ok i -> Iclass.name (Iclass.of_instruction i)
        | Error e -> "error: " ^ e
      in
      let expect_class word expected =
        incr checked;
        let got = class_of word in
        if got <> expected then fail "%08x: class %s, not %s" word got expected
      in
      (match Coral_zvt.samples () with
      | Error e -> fail "samples: %s" e
      | Ok l ->
          List.iter
            (fun (mnemonic, word) ->
              check ~mnemonic word;
              expect_class word "tile")
            l);
      List.iter
        (fun (word, expected) -> expect_class word expected)
        [
          (0x02a00513, "alu");
          (0x02b50533, "alu");
          (0x02b54533, "alu");
          (0x00b50663, "branch");
          (0x0000006f, "branch");
          (0x00008067, "branch");
          (0x00052503, "mem");
          (0x00b52023, "mem");
          (0x00052087, "mem");
          (0x00b52227, "mem");
          (0x00007053, "fp");
          (0x003110d3, "fp");
          (0x0d05f557, "vector");
          (0x022180d7, "vector");
          (0x02056087, "vector-mem");
          (0x0200e3a7, "vector-mem");
          (0x02057027, "vector-mem");
          (0xb0202573, "system");
          (0x30200073, "system");
          (0x10500073, "system");
          (0x0ff0000f, "system");
          (0x08000073, "system");
        ];
      List.iter
        (fun (word, text) ->
          check word;
          match Rivet_decode.decode d word with
          | Ok t when t <> text -> fail "%08x: decodes as %S, not %S" word t text
          | _ -> ())
        references;
      (match Rivet_decode.decode d 0x72007007 with
      | Ok t -> fail "72007007: decodes as %S, but the RTL traps on vtle64" t
      | Error _ -> ());
      match Rivet_decode.assemble d "vtle64 x11, 0(x10)\n" with
      | Ok b -> fail "vtle64 assembles to %s" (hex b)
      | Error _ -> ()));
  (match Rivet_decode.create ~features:"none,+m,+zve32x" () with
  | Error e -> fail "create without xcoralzvt: %s" e
  | Ok d -> (
      (match Rivet_decode.assemble d "vtzero mt0\n" with
      | Ok b -> fail "vtzero assembles to %s without xcoralzvt" (hex b)
      | Error _ -> ());
      match Rivet_decode.assemble d "mpause\n" with
      | Ok b -> fail "mpause assembles to %s without xcoralsys" (hex b)
      | Error _ -> ()));
  (!checked, List.rev !failures)
