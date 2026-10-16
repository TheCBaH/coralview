[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Frp
module M = Map.Make (Int)

type 'v t = 'v M.t

let empty = M.empty
let of_list l = List.fold_left (fun m (k, v) -> M.add k v m) M.empty l
let get t k = M.find_opt k t
let bindings = M.bindings
let cardinal = M.cardinal
let equal = M.equal

let diff eq a b =
  M.merge
    (fun _ x y ->
      match (x, y) with Some x, Some y when eq x y -> None | None, None -> None | _ -> Some (x, y))
    a b
  |> M.bindings
  |> List.map (fun (k, (x, y)) -> (k, x, y))

type ('v, 'c) store = { state : ('v t, 'c) Sig.t; changes : ((int * 'v) list, 'c) Ev.t }
type 'v step = { snap : 'v t; delta : (int * 'v) list }

let keys s = Ev.map (List.map fst) s.changes

(* The changes of a source-backed step signal: at every update, and at the first sample. *)
let store_of_source clk r =
  let first = Ev.when_ (Sig.map (fun c -> c = 0) (Sig.cycle clk)) r in
  let updated = Ev.merge (fun a _ -> a) (Sig.changes r) first in
  {
    state = Sig.map (fun r -> r.snap) r;
    changes = Ev.filter_map (fun r -> if r.delta = [] then None else Some r.delta) updated;
  }

let update eq keys read prev changed =
  let snap, delta =
    List.fold_left
      (fun (snap, delta) i ->
        let k = keys.(i) and v = read i in
        match M.find_opt k snap with
        | Some old when eq old v -> (snap, delta)
        | _ -> (M.add k v snap, (k, v) :: delta))
      (prev.snap, []) changed
  in
  if delta = [] then prev
  else { snap; delta = List.sort (fun (a, _) (b, _) -> Int.compare a b) delta }

let mirror ?purpose ?(eq = ( = )) sc entries d =
  let keys = Array.of_list (List.map fst entries) in
  let signals =
    Array.of_list (List.map (fun (_, name) -> Bind.resolve ?purpose sc name d.Bind.dwidth) entries)
  in
  let r =
    Source.many (Bind.clock_of sc) signals ~init:{ snap = M.empty; delta = [] }
      (fun changed logic prev ->
        update eq keys (fun i -> Bind.decode sc d signals.(i) (logic i)) prev changed)
  in
  store_of_source (Bind.clock_of sc) r

let mirror_fields ?purpose ?(eq = ( = )) sc entries combine =
  let fields =
    List.concat_map (fun (k, fs) -> List.map (fun (name, w) -> (k, name, w)) fs) entries
  in
  let signals =
    Array.of_list (List.map (fun (_, name, w) -> Bind.resolve ?purpose sc name w) fields)
  in
  let entry = Array.of_list (List.map (fun (k, _, _) -> k) fields) in
  let members = Hashtbl.create 64 in
  List.iteri
    (fun i (k, _, _) ->
      Hashtbl.replace members k (Option.value (Hashtbl.find_opt members k) ~default:[] @ [ i ]))
    fields;
  let keys = Array.of_list (List.map fst entries) in
  let position = Hashtbl.create 64 in
  Array.iteri (fun p k -> Hashtbl.replace position k p) keys;
  let r =
    Source.many (Bind.clock_of sc) signals ~init:{ snap = M.empty; delta = [] }
      (fun changed logic prev ->
        let touched =
          List.sort_uniq Int.compare (List.map (fun i -> Hashtbl.find position entry.(i)) changed)
        in
        update eq keys
          (fun p -> combine (List.map logic (Hashtbl.find members keys.(p))))
          prev touched)
  in
  store_of_source (Bind.clock_of sc) r

let mirror_packed ?purpose ?(first_key = 0) ?(eq = ( = )) sc name ~entries ~width decode =
  let d = { Bind.bits with dwidth = Exact (entries * width) } in
  let s = Bind.resolve ?purpose sc name d.dwidth in
  let keys = Array.init entries (fun i -> first_key + i) in
  let r =
    Source.many (Bind.clock_of sc) [| s |] ~init:{ snap = M.empty; delta = [] } (fun _ logic prev ->
        let v = Bind.decode sc d s (logic 0) in
        update eq keys
          (fun i -> decode (Bits.field v ~lo:(i * width) ~width))
          prev (List.init entries Fun.id))
  in
  store_of_source (Bind.clock_of sc) r

let previous clk s =
  let state = Sig.pre ~init:M.empty s.state in
  let last =
    Sig.hold ~init:(-1, []) (Ev.map (fun (d, c) -> (c, d)) (Ev.tag (Sig.cycle clk) s.changes))
  in
  let before = Sig.pre ~init:(-1, []) last in
  let changes =
    Ev.filter_map
      (fun ((c, d), now) -> if c = now - 1 && d <> [] then Some d else None)
      (Ev.when_ (Sig.const clk true) (Sig.map2 (fun b n -> (b, n)) before (Sig.cycle clk)))
  in
  { state; changes }

let replay ?(eq = ( = )) ~init merge writes =
  let r =
    Sig.fold ~init:{ snap = init; delta = [] }
      (fun prev ws ->
        let snap =
          List.fold_left
            (fun snap (k, w) -> M.add k (merge (M.find_opt k snap) w) snap)
            prev.snap ws
        in
        let delta =
          List.sort_uniq Int.compare (List.map fst ws)
          |> List.filter_map (fun k ->
              let v = M.find k snap in
              match M.find_opt k prev.snap with Some old when eq old v -> None | _ -> Some (k, v))
        in
        { snap; delta })
      writes
  in
  {
    state = Sig.map (fun r -> r.snap) r;
    changes =
      Ev.filter_map (fun (_, r) -> if r.delta = [] then None else Some r.delta) (Ev.tag r writes);
  }

let relate ?(severity = Diag.Error) clk net ~source ~code ~keys dirty check =
  let failing = Hashtbl.create 16 in
  let first =
    Ev.map (fun _ -> keys) (Ev.when_ (Sig.map (fun c -> c = 0) (Sig.cycle clk)) (Sig.cycle clk))
  in
  let all =
    Ev.map (fun ls -> List.sort_uniq Int.compare (List.concat ls)) (Ev.union (first :: dirty))
  in
  Ev.subscribe all
    (List.iter (fun k ->
         match check k with
         | None -> Hashtbl.remove failing k
         | Some msg ->
             if not (Hashtbl.mem failing k) then begin
               Hashtbl.replace failing k ();
               Diag.report net
                 (Diag.make ~severity ~source ~code (Printf.sprintf "key %d: %s" k msg))
             end))
