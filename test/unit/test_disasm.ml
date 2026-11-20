open Coralview

(* Two executable sections at the same addresses, as an overlay has, and a boot section above them. The
   builder refuses to place two segments on one page, so .ovl is built at 0x2100 and moved down. *)
let built =
  let open Elf in
  let rx = { Exec.read = true; write = false; execute = true } in
  let words ws =
    Exec.Bytes
      (String.concat ""
         (List.map (fun w -> String.init 4 (fun i -> Char.chr ((w lsr (8 * i)) land 0xff))) ws))
  in
  let nop = 0x00000013 in
  let body = [ nop; 0x0080006f; nop; nop; nop; 0xfedff06f; nop; nop ] in
  let section name addr ws = { Exec.name; addr; align = 4L; content = words ws } in
  let symbol name value section kind =
    { Exec.name; value; size = 0L; kind; binding = `Global; section = Some section }
  in
  let spec =
    {
      Exec.target = Target.riscv Riscv.rv32imafd_ilp32d;
      entry = 0x1000L;
      headers = Exec.Unmapped;
      gnu_stack = None;
      section_headers = true;
      symbols =
        [
          symbol "boot" 0x1000L ".boot" `Func;
          symbol "shared" 0x100L ".text" `Func;
          symbol "zeta" 0x110L ".text" `Notype;
          symbol "shared" 0x2100L ".ovl" `Func;
          symbol "b_mid" 0x2108L ".ovl" `Func;
          symbol "alpha" 0x2110L ".ovl" `Func;
        ];
      segments =
        [
          {
            Exec.perms = rx;
            paddr = None;
            sections = [ section ".boot" 0x1000L [ 0x908ff06f; nop ] ];
          };
          { Exec.perms = rx; paddr = None; sections = [ section ".text" 0x100L body ] };
          { Exec.perms = rx; paddr = None; sections = [ section ".ovl" 0x2100L body ] };
        ];
    }
  in
  match Exec.build spec with
  | Ok bytes -> bytes
  | Error e -> failwith (Format.asprintf "%a" (Err.Error.pp_kind Elf.Exec.pp_error) e)

let elf =
  let moved v = if v >= 0x2100 && v < 0x2120 then v - 0x2000 else v in
  let d = Result.get_ok (Elf.Decode.of_string built) in
  let b = Bytes.of_string built in
  let shoff = Int32.to_int (Bytes.get_int32_le b 0x20) and shentsize = Bytes.get_uint16_le b 0x2e in
  Array.iter
    (fun (s : Elf.Decode.section) ->
      let at = shoff + (s.index * shentsize) in
      if s.name = ".ovl" then Bytes.set_int32_le b (at + 12) 0x100l;
      if s.name = ".symtab" then
        for i = 0 to (Int64.to_int s.shdr.sh_size / 16) - 1 do
          let v = Int64.to_int s.shdr.sh_offset + (i * 16) + 4 in
          Bytes.set_int32_le b v (Int32.of_int (moved (Int32.to_int (Bytes.get_int32_le b v))))
        done)
    d.sections;
  Bytes.to_string b

let list () =
  let decoder = Result.get_ok (Coral_isa.Rivet_decode.create ()) in
  match Disasm.listing decoder Disasm.everything elf with
  | Error e -> print_endline e
  | Ok items ->
      List.iter
        (function
          | Disasm.Label l -> Printf.printf "%s:\n" l
          | Line l ->
              let opt = Option.value ~default:"-" in
              Printf.printf "  %04x %-15s symbol %-7s func %-7s target %s\n" l.address l.text
                (opt l.symbol) (opt l.func) (opt l.target)
          | Padding _ -> ())
        items

let%expect_test "labels, and branch targets, are per section" =
  list ();
  [%expect
    {|
    shared:
      0100 addi x0, x0, 0  symbol shared  func shared  target -
      0104 jal x0, 8       symbol shared  func shared  target <shared+0xc>
      0108 addi x0, x0, 0  symbol shared  func shared  target -
      010c addi x0, x0, 0  symbol shared  func shared  target -
    zeta:
      0110 addi x0, x0, 0  symbol zeta    func shared  target -
      0114 jal x0, -20     symbol zeta    func shared  target <shared>
      0118 addi x0, x0, 0  symbol zeta    func shared  target -
      011c addi x0, x0, 0  symbol zeta    func shared  target -
    shared:
      0100 addi x0, x0, 0  symbol shared  func shared  target -
      0104 jal x0, 8       symbol shared  func shared  target <b_mid+0x4>
    b_mid:
      0108 addi x0, x0, 0  symbol b_mid   func b_mid   target -
      010c addi x0, x0, 0  symbol b_mid   func b_mid   target -
    alpha:
      0110 addi x0, x0, 0  symbol alpha   func alpha   target -
      0114 jal x0, -20     symbol alpha   func alpha   target <shared>
      0118 addi x0, x0, 0  symbol alpha   func alpha   target -
      011c addi x0, x0, 0  symbol alpha   func alpha   target -
    boot:
      1000 jal x0, -3832   symbol boot    func boot    target -
      1004 addi x0, x0, 0  symbol boot    func boot    target -
    |}]
