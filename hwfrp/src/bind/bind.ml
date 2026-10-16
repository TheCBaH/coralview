[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Vcd_types
open Frp

type width_rule = Exact of int | At_least of int | Up_to of int | Any_width

type requirement = {
  model : string;
  root : Reference.t;
  path : Reference.t;
  width : width_rule;
  purpose : string;
}

type status =
  | Bound of Trace.signal
  | Missing
  | Width_mismatch of { expected : width_rule; actual : int }
  | Not_a_vector of Vcd_ast.var_type

exception Unbound of requirement * status

type report = { model : string; root : Reference.t; entries : (requirement * status) list }

let pp_width_rule ppf = function
  | Exact n -> Format.fprintf ppf "%d" n
  | At_least n -> Format.fprintf ppf ">=%d" n
  | Up_to n -> Format.fprintf ppf "<=%d" n
  | Any_width -> Format.fprintf ppf "any"

let ok (_, s) = match s with Bound _ -> true | _ -> false

let relative (r : requirement) =
  let rec strip root path =
    match (root, path) with
    | [], _ -> Some path
    | a :: root, b :: path when a = b -> strip root path
    | _ -> None
  in
  match strip (Reference.to_list r.root) (Reference.to_list r.path) with
  | Some (_ :: _ as l) -> String.concat "." l
  | _ -> Reference.to_string r.path

let pp_entry ppf ((r : requirement), s) =
  let word, detail =
    match s with
    | Bound s -> ("bound", Printf.sprintf "%d" s.width)
    | Missing -> ("missing", "")
    | Width_mismatch { expected; actual } ->
        ("width", Format.asprintf "%d, expected %a" actual pp_width_rule expected)
    | Not_a_vector t -> ("type", Vcd.string_of_var_type t)
  in
  Format.fprintf ppf "  %-7s %s" word (relative r);
  if detail <> "" then Format.fprintf ppf " %s" detail;
  if r.purpose <> "" then Format.fprintf ppf ": %s" r.purpose

let pp_report ppf { model; root; entries } =
  Format.fprintf ppf "@[<v>%s at %s" model (Reference.to_string root);
  List.iter (Format.fprintf ppf "@,%a" pp_entry) entries;
  Format.fprintf ppf "@]"

let () =
  Printexc.register_printer (function
    | Unbound (r, s) -> Some (Format.asprintf "Bind.Unbound: %s:%a" r.model pp_entry (r, s))
    | _ -> None)

type Net.ext += Requirements of requirement list ref

let registry net =
  match List.find_map (function Requirements r -> Some r | _ -> None) (Net.exts net) with
  | Some r -> r
  | None ->
      let r = ref [] in
      Net.add_ext net (Requirements r);
      r

let requirements net =
  match List.find_map (function Requirements r -> Some r | _ -> None) (Net.exts net) with
  | Some r -> List.rev !r
  | None -> []

let width_ok rule w =
  match rule with Exact n -> w = n | At_least n -> w >= n | Up_to n -> w <= n | Any_width -> true

let is_vector = function
  | Vcd_ast.Real | Realtime | Real_parameter | Shortreal | Sstring -> false
  | _ -> true

let status tr path rule =
  match Trace.lookup tr path with
  | None -> Missing
  | Some e ->
      let w = Vcd.Resolver.entry_size e and vt = Trace.var_type tr e in
      if not (is_vector vt) then Not_a_vector vt
      else if not (width_ok rule w) then Width_mismatch { expected = rule; actual = w }
      else Bound (Trace.track tr e)

let require net tr (r : requirement) =
  match status tr r.path r.width with
  | Bound s ->
      let reg = registry net in
      reg := r :: !reg;
      s
  | s -> raise (Unbound (r, s))

let parent p = Reference.of_list (List.rev (List.tl (List.rev (Reference.to_list p))))

let clock net tr ~model ?(purpose = "") ~name ?enable rule path =
  let bit path = require net tr { model; root = parent path; path; width = Exact 1; purpose } in
  let s = bit path in
  let enable = Option.map (fun p -> (bit p).slot) enable in
  Clock.define net ~name { clock = s.slot; rule; enable }

type 'c scope = {
  net : Net.t;
  trace : Trace.t;
  clk : 'c Clock.t;
  model : string;
  root : Reference.t;
  rel : string list;
  overrides : (string * Reference.t) list;
}

