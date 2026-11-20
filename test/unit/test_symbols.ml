open Coralview

let elf =
  let open Elf in
  let target = Target.riscv Riscv.rv32imafd_ilp32d in
  let rx = { Exec.read = true; write = false; execute = true } in
  let text =
    {
      Exec.name = ".text";
      addr = 0x10000L;
      align = 4L;
      content = Exec.Bytes (String.make 0x40 '\x13');
    }
  in
  let symbol name value size kind =
    { Exec.name; value; size; kind; binding = `Global; section = Some ".text" }
  in
  let spec =
    {
      Exec.target;
      entry = 0x10000L;
      headers = Exec.Unmapped;
      gnu_stack = None;
      section_headers = true;
      symbols =
        [
          symbol "_start" 0x10000L 0x10L `Func;
          symbol "kernel" 0x10010L 0x20L `Func;
          symbol "tail" 0x10030L 0L `Func;
          symbol "table" 0x10038L 8L `Object;
        ];
      segments = [ { Exec.perms = rx; paddr = None; sections = [ text ] } ];
    }
  in
  match Exec.build spec with Ok bytes -> bytes | Error _ -> failwith "Exec.build"

let%expect_test "functions of the symbol table" =
  (match Symbols.of_string elf with
  | Error e -> print_endline e
  | Ok t ->
      List.iter
        (fun (f : Symbols.func) -> Printf.printf "%s %x %x\n" f.name f.address f.size)
        (Symbols.to_list t);
      List.iter
        (fun pc ->
          match Symbols.lookup t pc with
          | Some (f, off) -> Printf.printf "%x: %s+%d\n" pc f.name off
          | None -> Printf.printf "%x: -\n" pc)
        [ 0xfffc; 0x10000; 0x1001c; 0x10010; 0x1002f; 0x10030; 0x10037; 0x10038 ];
      Printf.printf "find kernel: %d, nope: %d\n"
        (List.length (Symbols.find t "kernel"))
        (List.length (Symbols.find t "nope")));
  [%expect
    {|
    _start 10000 10
    kernel 10010 20
    tail 10030 0
    fffc: -
    10000: _start+0
    1001c: kernel+12
    10010: kernel+0
    1002f: kernel+31
    10030: tail+0
    10037: -
    10038: -
    find kernel: 1, nope: 0 |}]

let%expect_test "not an ELF" =
  (match Symbols.of_string "hello" with Error e -> print_endline e | Ok _ -> print_endline "ok");
  [%expect {| e_ident at offset 0x0, size 0x10, extends past the 5-byte input |}]

(* Assembly without .type or .size: untyped labels in code, an alias around a smaller function, and untyped
   symbols that are not code. *)
let asm_elf =
  let open Elf in
  let target = Target.riscv Riscv.rv32imafd_ilp32d in
  let rx = { Exec.read = true; write = false; execute = true } in
  let rw = { Exec.read = true; write = true; execute = false } in
  let text =
    {
      Exec.name = ".text";
      addr = 0x10000L;
      align = 4L;
      content = Exec.Bytes (String.make 0x80 '\x13');
    }
  in
  let data =
    {
      Exec.name = ".data";
      addr = 0x20000L;
      align = 4L;
      content = Exec.Bytes (String.make 0x10 '\x00');
    }
  in
  let symbol ?(section = ".text") ?(binding = `Global) name value size kind =
    { Exec.name; value; size; kind; binding; section = Some section }
  in
  let spec =
    {
      Exec.target;
      entry = 0x10000L;
      headers = Exec.Unmapped;
      gnu_stack = None;
      section_headers = true;
      symbols =
        [
          symbol "reset" 0x10000L 0L `Notype;
          symbol "early" 0x10008L 0L `Func;
          symbol "outer" 0x10020L 0x30L `Func;
          symbol "alias" 0x10020L 0L `Notype;
          symbol "inner" 0x10030L 8L `Func;
          symbol "after" 0x10060L 0L `Notype;
          symbol ~binding:`Local "$x" 0x10000L 0L `Notype;
          symbol ~binding:`Local ".Lskip" 0x10040L 0L `Notype;
          symbol "table" 0x10070L 8L `Object;
          symbol ~section:".data" "flag" 0x20000L 0L `Notype;
        ];
      segments =
        [
          { Exec.perms = rx; paddr = None; sections = [ text ] };
          { Exec.perms = rw; paddr = None; sections = [ data ] };
        ];
    }
  in
  match Exec.build spec with Ok bytes -> bytes | Error _ -> failwith "Exec.build"

let%expect_test "untyped code symbols and overlapping functions" =
  (match Symbols.of_string asm_elf with
  | Error e -> print_endline e
  | Ok t ->
      List.iter
        (fun (f : Symbols.func) -> Printf.printf "%s %x %x\n" f.name f.address f.size)
        (Symbols.to_list t);
      List.iter
        (fun pc ->
          match Symbols.lookup t pc with
          | Some (f, off) -> Printf.printf "%x: %s+%d\n" pc f.name off
          | None -> Printf.printf "%x: -\n" pc)
        [ 0x10004; 0x10008; 0x10024; 0x10034; 0x10040; 0x10050; 0x10060; 0x10064 ];
      List.iter
        (fun n -> Printf.printf "find %s: %d\n" n (List.length (Symbols.find t n)))
        [ "reset"; "alias"; "flag"; "$x"; ".Lskip"; "table" ]);
  [%expect
    {|
    reset 10000 8
    early 10008 18
    alias 10020 10
    outer 10020 30
    inner 10030 8
    after 10060 0
    10004: reset+4
    10008: early+0
    10024: outer+4
    10034: inner+4
    10040: outer+32
    10050: -
    10060: after+0
    10064: -
    find reset: 1
    find alias: 1
    find flag: 0
    find $x: 0
    find .Lskip: 0
    find table: 0
    |}]
