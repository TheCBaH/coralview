[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Vcd_types

type slot = int

type signal = {
  slot : slot;
  id : ID.t;
  path : Reference.t;
  aliases : Vcd.Ref_set.t;
  width : int;
  var_type : Vcd_ast.var_type;
}

type t = {
  format : Vcd_fst.format;
  header : Vcd_ast.header;
  resolver : Vcd.Resolver.t;
  var_types : (string, Vcd_ast.var_type) Hashtbl.t;
  by_id : (string, signal) Hashtbl.t;
  mutable tracked : signal list;
  mutable count : int;
  mutable frozen : bool;
  mutable events : Vcd_ast.event Seq.t option;
}

(* The parse reads only the tracked signals' changes: ovcd asks [select] on the first pull, after
   [events] has frozen the tracked set. *)
let make ~select format parse =
  let by_id = Hashtbl.create 256 in
  let { Vcd.header; simulation } =
    parse (if select then Some (fun id -> Hashtbl.mem by_id (ID.to_string id)) else None)
  in
  let var_types = Hashtbl.create 1024 in
  let rec walk (s : Vcd_ast.scope_node) =
    List.iter
      (fun (v : Vcd_ast.var_decl) -> Hashtbl.replace var_types (ID.to_string v.id) v.v_type)
      s.vars;
    List.iter walk s.children
  in
  List.iter walk header.scopes;
  {
    format;
    header;
    resolver = Vcd.Resolver.make header;
    var_types;
    by_id;
    tracked = [];
    count = 0;
    frozen = false;
    events = Some simulation;
  }

let open_file ?(select = true) path =
  make ~select (Vcd_fst.detect_file path) (fun select -> Vcd_fst.open_file ?select path)

let of_string ?(select = true) s =
  make ~select (Vcd_fst.detect_string s) (fun select -> Vcd_fst.open_string ?select s)

let format t = t.format
let header t = t.header
let resolver t = t.resolver

let lookup t r =
  match Vcd.Resolver.find_id t.resolver r with
  | None -> None
  | Some id -> Vcd.Resolver.find t.resolver id

let track t entry =
  let id = Vcd.Resolver.entry_id entry in
  match Hashtbl.find_opt t.by_id (ID.to_string id) with
  | Some s -> s
  | None ->
      if t.frozen then invalid_arg "Trace.track: trace is frozen";
      let aliases = Vcd.Resolver.entry_references entry in
      let s =
        {
          slot = t.count;
          id;
          path = Vcd.Ref_set.min_elt aliases;
          aliases;
          width = Vcd.Resolver.entry_size entry;
          var_type =
            Option.value (Hashtbl.find_opt t.var_types (ID.to_string id)) ~default:Vcd_ast.Wire;
        }
      in
      Hashtbl.add t.by_id (ID.to_string id) s;
      t.tracked <- s :: t.tracked;
      t.count <- t.count + 1;
      s

let track_path t path = Option.map (track t) (lookup t (Reference.of_string path))
let tracked t = Array.of_list (List.rev t.tracked)
let freeze t = t.frozen <- true

let events t =
  t.frozen <- true;
  match t.events with
  | Some e ->
      t.events <- None;
      e
  | None -> invalid_arg "Trace.events: already consumed"

let events_pulled t = Option.is_none t.events

type sample_rule = After_falling | Before_rising | After_rising
type domain_spec = { clock : slot; rule : sample_rule; enable : slot option }
type tick = { domain : int; index : int; time : Timestamp.t; enabled : bool }

let find t path = Option.map (track t) (lookup t (Reference.of_list path))

let paths_ending t name =
  Vcd.Resolver.fold
    (fun e acc ->
      Vcd.Ref_set.fold
        (fun r acc ->
          match List.rev (Reference.to_list r) with n :: _ when n = name -> r :: acc | _ -> acc)
        (Vcd.Resolver.entry_references e) acc)
    t.resolver []
  |> List.sort (fun a b ->
      match Int.compare (List.length (Reference.to_list a)) (List.length (Reference.to_list b)) with
      | 0 -> Reference.compare a b
      | c -> c)

let var_type t entry =
  Option.value
    (Hashtbl.find_opt t.var_types (ID.to_string (Vcd.Resolver.entry_id entry)))
    ~default:Vcd_ast.Wire

let scope_vars t path =
  let rec descend (nodes : Vcd_ast.scope_node list) = function
    | [] -> []
    | [ n ] -> List.filter (fun (s : Vcd_ast.scope_node) -> s.s_name = n) nodes
    | n :: rest ->
        List.concat_map
          (fun (s : Vcd_ast.scope_node) -> if s.s_name = n then descend s.children rest else [])
          nodes
  in
  List.concat_map
    (fun (s : Vcd_ast.scope_node) ->
      List.map (fun (v : Vcd_ast.var_decl) -> (v.ref, v.size)) s.vars)
    (descend t.header.scopes (Reference.to_list path))
