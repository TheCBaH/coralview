[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

let probe path =
  let { Vcd.header; simulation } = Vcd_fst.open_file path in
  let signals = Vcd.Resolver.fold (fun _ n -> n + 1) (Vcd.Resolver.make header) 0 in
  let times, changes, last =
    Seq.fold_left
      (fun (t, c, last) -> function
        | Vcd_ast.Timestamp ts -> (t + 1, c, Some ts)
        | Vcd_ast.Change _ -> (t, c + 1, last)
        | _ -> (t, c, last))
      (0, 0, None) simulation
  in
  Format.printf "signals %d@.timestamps %d@.changes %d@.last %a@." signals times changes
    (Format.pp_print_option Vcd_types.Timestamp.pp)
    last

let decode words =
  let (module D : Target_intf.Target.DRIVER) = Option.get (Driver.Registry.find "riscv32") in
  List.iter
    (fun w ->
      let w = int_of_string ("0x" ^ w) in
      let b = Bytes.create 4 in
      Bytes.set_int32_le b 0 (Int32.of_int w);
      match D.dump_disasm_diagnostic ~address:0L (Bytes.to_string b) with
      | Ok s -> print_string s
      | Error ds ->
          Printf.printf "%08x  error: %s\n" w
            (Foundation.Diagnostic.render_all (Foundation.Diag.diagnostics ds)))
    words

let () =
  match List.tl (Array.to_list Sys.argv) with
  | [ "probe"; path ] -> probe path
  | "decode" :: (_ :: _ as words) -> decode words
  | _ ->
      prerr_endline "usage: coralview probe FILE.fst | coralview decode HEXWORD...";
      exit 2
