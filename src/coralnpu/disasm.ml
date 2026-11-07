[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

module Rd = Coral_isa.Rivet_decode

type line = {
  address : int;
  word : int;
  text : string;
  instruction : Rd.instruction option;
  symbol : string option;
  target : string option;
}

type item = Label of string | Line of line
type scope = { sections : string list; functions : string list; range : (int * int) option }

let everything = { sections = []; functions = []; range = None }

type label = { l_address : int; l_name : string; l_func : bool; l_section : int }

let elf_error pp e = Format.asprintf "%a" (Err.Error.pp_kind pp) e
let has flags f = Int64.logand flags f <> 0L

let u32 s off =
  Char.code s.[off]
  lor (Char.code s.[off + 1] lsl 8)
  lor (Char.code s.[off + 2] lsl 16)
  lor (Char.code s.[off + 3] lsl 24)

let sign_extend bits v = if v land (1 lsl (bits - 1)) <> 0 then v - (1 lsl bits) else v

(* The destination of a [jal] or a conditional branch, from its encoding. *)
let branch_target address word =
  match word land 0x7f with
  | 0x6f ->
      let imm =
        (((word lsr 31) land 1) lsl 20)
        lor (((word lsr 12) land 0xff) lsl 12)
        lor (((word lsr 20) land 1) lsl 11)
        lor (((word lsr 21) land 0x3ff) lsl 1)
      in
      Some (address + sign_extend 21 imm)
  | 0x63 ->
      let imm =
        (((word lsr 31) land 1) lsl 12)
        lor (((word lsr 7) land 1) lsl 11)
        lor (((word lsr 25) land 0x3f) lsl 5)
        lor (((word lsr 8) land 0xf) lsl 1)
      in
      Some (address + sign_extend 13 imm)
  | _ -> None

let is_mapping n = String.length n >= 2 && n.[0] = '$' && (n.[1] = 'x' || n.[1] = 'd')

(* The labels of the ELF. Mapping symbols ($x, $d) name no code and are not read as data: the toolchain marks
   Coral's Zvt words, which it can only write as .word, as data. *)
let read_symbols elf =
  match Elf.Decode.find_section elf ".symtab" with
  | None -> Ok None
  | Some section -> (
      match Elf.Decode.symbols elf section with
      | Error e -> Error (elf_error Elf.Decode.pp_error e)
      | Ok symbols ->
          let labels = ref [] in
          Array.iter
            (fun (s : Elf.Decode.symbol) ->
              let ty = Elf.Types.st_type s.sym.st_info in
              let shndx = Int64.to_int s.shndx in
              let defined = shndx <> Elf.Const.shn_undef && shndx < Elf.Const.shn_loreserve in
              let n = s.sym_name and address = Int64.to_int s.sym.st_value in
              if defined && n <> "" then
                if is_mapping n then ()
                else if
                  (ty = Elf.Const.stt_func || ty = Elf.Const.stt_notype)
                  && not (String.length n >= 2 && String.sub n 0 2 = ".L")
                then
                  labels :=
                    {
                      l_address = address;
                      l_name = n;
                      l_func = ty = Elf.Const.stt_func;
                      l_section = shndx;
                    }
                    :: !labels)
            symbols;
          let labels =
            List.sort_uniq
              (fun a b ->
                compare (a.l_address, not a.l_func, a.l_name) (b.l_address, not b.l_func, b.l_name))
              !labels
          in
          Ok (Some (Array.of_list labels)))

(* The last element of a sorted array with [key x <= v]. *)
let floor_index key a v =
  let lo = ref 0 and hi = ref (Array.length a) in
  while !lo < !hi do
    let mid = (!lo + !hi) / 2 in
    if key a.(mid) <= v then lo := mid + 1 else hi := mid
  done;
  !lo - 1

let name_at labels section v =
  let i = floor_index (fun l -> l.l_address) labels v in
  (* Several labels at one address: the first (a function) names it. *)
  let rec first i =
    if i > 0 && labels.(i - 1).l_address = labels.(i).l_address then first (i - 1) else i
  in
  if i < 0 then None
  else
    let l = labels.(first i) in
    if l.l_section = section then Some l else None

(* Every label at an address of a section, in the array's order. *)
let labels_at labels section address =
  let i = floor_index (fun l -> l.l_address) labels address in
  let rec first i = if i > 0 && labels.(i - 1).l_address = address then first (i - 1) else i in
  if i < 0 || labels.(i).l_address <> address then []
  else
    let rec collect j acc =
      if j < Array.length labels && labels.(j).l_address = address then
        collect (j + 1) (if labels.(j).l_section = section then labels.(j) :: acc else acc)
      else List.rev acc
    in
    collect (first i) []

let check_header (elf : Elf.Decode.t) =
  let h = elf.header in
  if h.ident.elf_class <> Elf.Types.Elf32 || h.ident.endianness <> Elf.Types.Little then
    Error "not an ELF32 little-endian file"
  else if h.e_machine <> Elf.Const.em_riscv then Error "not a RISC-V ELF"
  else if has h.e_flags Elf.Const.ef_riscv_rvc then
    Error "the ELF marks compressed instructions (RVC); only 4-byte words are listed"
  else Ok ()

let ( let* ) = Result.bind

let listing decoder scope data =
  let* elf = Result.map_error (elf_error Elf.Decode.pp_error) (Elf.Decode.of_string data) in
  let* () = check_header elf in
  let* syms = read_symbols elf in
  let labels = Option.value syms ~default:[||] in
  let exec =
    Array.to_list elf.sections
    |> List.filter (fun (s : Elf.Decode.section) ->
        has s.shdr.sh_flags Elf.Const.shf_execinstr && s.shdr.sh_type = Elf.Const.sht_progbits)
    |> List.stable_sort (fun (a : Elf.Decode.section) b -> compare a.shdr.sh_addr b.shdr.sh_addr)
  in
  let* () =
    match
      List.filter
        (fun n -> not (List.exists (fun (s : Elf.Decode.section) -> s.name = n) exec))
        scope.sections
    with
    | [] -> Ok ()
    | n :: _ -> Error (Printf.sprintf "no executable section %s" n)
  in
  let exec =
    if scope.sections = [] then exec
    else List.filter (fun (s : Elf.Decode.section) -> List.mem s.name scope.sections) exec
  in
  let* extents =
    if scope.functions = [] then Ok None
    else
      match Symbols.of_string data with
      | Error e -> Error e
      | Ok syms ->
          let rec go acc = function
            | [] -> Ok (Some acc)
            | n :: rest -> (
                match Symbols.find syms n with
                | [] -> Error (Printf.sprintf "no function %s" n)
                | fs ->
                    go
                      (List.map (fun (f : Symbols.func) -> (f.address, f.address + f.size)) fs @ acc)
                      rest)
          in
          go [] scope.functions
  in
  let selected address =
    (match extents with
      | None -> true
      | Some l -> List.exists (fun (lo, hi) -> address >= lo && address < hi) l)
    && match scope.range with None -> true | Some (lo, hi) -> address >= lo && address < hi
  in
  let section_ends =
    List.map
      (fun (s : Elf.Decode.section) ->
        ( s.index,
          Int64.to_int s.shdr.sh_addr,
          Int64.to_int s.shdr.sh_addr + Int64.to_int s.shdr.sh_size ))
      exec
  in
  let target_text address word =
    match branch_target address word with
    | None -> None
    | Some t -> (
        match List.find_opt (fun (_, lo, hi) -> t >= lo && t < hi) section_ends with
        | None -> None
        | Some (sec, _, _) ->
            Option.map
              (fun l ->
                let off = t - l.l_address in
                if off = 0 then Printf.sprintf "<%s>" l.l_name
                else Printf.sprintf "<%s+0x%x>" l.l_name off)
              (name_at labels sec t))
  in
  let out = ref [] in
  let rec run = function
    | [] -> Ok ()
    | (s : Elf.Decode.section) :: rest -> (
        match Elf.Decode.section_data elf s with
        | Error e -> Error (elf_error Elf.Decode.pp_error e)
        | Ok bytes ->
            let base = Int64.to_int s.shdr.sh_addr in
            let n = String.length bytes in
            let i = ref 0 in
            while !i < n do
              let address = base + !i in
              if !i + 4 > n then begin
                (* A tail shorter than a word: not an instruction. *)
                i := n
              end
              else begin
                if selected address then begin
                  List.iter
                    (fun l -> out := Label l.l_name :: !out)
                    (labels_at labels s.index address)
                end;
                (if selected address then
                   let word = u32 bytes !i in
                   let text, instruction =
                     (* Not a 32-bit encoding (Rivet would read two compressed halves): data. *)
                     if word land 3 <> 3 then (Printf.sprintf ".word 0x%08x" word, None)
                     else
                       match Rd.instruction decoder word with
                       | Ok ins -> (Rd.disasm decoder word, Some ins)
                       | Error _ -> (Rd.disasm decoder word, None)
                   in
                   let target = if instruction = None then None else target_text address word in
                   let symbol = Option.map (fun l -> l.l_name) (name_at labels s.index address) in
                   out := Line { address; word; text; instruction; symbol; target } :: !out);
                i := !i + 4
              end
            done;
            run rest)
  in
  let* () = run exec in
  Ok (List.rev !out)

let lines items = List.filter_map (function Line l -> Some l | Label _ -> None) items

let pp_text ppf items =
  List.iter
    (function
      | Label n -> Format.fprintf ppf "%s:@\n" n
      | Line l ->
          Format.fprintf ppf "  %08x  %08x  %s%s@\n" l.address l.word l.text
            (match l.target with Some t -> "  " ^ t | None -> ""))
    items

let line_jsont =
  Jsont.Object.map ~kind:"disasm" (fun address word text mnemonic cls symbol target ->
      ignore (mnemonic, cls);
      { address; word; text; instruction = None; symbol; target })
  |> Jsont.Object.mem "address" Jsont.int ~enc:(fun l -> l.address)
  |> Jsont.Object.mem "word" Jsont.int ~enc:(fun l -> l.word)
  |> Jsont.Object.mem "text" Jsont.string ~enc:(fun l -> l.text)
  |> Codec.opt
       (fun l -> Option.map (fun (i : Rd.instruction) -> i.mnemonic) l.instruction)
       "mnemonic" Jsont.string
  |> Codec.opt
       (fun l ->
         Option.map
           (fun i -> Coral_isa.Iclass.name (Coral_isa.Iclass.of_instruction i))
           l.instruction)
       "class" Jsont.string
  |> Codec.opt (fun l -> l.symbol) "symbol" Jsont.string
  |> Codec.opt (fun l -> l.target) "target" Jsont.string
  |> Jsont.Object.finish
