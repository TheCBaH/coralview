[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

open Vcd_types
module String_set = Set.Make (String)
module Ref_map = Map.Make (Reference)

type entry = {
  aliases : Reference.t list;
  width : int;
  var_type : Vcd_ast.var_type;
  origins : string list;
  provenance : (string * string) list;
}

type plan = entry list

let type_name = Vcd.string_of_var_type
let same_type a b = String.equal (type_name a) (type_name b)
let same_aliases a b = List.equal Reference.equal a b
let sorted_uniq cmp l = List.sort_uniq cmp l
let first_alias e = List.hd e.aliases
let by_first a b = Reference.compare (first_alias a) (first_alias b)
let normalise entries = List.sort by_first entries
let entries = Fun.id
let origins p = sorted_uniq String.compare (List.concat_map (fun e -> e.origins) p)
let show = Reference.to_string

let valid_origin o =
  o <> "" && not (String.exists (fun c -> c = ',' || c = ' ' || c = '\t' || c = '\n' || c = '\r') o)

let plan ~origin trace nets =
  if Trace.events_pulled trace then invalid_arg "Capture.plan: the trace's events were pulled";
  if not (valid_origin origin) then
    invalid_arg ("Capture.plan: invalid origin " ^ String.escaped origin);
  let tracked = Trace.tracked trace in
  let provenance = Hashtbl.create 64 in
  List.iter
    (fun net ->
      List.iter
        (fun (r : Bind.requirement) ->
          match Trace.lookup trace r.path with
          | None -> ()
          | Some entry ->
              let id = ID.to_string (Vcd.Resolver.entry_id entry) in
              let prev = Option.value (Hashtbl.find_opt provenance id) ~default:[] in
              Hashtbl.replace provenance id ((r.model, r.purpose) :: prev))
        (Bind.requirements net))
    nets;
  normalise
    (Array.to_list
       (Array.map
          (fun (s : Trace.signal) ->
            {
              aliases = Vcd.Ref_set.elements s.aliases;
              width = s.width;
              var_type = s.var_type;
              origins = [ origin ];
              provenance =
                sorted_uniq compare
                  (Option.value (Hashtbl.find_opt provenance (ID.to_string s.id)) ~default:[]);
            })
          tracked))

let union plans =
  let by_path = ref Ref_map.empty and errors = ref [] and groups = ref [] in
  let conflict path what = errors := Printf.sprintf "%s: %s" (show path) what :: !errors in
  List.iter
    (List.iter (fun e ->
         let hits =
           List.filter_map
             (fun r -> Option.map (fun g -> (r, g)) (Ref_map.find_opt r !by_path))
             e.aliases
         in
         match hits with
         | [] ->
             let cell = ref e in
             groups := cell :: !groups;
             List.iter (fun r -> by_path := Ref_map.add r cell !by_path) e.aliases
         | (_, cell) :: _
           when List.for_all (fun (_, c) -> c == cell) hits
                && same_aliases !cell.aliases e.aliases
                && !cell.width = e.width
                && same_type !cell.var_type e.var_type ->
             cell :=
               {
                 !cell with
                 origins = sorted_uniq String.compare (!cell.origins @ e.origins);
                 provenance = sorted_uniq compare (!cell.provenance @ e.provenance);
               }
         | hits ->
             List.iter
               (fun (r, c) ->
                 if not (same_aliases !c.aliases e.aliases) then conflict r "different alias group"
                 else if !c.width <> e.width then
                   conflict r (Printf.sprintf "width %d against %d" !c.width e.width)
                 else
                   conflict r
                     (Printf.sprintf "type %s against %s" (type_name !c.var_type)
                        (type_name e.var_type)))
               hits))
    plans;
  match !errors with
  | [] -> Ok (normalise (List.map ( ! ) !groups))
  | errs -> Error (sorted_uniq String.compare errs)

(* ---------------------------------------------------------------- *)
(*  File                                                              *)
(* ---------------------------------------------------------------- *)

let header = "hwfrp-capture-plan 1"

let components r =
  let cs = Reference.to_list r in
  List.iter
    (fun c ->
      if String.exists (fun ch -> ch = '\t' || ch = '\n' || ch = '\r') c then
        invalid_arg ("Capture.to_file: tab or newline in a path component of " ^ show r))
    cs;
  String.concat "\t" cs

let to_file p =
  let b = Buffer.create 1024 in
  Buffer.add_string b header;
  Buffer.add_char b '\n';
  List.iter
    (fun e ->
      match e.aliases with
      | [] -> invalid_arg "Capture.to_file: an entry without aliases"
      | first :: rest ->
          Printf.bprintf b "signal %d %s %s\t%s\n" e.width (type_name e.var_type)
            (String.concat "," e.origins) (components first);
          List.iter (fun r -> Printf.bprintf b "alias\t%s\n" (components r)) rest)
    p;
  Buffer.contents b

exception File_error of int * string

let of_file text =
  let fail n msg = raise (File_error (n, msg)) in
  match
    let lines = String.split_on_char '\n' text in
    let lines = match List.rev lines with "" :: rest -> List.rev rest | _ -> lines in
    if String.length text = 0 || text.[String.length text - 1] <> '\n' then
      fail (List.length lines) "no final newline";
    (match lines with
    | first :: _ when String.equal first header -> ()
    | _ -> fail 1 ("expected " ^ header));
    let groups = ref [] in
    let seen = ref Ref_map.empty in
    let add n r =
      if Ref_map.mem r !seen then fail n ("duplicate path " ^ show r);
      seen := Ref_map.add r () !seen
    in
    let path n = function
      | [] -> fail n "empty path"
      | cs ->
          if List.exists (String.equal "") cs then fail n "empty path component";
          Reference.of_list cs
    in
    List.iteri
      (fun i line ->
        let n = i + 1 in
        if n > 1 then
          match String.split_on_char '\t' line with
          | "alias" :: cs -> (
              match !groups with
              | [] -> fail n "alias before any signal"
              | (e, rest) :: groups' ->
                  let r = path n cs in
                  add n r;
                  groups := (e, r :: rest) :: groups')
          | head :: cs -> (
              match String.split_on_char ' ' head with
              | [ "signal"; width; ty; origins ] ->
                  let width =
                    match int_of_string_opt width with
                    | Some w when w > 0 -> w
                    | _ -> fail n ("bad width " ^ width)
                  in
                  let origins = String.split_on_char ',' origins in
                  if not (List.for_all valid_origin origins) then fail n "bad origins";
                  let r = path n cs in
                  add n r;
                  groups :=
                    ( {
                        aliases = [];
                        width;
                        var_type = Vcd_ast.var_type_of_keyword ty;
                        origins = sorted_uniq String.compare origins;
                        provenance = [];
                      },
                      [ r ] )
                    :: !groups
              | _ -> fail n ("unknown line " ^ String.escaped line))
          | [] -> fail n "empty line")
      lines;
    normalise
      (List.rev_map (fun (e, rs) -> { e with aliases = List.sort Reference.compare rs }) !groups)
  with
  | p -> Ok p
  | exception File_error (n, msg) -> Error (Printf.sprintf "line %d: %s" n msg)

(* ---------------------------------------------------------------- *)
(*  Check                                                             *)
(* ---------------------------------------------------------------- *)

let check p ~origins:wanted trace =
  let errors = ref [] in
  let err fmt = Printf.ksprintf (fun s -> errors := s :: !errors) fmt in
  let known = String_set.of_list (origins p) in
  List.iter
    (fun o -> if not (String_set.mem o known) then err "origin %s is not in the plan" o)
    wanted;
  let wanted = String_set.of_list wanted in
  let expected =
    List.filter (fun e -> List.exists (fun o -> String_set.mem o wanted) e.origins) p
  in
  let tracked = Trace.tracked trace in
  let tracked_by_id = Hashtbl.create 64 in
  Array.iter (fun (s : Trace.signal) -> Hashtbl.replace tracked_by_id (ID.to_string s.id) s) tracked;
  let matched = Hashtbl.create 64 in
  List.iter
    (fun e ->
      let first = first_alias e in
      let resolved = List.map (fun r -> (r, Trace.lookup trace r)) e.aliases in
      match List.filter (fun (_, x) -> Option.is_none x) resolved with
      | _ :: _ as missing -> List.iter (fun (r, _) -> err "%s: missing" (show r)) missing
      | [] ->
          let entries = List.filter_map snd resolved in
          List.iter
            (fun x -> Hashtbl.replace matched (ID.to_string (Vcd.Resolver.entry_id x)) ())
            entries;
          let id = Vcd.Resolver.entry_id (List.hd entries) in
          if not (List.for_all (fun x -> ID.equal (Vcd.Resolver.entry_id x) id) entries) then
            err "%s: alias group split over several signals" (show first)
          else
            let refs = Vcd.Ref_set.elements (Vcd.Resolver.entry_references (List.hd entries)) in
            if not (same_aliases refs e.aliases) then err "%s: different alias group" (show first)
            else
              let entry = List.hd entries in
              if Vcd.Resolver.entry_size entry <> e.width then
                err "%s: width %d, planned %d" (show first) (Vcd.Resolver.entry_size entry) e.width
              else if not (same_type (Trace.var_type trace entry) e.var_type) then
                err "%s: type %s, planned %s" (show first)
                  (type_name (Trace.var_type trace entry))
                  (type_name e.var_type)
              else if not (Hashtbl.mem tracked_by_id (ID.to_string id)) then
                err "%s: planned but not tracked" (show first))
    expected;
  Array.iter
    (fun (s : Trace.signal) ->
      if not (Hashtbl.mem matched (ID.to_string s.id)) then
        err "%s: tracked but not planned" (show s.path))
    tracked;
  match !errors with [] -> Ok () | errs -> Error (sorted_uniq String.compare errs)

(* ---------------------------------------------------------------- *)
(*  Verilator manifest                                                *)
(* ---------------------------------------------------------------- *)

module Verilator = struct
  let bad_char c = c <= ' ' || c = '\x7f'
  let bad_component c = c = "" || String.exists bad_char c

  let bus_range = function
    | None -> true
    | Some i -> (
        let n = String.length i in
        n > 2
        && i.[0] = '['
        && i.[n - 1] = ']'
        &&
        match String.split_on_char ':' (String.sub i 1 (n - 2)) with
        | [ a; b ] -> int_of_string_opt a <> None && int_of_string_opt b <> None
        | _ -> false)

  (* The verdict on each declared path, from the catalog's scope tree: the first declaration wins. *)
  let declared (catalog : Trace.t) =
    let table = ref Ref_map.empty in
    let rec walk names bad (s : Vcd_ast.scope_node) =
      let names = s.s_name :: names in
      let bad =
        match (bad, s.s_type) with
        | None, Vcd_ast.Module -> None
        | None, t -> Some (Vcd.string_of_scope_type t)
        | b, _ -> b
      in
      List.iter
        (fun (v : Vcd_ast.var_decl) ->
          let comps = List.rev (v.ref :: names) in
          let key = Reference.of_list comps in
          if not (Ref_map.mem key !table) then
            let verdict =
              match bad with
              | Some kind -> Error (Printf.sprintf "under a %s scope" kind)
              | None when not (bus_range v.index) ->
                  Error ("index " ^ Option.value v.index ~default:"")
              | None -> Ok (String.concat " " comps)
            in
            table := Ref_map.add key verdict !table)
        s.vars;
      List.iter (walk names bad) s.children
    in
    List.iter (walk [] None) (Trace.header catalog).Vcd_ast.scopes;
    !table

  let manifest ~catalog ~producer ~format p =
    let errors = ref [] in
    let err fmt = Printf.ksprintf (fun s -> errors := s :: !errors) fmt in
    if producer = "" || String.exists bad_char producer then
      err "producer: empty or with whitespace";
    let table = declared catalog in
    let natives = ref String_set.empty in
    List.iter
      (fun e ->
        List.iter
          (fun r ->
            if List.exists bad_component (Reference.to_list r) then
              err "%s: component empty or with whitespace or a control character" (show r)
            else
              match Ref_map.find_opt r table with
              | None -> err "%s: not in the catalog" (show r)
              | Some (Error why) -> err "%s: %s" (show r) why
              | Some (Ok native) -> natives := String_set.add native !natives)
          e.aliases)
      p;
    if p = [] then err "empty selection";
    match !errors with
    | [] ->
        let b = Buffer.create 1024 in
        Printf.bprintf b "hwfrp-verilator-select 1\nproducer %s %s\n" producer
          (match format with `Fst -> "fst" | `Vcd -> "vcd");
        String_set.iter (Printf.bprintf b "select %s\n") !natives;
        Ok (Buffer.contents b)
    | errs -> Error (sorted_uniq String.compare errs)
end
