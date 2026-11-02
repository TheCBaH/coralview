[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

type func = { name : string; address : int; size : int }
type t = func array

let error pp e = Error (Format.asprintf "%a" (Err.Error.pp_kind pp) e)

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
              let funcs =
                Array.to_list symbols
                |> List.filter_map (fun (s : Elf.Decode.symbol) ->
                    if Elf.Types.st_type s.sym.st_info = Elf.Const.stt_func && s.sym_name <> "" then
                      Some
                        {
                          name = s.sym_name;
                          address = Int64.to_int s.sym.st_value;
                          size = Int64.to_int s.sym.st_size;
                        }
                    else None)
                |> List.stable_sort (fun a b -> compare (a.address, a.name) (b.address, b.name))
              in
              (* A function with no size (assembly without .size) ends where the next one starts. *)
              let rec close = function
                | f :: (next :: _ as rest) ->
                    let f =
                      if f.size = 0 && next.address > f.address then
                        { f with size = next.address - f.address }
                      else f
                    in
                    f :: close rest
                | l -> l
              in
              Ok (Array.of_list (close funcs))))

let load path =
  match In_channel.with_open_bin path In_channel.input_all with
  | data -> ( match of_string data with Ok _ as ok -> ok | Error e -> Error (path ^ ": " ^ e))
  | exception Sys_error e -> Error e

let find t name = List.filter (fun f -> f.name = name) (Array.to_list t)

let lookup t pc =
  (* The last function starting at or before [pc]. *)
  let lo = ref 0 and hi = ref (Array.length t) in
  while !lo < !hi do
    let mid = (!lo + !hi) / 2 in
    if t.(mid).address <= pc then lo := mid + 1 else hi := mid
  done;
  if !lo = 0 then None
  else
    let f = t.(!lo - 1) in
    if pc < f.address + max f.size 1 then Some (f, pc - f.address) else None

let to_list = Array.to_list
