[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

type t = {
  first : int;
  last : int option;
  instructions : int;
  cycles : int;
  loads : int option;
  stores : int option;
  vector_instructions : int option;
  vector_ops : int option;
  stalls : (string * int) list option;
}

let make ~(window : Text.window) ~end_cycle ~commits ~accesses ~ops ~stalls =
  let selected ~cycle ~pc = Text.selected window ~cycle ~pc in
  let commits =
    List.filter (fun (c : Commits.commit) -> selected ~cycle:c.retired ~pc:c.pc) commits
  in
  let reads, writes =
    match accesses with
    | None -> (None, None)
    | Some accesses ->
        let r, w =
          List.fold_left
            (fun (r, w) (a : Memory.Event.access) ->
              if selected ~cycle:a.cycle ~pc:a.pc then
                if a.access.write then (r, w + 1) else (r + 1, w)
              else (r, w))
            (0, 0) accesses
        in
        (Some r, Some w)
  in
  let ops =
    Option.map
      (List.filter (fun (o : Ops.op) ->
           selected ~cycle:o.cycle ~pc:(Option.value o.pc ~default:(-1))))
      ops
  in
  let stalls =
    Option.map
      (fun spans ->
        let total = Hashtbl.create 16 in
        List.iter
          (fun (s : Stalls.Event.stall_span) ->
            let stop = Option.value s.span.stop ~default:end_cycle in
            let lo = max s.span.start window.first and hi = min stop window.last in
            if hi >= lo then
              Hashtbl.replace total s.reason
                (hi - lo + 1 + Option.value (Hashtbl.find_opt total s.reason) ~default:0))
          spans;
        List.filter_map
          (fun r -> Option.map (fun n -> (Stalls.reason_name r, n)) (Hashtbl.find_opt total r))
          Stalls.reasons)
      stalls
  in
  {
    first = window.first;
    last = (if window.last = max_int then None else Some window.last);
    instructions = List.length commits;
    cycles = List.fold_left (fun n (c : Commits.commit) -> n + c.charged) 0 commits;
    loads = reads;
    stores = writes;
    vector_instructions = Option.map List.length ops;
    vector_ops = Option.map (List.fold_left (fun n (o : Ops.op) -> n + o.ops) 0) ops;
    stalls;
  }

let stall_jsont =
  Jsont.Object.map ~kind:"stall" (fun reason lane_cycles -> (reason, lane_cycles))
  |> Jsont.Object.mem "reason" Jsont.string ~enc:fst
  |> Jsont.Object.mem "lane_cycles" Jsont.int ~enc:snd
  |> Jsont.Object.finish

let jsont =
  Codec.record "summary.window"
    (fun first last instructions cycles loads stores vector_instructions vector_ops stalls : t ->
      { first; last; instructions; cycles; loads; stores; vector_instructions; vector_ops; stalls })
  |> Jsont.Object.mem "first" Jsont.int ~enc:(fun (s : t) -> s.first)
  |> Codec.opt (fun (s : t) -> s.last) "last" Jsont.int
  |> Jsont.Object.mem "instructions" Jsont.int ~enc:(fun (s : t) -> s.instructions)
  |> Jsont.Object.mem "cycles" Jsont.int ~enc:(fun (s : t) -> s.cycles)
  |> Codec.opt (fun (s : t) -> s.loads) "loads" Jsont.int
  |> Codec.opt (fun (s : t) -> s.stores) "stores" Jsont.int
  |> Codec.opt (fun (s : t) -> s.vector_instructions) "vector_instructions" Jsont.int
  |> Codec.opt (fun (s : t) -> s.vector_ops) "vector_ops" Jsont.int
  |> Codec.opt (fun (s : t) -> s.stalls) "stalls" (Jsont.list stall_jsont)
  |> Jsont.Object.finish

let text (s : t) =
  Printf.printf "window [%d, %s]\n" s.first
    (match s.last with Some l -> string_of_int l | None -> "end");
  Printf.printf "  instructions %d, cycles charged %d\n" s.instructions s.cycles;
  (match (s.loads, s.stores) with
  | Some l, Some w -> Printf.printf "  data requests: %d loads, %d stores\n" l w
  | _ -> ());
  (match (s.vector_instructions, s.vector_ops) with
  | Some i, Some o -> Printf.printf "  vector: %d instructions, %d operations\n" i o
  | _ -> ());
  match s.stalls with
  | Some l when l <> [] ->
      Printf.printf "  dispatch lane-cycles: %s\n"
        (String.concat ", " (List.map (fun (r, n) -> Printf.sprintf "%s %d" r n) l))
  | _ -> ()

let analyze (p : Platform.t) ~window ?(region = Region.none) trace =
  let (Core.Any c) = Core.bind p trace ~model:"summary" in
  let has needs = List.for_all (fun b -> List.mem b (Platform.blocks p)) needs in
  let commits = ref [] in
  let commit_summary =
    Analysis.subscribe
      (module Commits)
      () c
      (function Commits.Event.Commit k -> commits := k :: !commits | In_flight _ -> ())
  in
  let accesses =
    if has Memory.needs then
      let l = ref [] in
      let (_ : Hwfrp.Sched.run_stats -> Memory.Summary.t) =
        Analysis.subscribe
          (module Memory)
          { region } c
          (function Memory.Event.Access a -> l := a :: !l | Fault _ -> ())
      in
      Some l
    else None
  in
  let ops =
    if has Ops.needs then
      let l = ref [] in
      let (_ : Hwfrp.Sched.run_stats -> Ops.Summary.t) =
        Analysis.subscribe
          (module Ops)
          Ops.Config.default c
          (function Ops.Event.Op o -> l := o :: !l | Burst _ -> ())
      in
      Some l
    else None
  in
  let stalls =
    if has Stalls.needs then
      let l = ref [] in
      let (_ : Hwfrp.Sched.run_stats -> Stalls.Summary.t) =
        Analysis.subscribe
          (module Stalls)
          Stalls.Config.default c
          (fun (Stalls.Event.Stall_span s) -> l := s :: !l)
      in
      Some l
    else None
  in
  let stats = Core.run c in
  let cycles = (commit_summary stats).cycles in
  let rev o = Option.map (fun l -> List.rev !l) o in
  let commits = List.rev !commits in
  ( make ~window ~end_cycle:(cycles - 1) ~commits ~accesses:(rev accesses) ~ops:(rev ops)
      ~stalls:(rev stalls),
    commits )

let of_trace p ~window ?region trace = fst (analyze p ~window ?region trace)
