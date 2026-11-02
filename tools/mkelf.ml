(* A tiny RV32 ELF for the tests: mkelf OUT ADDR NAME:SIZE...; the functions follow each other from
   ADDR (hex), each filled with nops. *)
let () =
  let open Elf in
  match Array.to_list Sys.argv with
  | _ :: out :: addr :: funcs when funcs <> [] -> (
      let addr = Int64.of_string ("0x" ^ addr) in
      let funcs =
        List.map
          (fun f ->
            match String.split_on_char ':' f with
            | [ name; size ] -> (name, int_of_string size)
            | _ -> failwith ("bad function " ^ f))
          funcs
      in
      let total = List.fold_left (fun n (_, s) -> n + s) 0 funcs in
      let text =
        {
          Exec.name = ".text";
          addr;
          align = 4L;
          content =
            Exec.Bytes (String.concat "" (List.init (total / 4) (fun _ -> "\x13\x00\x00\x00")));
        }
      in
      let symbols, _ =
        List.fold_left
          (fun (acc, at) (name, size) ->
            ( {
                Exec.name;
                value = at;
                size = Int64.of_int size;
                kind = `Func;
                binding = `Global;
                section = Some ".text";
              }
              :: acc,
              Int64.add at (Int64.of_int size) ))
          ([], addr) funcs
      in
      let spec =
        {
          Exec.target = Target.riscv Riscv.rv32imafd_ilp32d;
          entry = addr;
          headers = Exec.Unmapped;
          gnu_stack = None;
          section_headers = true;
          symbols = List.rev symbols;
          segments =
            [
              {
                Exec.perms = { Exec.read = true; write = false; execute = true };
                paddr = None;
                sections = [ text ];
              };
            ];
        }
      in
      match Exec.build spec with
      | Ok bytes -> Out_channel.with_open_bin out (fun oc -> output_string oc bytes)
      | Error _ ->
          prerr_endline "mkelf: cannot build";
          exit 1)
  | _ ->
      prerr_endline "usage: mkelf OUT ADDR NAME:SIZE...";
      exit 2
