[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Ovcd_types

type slot = int

type signal = {
  slot : slot;
  id : ID.t;
  path : Reference.t;
  aliases : Ovcd.Vcd.Ref_set.t;
  width : int;
  var_type : Ovcd.Ast.var_type;
}

type format = [ `Vcd | `Fst ]
type pull = Event of Ovcd.Ast.event | Starved | Ended

type t = {
  format : format;
  header : Ovcd.Ast.header;
  resolver : Ovcd.Vcd.Resolver.t;
  var_types : (string, Ovcd.Ast.var_type) Hashtbl.t;
  by_id : (string, signal) Hashtbl.t;
  mutable tracked : signal list;
  mutable count : int;
  mutable frozen : bool;
  mutable events : (unit -> pull) option;
  mutable closers : (unit -> unit) list;
}

(* The parse reads only the tracked signals' changes: ovcd asks [select] on the first pull, after
   [events] has frozen the tracked set. *)
let of_header ~format header events =
  let by_id = Hashtbl.create 256 in
  let var_types = Hashtbl.create 1024 in
  let rec walk (s : Ovcd.Ast.scope_node) =
    List.iter
      (fun (v : Ovcd.Ast.var_decl) -> Hashtbl.replace var_types (ID.to_string v.id) v.v_type)
      s.vars;
    List.iter walk s.children
  in
  List.iter walk header.Ovcd.Ast.scopes;
  ( {
      format;
      header;
      resolver = Ovcd.Vcd.Resolver.make header;
      var_types;
      by_id;
      tracked = [];
      count = 0;
      frozen = false;
      events = Some events;
      closers = [];
    },
    by_id )

let pull_of_seq seq =
  let rest = ref seq in
  fun () ->
    match !rest () with
    | Seq.Nil -> Ended
    | Seq.Cons (e, r) ->
        rest := r;
        Event e

(* The parse reads only the tracked signals' changes: ovcd asks [select] on the first pull, after
   [events] has frozen the tracked set. *)
let of_parse ?(select = true) ~format parse =
  let by_id_ref = ref None in
  let { Ovcd.Vcd.header; simulation } =
    parse
      (if select then
         Some
           (fun id ->
             match !by_id_ref with Some h -> Hashtbl.mem h (ID.to_string id) | None -> false)
       else None)
  in
  let t, by_id = of_header ~format header (pull_of_seq simulation) in
  by_id_ref := Some by_id;
  t

let of_pull ~format header pull = fst (of_header ~format header pull)
let on_close t f = t.closers <- f :: t.closers

let close t =
  let l = t.closers in
  t.closers <- [];
  List.iter (fun f -> f ()) l

let format t = t.format
let header t = t.header
let resolver t = t.resolver

let lookup t r =
  match Ovcd.Vcd.Resolver.find_id t.resolver r with
  | None -> None
  | Some id -> Ovcd.Vcd.Resolver.find t.resolver id

let unbound ~path ~width =
  {
    slot = -1;
    id = ID.of_string "";
    path;
    aliases = Ovcd.Vcd.Ref_set.singleton path;
    width;
    var_type = Ovcd.Ast.Wire;
  }

let track t entry =
  let id = Ovcd.Vcd.Resolver.entry_id entry in
  match Hashtbl.find_opt t.by_id (ID.to_string id) with
  | Some s -> s
  | None ->
      if t.frozen then invalid_arg "Trace.track: trace is frozen";
      let aliases = Ovcd.Vcd.Resolver.entry_references entry in
      let s =
        {
          slot = t.count;
          id;
          path = Ovcd.Vcd.Ref_set.min_elt aliases;
          aliases;
          width = Ovcd.Vcd.Resolver.entry_size entry;
          var_type =
            Option.value (Hashtbl.find_opt t.var_types (ID.to_string id)) ~default:Ovcd.Ast.Wire;
        }
      in
      Hashtbl.add t.by_id (ID.to_string id) s;
      t.tracked <- s :: t.tracked;
      t.count <- t.count + 1;
      s

let track_path t path = Option.map (track t) (lookup t (Reference.of_string path))
let tracked t = Array.of_list (List.rev t.tracked)
let freeze t = t.frozen <- true

let pull t =
  t.frozen <- true;
  match t.events with
  | Some e ->
      t.events <- None;
      e
  | None -> invalid_arg "Trace.events: already consumed"

let events t =
  let next = pull t in
  Seq.of_dispenser (fun () ->
      match next () with
      | Event e -> Some e
      | Ended -> None
      | Starved -> invalid_arg "Trace.events: the source is starved; use Trace.pull")

let events_pulled t = Option.is_none t.events

type sample_rule = After_falling | Before_rising | After_rising
type reset = { signal : slot; active : bool }
type domain_spec = { clock : slot; rule : sample_rule; enable : slot option; reset : reset option }
type tick = { domain : int; index : int; time : Timestamp.t; enabled : bool; in_reset : bool }

let find t path = Option.map (track t) (lookup t (Reference.of_list path))

let paths_ending t name =
  Ovcd.Vcd.Resolver.fold
    (fun e acc ->
      Ovcd.Vcd.Ref_set.fold
        (fun r acc ->
          match List.rev (Reference.to_list r) with n :: _ when n = name -> r :: acc | _ -> acc)
        (Ovcd.Vcd.Resolver.entry_references e)
        acc)
    t.resolver []
  |> List.sort (fun a b ->
      match Int.compare (List.length (Reference.to_list a)) (List.length (Reference.to_list b)) with
      | 0 -> Reference.compare a b
      | c -> c)

let var_type t entry =
  Option.value
    (Hashtbl.find_opt t.var_types (ID.to_string (Ovcd.Vcd.Resolver.entry_id entry)))
    ~default:Ovcd.Ast.Wire

let scope_vars t path =
  let rec descend (nodes : Ovcd.Ast.scope_node list) = function
    | [] -> []
    | [ n ] -> List.filter (fun (s : Ovcd.Ast.scope_node) -> s.s_name = n) nodes
    | n :: rest ->
        List.concat_map
          (fun (s : Ovcd.Ast.scope_node) -> if s.s_name = n then descend s.children rest else [])
          nodes
  in
  List.concat_map
    (fun (s : Ovcd.Ast.scope_node) ->
      List.map (fun (v : Ovcd.Ast.var_decl) -> (v.ref, v.size)) s.vars)
    (descend t.header.scopes (Reference.to_list path))
