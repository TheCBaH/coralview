[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

type func = { name : string; address : int; size : int }

(* [typed.(i)]: a FUNC symbol, which names its range before an untyped label inside it. [reach.(i)]: the
   largest end of the first [i + 1] symbols, so that a lookup knows when to stop looking back. *)
type t = { funcs : func array; typed : bool array; reach : int array }

let error pp e = Error (Format.asprintf "%a" (Err.Error.pp_kind pp) e)
let is_mapping n = String.length n >= 2 && n.[0] = '$' && (n.[1] = 'x' || n.[1] = 'd')
let is_local_label n = String.length n >= 2 && String.sub n 0 2 = ".L"
let extent f = f.address + max f.size 1

(* A symbol with no size (assembly without .size) ends where the next one starts: a FUNC at the next FUNC,
   an untyped label at the next symbol of either kind. *)
let close syms =
  let n = Array.length syms in
  let size = Array.map (fun (f, _) -> f.size) syms in
  let next_any = ref None and next_func = ref None in
  let i = ref (n - 1) in
  while !i >= 0 do
    let address = (fst syms.(!i)).address in
    let j = ref !i and has_func = ref false in
    while !j >= 0 && (fst syms.(!j)).address = address do
      let _, typed = syms.(!j) in
      if typed then has_func := true;
      (if size.(!j) = 0 then
         match if typed then !next_func else !next_any with
         | Some next -> size.(!j) <- next - address
         | None -> ());
      decr j
    done;
    next_any := Some address;
    if !has_func then next_func := Some address;
    i := !j
  done;
  Array.mapi (fun i (f, typed) -> ({ f with size = size.(i) }, typed)) syms

let make syms =
  let syms = close syms in
  let reach = Array.make (Array.length syms) 0 in
  Array.iteri
    (fun i (f, _) -> reach.(i) <- max (extent f) (if i = 0 then 0 else reach.(i - 1)))
    syms;
  { funcs = Array.map fst syms; typed = Array.map snd syms; reach }

let of_string data =
  match Elf.Decode.of_string data with
  | Error e -> error Elf.Decode.pp_error e
  | Ok elf -> (
      match Elf.Decode.find_section elf ".symtab" with
      | None -> Error "no .symtab: the ELF is stripped"
      | Some section -> (
          match Elf.Decode.symbols elf section with
          | Error e -> error Elf.Decode.pp_error e
          | Ok symbols ->
              (* FUNC symbols, and untyped ones defined in an executable section, as an assembly entry
                 point is. *)
              let executable shndx =
                shndx > Elf.Const.shn_undef
                && shndx < min (Array.length elf.sections) Elf.Const.shn_loreserve
                && Int64.logand elf.sections.(shndx).shdr.sh_flags Elf.Const.shf_execinstr <> 0L
              in
              let funcs =
                Array.to_list symbols
                |> List.filter_map (fun (s : Elf.Decode.symbol) ->
                    let ty = Elf.Types.st_type s.sym.st_info and n = s.sym_name in
                    let typed = ty = Elf.Const.stt_func in
                    if
                      n <> ""
                      && (typed
                         || ty = Elf.Const.stt_notype
                            && executable (Int64.to_int s.shndx)
                            && (not (is_mapping n))
                            && not (is_local_label n))
                    then
                      Some
                        ( {
                            name = n;
                            address = Int64.to_int s.sym.st_value;
                            size = Int64.to_int s.sym.st_size;
                          },
                          typed )
                    else None)
                |> List.stable_sort (fun (a, _) (b, _) ->
                    compare (a.address, a.name) (b.address, b.name))
              in
              Ok (make (Array.of_list funcs))))

let load path =
  match In_channel.with_open_bin path In_channel.input_all with
  | data -> ( match of_string data with Ok _ as ok -> ok | Error e -> Error (path ^ ": " ^ e))
  | exception Sys_error e -> Error e

let find t name = List.filter (fun f -> f.name = name) (Array.to_list t.funcs)

let lookup t pc =
  (* The symbols starting at or before [pc], latest first, while one can still reach it: the latest FUNC
     that holds it, else the latest untyped label. *)
  let lo = ref 0 and hi = ref (Array.length t.funcs) in
  while !lo < !hi do
    let mid = (!lo + !hi) / 2 in
    if t.funcs.(mid).address <= pc then lo := mid + 1 else hi := mid
  done;
  let rec back i untyped =
    if i < 0 || t.reach.(i) <= pc then untyped
    else
      let f = t.funcs.(i) in
      if pc >= extent f then back (i - 1) untyped
      else if t.typed.(i) then Some f
      else back (i - 1) (match untyped with None -> Some f | some -> some)
  in
  Option.map (fun f -> (f, pc - f.address)) (back (!lo - 1) None)

let to_list t = Array.to_list t.funcs