let root net trace clk ~model ?(overrides = []) root =
  { net; trace; clk; model; root; rel = []; overrides }

let sub sc name = { sc with rel = sc.rel @ [ name ] }
let path sc = Reference.of_list (Reference.to_list sc.root @ sc.rel)
let vars sc = Trace.scope_vars sc.trace (path sc)

let find_roots tr pattern =
  let rec walk prefix acc (s : Vcd_ast.scope_node) =
    let p = prefix @ [ s.s_name ] in
    let acc = if Filter_matcher.matches pattern (Reference.of_list p) then p :: acc else acc in
    List.fold_left (walk p) acc s.children
  in
  List.fold_left (walk []) [] (Trace.header tr).scopes |> List.rev_map Reference.of_list

type 'a decoder = {
  dname : string;
  dwidth : width_rule;
  decode : Logic.t -> ('a, Logic.t) result;
  unknown : int -> 'a;
}

let known f (l : Logic.t) = match Logic.to_known l with Some b -> Ok (f b) | None -> Error l

let bool =
  {
    dname = "bool";
    dwidth = Exact 1;
    decode = known (fun b -> Bits.bit b 0);
    unknown = (fun _ -> false);
  }

let uint =
  { dname = "uint"; dwidth = Up_to 62; decode = known Bits.to_int_exn; unknown = (fun _ -> 0) }

let bits = { dname = "bits"; dwidth = Any_width; decode = known Fun.id; unknown = Bits.zero }
let logic = { dname = "logic"; dwidth = Any_width; decode = Result.ok; unknown = Logic.unknown }

let field ~lo ~width =
  {
    dname = Printf.sprintf "field[%d+:%d]" lo width;
    dwidth = At_least (lo + width);
    decode =
      (fun l ->
        if Bits.is_zero (Bits.field l.Logic.unknown ~lo ~width) then
          Ok (Bits.field_int l.Logic.bits ~lo ~width)
        else Error l);
    unknown = (fun _ -> 0);
  }

let resolve ?(purpose = "") sc name width =
  let rel = String.concat "." (sc.rel @ [ name ]) in
  let path =
    match List.assoc_opt rel sc.overrides with
    | Some p -> p
    | None -> Reference.of_list (Reference.to_list sc.root @ sc.rel @ [ name ])
  in
  require sc.net sc.trace { model = sc.model; root = sc.root; path; width; purpose }

let decode sc d (s : Trace.signal) l =
  match d.decode l with
  | Ok v -> v
  | Error l ->
      Diag.report sc.net
        (Diag.make ~paths:[ s.path ] ~source:sc.model ~code:"bind.unknown-bits"
           (Printf.sprintf "%s of %s" d.dname (Logic.to_string l)));
      d.unknown s.width

let signal ?purpose sc name d =
  let s = resolve ?purpose sc name d.dwidth in
  Source.logic sc.clk s ~init:(d.unknown s.width) (decode sc d s)

let clock_of sc = sc.clk
let net_of sc = sc.net

let check tr reqs =
  let groups = ref [] in
  List.iter
    (fun (r : requirement) ->
      let e = (r, status tr r.path r.width) in
      match
        List.find_opt
          (fun (g : report ref) -> !g.model = r.model && Reference.equal !g.root r.root)
          !groups
      with
      | Some g -> g := { !g with entries = e :: !g.entries }
      | None -> groups := ref { model = r.model; root = r.root; entries = [ e ] } :: !groups)
    reqs;
  List.rev_map (fun g -> { !g with entries = List.rev !g.entries }) !groups
