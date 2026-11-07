(* A tiny RV32 ELF for the tests: mkelf [--strip] OUT ADDR FUNCTION...; the functions follow each other
   from ADDR (hex). A FUNCTION is NAME:SIZE, filled with nops, or NAME=WORD,... in hex, where a word
   written dWORD is data and gets a $d mapping symbol. --strip leaves out the symbols. *)
let word_bytes w = String.init 4 (fun i -> Char.chr ((w lsr (8 * i)) land 0xff))

let () =
  let open Elf in
  let args = List.tl (Array.to_list Sys.argv) in
  let strip, args = match args with "--strip" :: r -> (true, r) | r -> (false, r) in
  match args with
  | out :: addr :: funcs when funcs <> [] -> (
      let addr = Int64.of_string ("0x" ^ addr) in
      (* Each function: its name, its words, and which of them are data. *)
      let funcs =
        List.map
          (fun f ->
            match (String.split_on_char ':' f, String.split_on_char '=' f) with
            | [ name; size ], [ _ ] ->
                (name, List.init (int_of_string size / 4) (fun _ -> (0x13, false)))
            | _, [ name; words ] ->
                ( name,
                  List.map
                    (fun w ->
                      if w.[0] = 'd' then
                        (int_of_string ("0x" ^ String.sub w 1 (String.length w - 1)), true)
                      else (int_of_string ("0x" ^ w), false))
                    (String.split_on_char ',' words) )
            | _ -> failwith ("bad function " ^ f))
          funcs
      in
      let text =
        {
          Exec.name = ".text";
          addr;
          align = 4L;
          content =
            Exec.Bytes
              (String.concat ""
                 (List.concat_map (fun (_, ws) -> List.map (fun (w, _) -> word_bytes w) ws) funcs));
        }
      in
      let symbols, _ =
        List.fold_left
          (fun (acc, at) (name, ws) ->
            let sym name kind binding value size =
              { Exec.name; value; size; kind; binding; section = Some ".text" }
            in
            let data =
              List.concat
                (List.mapi
                   (fun i (_, d) ->
                     if d then [ sym "$d" `Notype `Local (Int64.add at (Int64.of_int (4 * i))) 0L ]
                     else [])
                   ws)
            in
            ( data @ (sym name `Func `Global at (Int64.of_int (4 * List.length ws)) :: acc),
              Int64.add at (Int64.of_int (4 * List.length ws)) ))
          ([], addr) funcs
      in
      let symbols = if strip then [] else symbols in
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
      prerr_endline "usage: mkelf [--strip] OUT ADDR FUNCTION...";
      exit 2
