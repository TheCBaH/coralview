[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

type entry = { lo : int; hi : int; label : string } (* [lo, hi) *)
type t = entry list

let number s = int_of_string_opt (String.trim s)

let is_hex8 s =
  String.length s = 8
  && String.for_all (function '0' .. '9' | 'a' .. 'f' | 'A' .. 'F' -> true | _ -> false) s

let absolute s =
  if String.starts_with ~prefix:"0x" s || is_hex8 s then
    number (if String.starts_with ~prefix:"0x" s then s else "0x" ^ s)
  else None

(* "A" or "A-B" with [parse] for each. *)
let span parse s =
  match String.index_opt s '-' with
  | None -> Option.map (fun a -> (a, a + 1)) (parse s)
  | Some i -> (
      match (parse (String.sub s 0 i), parse (String.sub s (i + 1) (String.length s - i - 1))) with
      | Some a, Some b when a < b -> Some (a, b)
      | _ -> None)

let location ~functions loc =
  match
    absolute (match String.index_opt loc '-' with Some i -> String.sub loc 0 i | None -> loc)
  with
  | Some _ -> (
      match span absolute loc with Some r -> Ok [ r ] | None -> Error ("bad address range " ^ loc))
  | None -> (
      let name, offsets =
        match String.rindex_opt loc '+' with
        | Some i -> (String.sub loc 0 i, Some (String.sub loc (i + 1) (String.length loc - i - 1)))
        | None -> (loc, None)
      in
      match functions name with
      | [] -> Error ("no function " ^ name ^ " in the ELF")
      | fs -> (
          match offsets with
          | None -> Ok (List.map (fun (a, size) -> (a, a + max size 1)) fs)
          | Some o -> (
              match span number o with
              | None -> Error ("bad offsets " ^ o)
              | Some (lo, hi) -> Ok (List.map (fun (a, _) -> (a + lo, a + hi)) fs))))

let parse ~functions text =
  let rec go n acc = function
    | [] -> Ok (List.rev acc)
    | line :: rest -> (
        let line = String.trim line in
        if line = "" || line.[0] = '#' then go (n + 1) acc rest
        else
          match String.index_from_opt line 0 ' ' with
          | None -> Error (Printf.sprintf "line %d: expected LOCATION LABEL" n)
          | Some i -> (
              let loc = String.sub line 0 i
              and label = String.trim (String.sub line i (String.length line - i)) in
              match location ~functions loc with
              | Error e -> Error (Printf.sprintf "line %d: %s" n e)
              | Ok ranges ->
                  go (n + 1)
                    (List.rev_append (List.map (fun (lo, hi) -> { lo; hi; label }) ranges) acc)
                    rest))
  in
  go 1 [] (String.split_on_char '\n' text)

let load ~functions file =
  match In_channel.with_open_text file In_channel.input_all with
  | text -> Result.map_error (fun e -> file ^ ": " ^ e) (parse ~functions text)
  | exception Sys_error e -> Error e

let labels t addr =
  List.filter_map (fun e -> if addr >= e.lo && addr < e.hi then Some e.label else None) t
