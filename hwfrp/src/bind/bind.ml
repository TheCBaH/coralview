[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Vcd_types
open Frp

type need = Required | Optional
type width_rule = Exact of int | At_least of int | Up_to of int | Any_width

type requirement = {
  model : string;
  root : Reference.t;
  path : Reference.t;
  width : width_rule;
  need : need;
  purpose : string;
}

type status =
  | Bound of Trace.signal
  | Missing
  | Width_mismatch of { expected : width_rule; actual : int }
  | Not_a_vector of Vcd_ast.var_type

type report = { model : string; root : Reference.t; entries : (requirement * status) list }

let pp_width_rule ppf = function
  | Exact n -> Format.fprintf ppf "%d" n
  | At_least n -> Format.fprintf ppf ">=%d" n
  | Up_to n -> Format.fprintf ppf "<=%d" n
  | Any_width -> Format.fprintf ppf "any"

let failed (r, s) = r.need = Required && match s with Bound _ -> false | _ -> true

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
  if r.need = Optional then Format.fprintf ppf " (optional)";
  if r.purpose <> "" then Format.fprintf ppf ": %s" r.purpose

let pp_report ppf { model; root; entries } =
  Format.fprintf ppf "@[<v>%s at %s" model (Reference.to_string root);
  List.iter (Format.fprintf ppf "@,%a" pp_entry) entries;
  Format.fprintf ppf "@]"

type Net.ext += Requirements of (requirement * status) list ref

let registry net =
  match List.find_map (function Requirements r -> Some r | _ -> None) (Net.exts net) with
  | Some r -> r
  | None ->
      let r = ref [] in
      Net.add_ext net (Requirements r);
      Net.add_check net (fun () ->
          List.rev !r |> List.filter failed |> List.map (fun e -> Format.asprintf "%a" pp_entry e));
      r

let requirements net =
  match List.find_map (function Requirements r -> Some r | _ -> None) (Net.exts net) with
  | Some r -> List.rev_map fst !r
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

let record net (r : requirement) s =
  let reg = registry net in
  reg := (r, s) :: !reg;
  match s with Bound s -> Some s | _ -> None

let clock net tr ~model ?(purpose = "") ~name ?enable rule path =
  let parent p = Reference.of_list (List.rev (List.tl (List.rev (Reference.to_list p)))) in
  let bind need path =
    record net
      { model; root = parent path; path; width = Exact 1; need; purpose }
      (status tr path (Exact 1))
  in
  match bind Required path with
  | None -> None
  | Some s ->
      let enable =
        Option.map (fun p -> Option.map (fun (e : Trace.signal) -> e.slot) (bind Required p)) enable
      in
      if enable = Some None then None
      else Some (Clock.define net ~name { clock = s.slot; rule; enable = Option.join enable })

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
  default : int -> 'a;
}

let known f (l : Logic.t) = match Logic.to_known l with Some b -> Ok (f b) | None -> Error l

let bool =
  {
    dname = "bool";
    dwidth = Exact 1;
    decode = known (fun b -> Bits.bit b 0);
    default = (fun _ -> false);
  }

let uint =
  { dname = "uint"; dwidth = Up_to 62; decode = known Bits.to_int_exn; default = (fun _ -> 0) }

let bits = { dname = "bits"; dwidth = Any_width; decode = known Fun.id; default = Bits.zero }
let logic = { dname = "logic"; dwidth = Any_width; decode = Result.ok; default = Logic.unknown }

let field ~lo ~width =
  {
    dname = Printf.sprintf "field[%d+:%d]" lo width;
    dwidth = At_least (lo + width);
    decode =
      (fun l ->
        if Bits.is_zero (Bits.field l.Logic.unknown ~lo ~width) then
          Ok (Bits.field_int l.Logic.bits ~lo ~width)
        else Error l);
    default = (fun _ -> 0);
  }

let nominal = function Exact n | At_least n | Up_to n -> n | Any_width -> 1

let bind ~need ~purpose sc name d =
  let rel = String.concat "." (sc.rel @ [ name ]) in
  let path =
    match List.assoc_opt rel sc.overrides with
    | Some p -> p
    | None -> Reference.of_list (Reference.to_list sc.root @ sc.rel @ [ name ])
  in
  record sc.net
    { model = sc.model; root = sc.root; path; width = d.dwidth; need; purpose }
    (status sc.trace path d.dwidth)

let source sc (s : Trace.signal) d wrap =
  let fallback = d.default s.width in
  Source.logic sc.clk s ~init:(wrap fallback) (fun l ->
      match d.decode l with
      | Ok v -> wrap v
      | Error l ->
          Diag.report sc.net
            (Diag.make ~paths:[ s.path ] ~source:sc.model ~code:"bind.unknown-bits"
               (Printf.sprintf "%s of %s" d.dname (Logic.to_string l)));
          wrap fallback)

let signal ?(need = Required) ?(purpose = "") sc name d =
  match bind ~need ~purpose sc name d with
  | Some s -> source sc s d Fun.id
  | None -> Sig.const sc.clk (d.default (nominal d.dwidth))

let optional ?(purpose = "") sc name d =
  match bind ~need:Optional ~purpose sc name d with
  | Some s -> source sc s d Option.some
  | None -> Sig.const sc.clk None

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
