[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

module IM = Map.Make (Int)

let vtype (o : Ops.op) =
  let lmul =
    match Option.value o.lmul_orig ~default:o.lmul with
    | "1/2" -> "mf2"
    | "1/4" -> "mf4"
    | "1/8" -> "mf8"
    | m -> "m" ^ m
  in
  Printf.sprintf "e%d,%s" o.sew lmul

let join commits ops =
  (* Commits by PC, in program order. *)
  let by_pc =
    List.fold_left
      (fun m (c : Commits.commit) ->
        IM.update c.pc (fun l -> Some (c :: Option.value l ~default:[])) m)
      IM.empty commits
    |> IM.map List.rev
  in
  let ops_by_pc =
    List.fold_left
      (fun m (o : Ops.op) ->
        match o.pc with
        | None -> m
        | Some pc -> IM.update pc (fun l -> Some (o :: Option.value l ~default:[])) m)
      IM.empty ops
    |> IM.map (List.sort (fun (a : Ops.op) b -> compare a.cycle b.cycle))
  in
  let t = Hashtbl.create 64 in
  IM.iter
    (fun pc ops ->
      let rec go cs = function
        | [] -> ()
        | (c : Commits.commit) :: rest ->
            let from = Option.value c.dispatched ~default:min_int in
            let until =
              match rest with
              | (n : Commits.commit) :: _ -> Option.value n.dispatched ~default:max_int
              | [] -> max_int
            in
            (match List.find_opt (fun (o : Ops.op) -> o.cycle >= from && o.cycle < until) ops with
            | Some o -> Hashtbl.replace t (pc, c.retired) o
            | None -> ());
            go cs rest
      in
      go () (Option.value (IM.find_opt pc by_pc) ~default:[]))
    ops_by_pc;
  t

let notes ~static commits ops =
  let t = join commits ops in
  fun ~pc ~cycle ->
    Option.map
      (fun (o : Ops.op) ->
        let traced = vtype o in
        let base = Printf.sprintf "%s vl %d" traced o.vl in
        match static pc with
        | Some s when not (String.starts_with ~prefix:traced s) ->
            let s =
              match String.index_opt s ',' with
              | Some i -> (
                  match String.index_from_opt s (i + 1) ',' with
                  | Some j -> String.sub s 0 j
                  | None -> s)
              | None -> s
            in
            Printf.sprintf "%s (static %s)" base s
        | _ -> base)
      (Hashtbl.find_opt t (pc, cycle))
