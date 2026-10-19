[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Hwfrp
module Reference = Vcd_types.Reference

let time f =
  let t0 = Unix.gettimeofday () in
  let x = f () in
  (x, Unix.gettimeofday () -. t0)

let inputs (p : Platform.t) tr root =
  List.filter_map
    (fun (name, w) -> if w <= 62 && name <> p.clock then Some name else None)
    (Trace.scope_vars tr root)

let read path =
  let { Vcd.simulation; _ } = Vcd_fst.open_file path in
  Seq.fold_left (fun n _ -> n + 1) 0 simulation

(* Decoding alone, of what sampling would read. *)
let read_tracked (p : Platform.t) ~select path =
  let tr = Trace.open_file ~select path in
  let root = Platform.root p in
  let find n = ignore (Option.get (Trace.find tr (Reference.to_list root @ [ n ]))) in
  find p.clock;
  List.iter find (inputs p tr root);
  Seq.fold_left (fun n _ -> n + 1) 0 (Trace.events tr)

let sample (p : Platform.t) ~select path =
  let tr, open_s = time (fun () -> Trace.open_file ~select path) in
  let root = Platform.root p in
  let find n = Option.get (Trace.find tr (Reference.to_list root @ [ n ])) in
  let clk = find p.clock in
  let names = inputs p tr root in
  List.iter (fun n -> ignore (find n)) names;
  let s = Sampler.create tr [| { clock = clk.slot; rule = p.sample; enable = None } |] in
  let rec go n = match Sampler.next s with Some _ -> go (n + 1) | None -> n in
  let ticks, drain_s = time (fun () -> go 0) in
  (open_s, ticks, List.length names, drain_s, Sampler.stats s)

let engine (p : Platform.t) ~select ~nodes ~strategy path =
  let tr = Trace.open_file ~select path in
  let root = Platform.root p in
  let net = Net.create () in
  let (Clock.Any c) =
    Bind.clock net tr ~model:"bench" ~name:p.clock p.sample (Platform.scope p [ p.clock ])
  in
  let sc = Bind.root net tr c ~model:"bench" root in
  let pool =
    ref
      (Array.of_list
         (List.map (fun n -> Bind.signal sc n Bind.uint) (inputs p tr root) @ [ Sig.cycle c ]))
  in
  let rng = Random.State.make [| 1 |] in
  let pick () =
    let n = Array.length !pool in
    !pool.(n - 1 - Random.State.int rng (min n 16))
  in
  let mask = 0xffff in
  for _ = 1 to nodes do
    let s =
      match Random.State.int rng 5 with
      | 0 -> Sig.map (fun x -> ((x * 3) + 1) land mask) (pick ())
      | 1 -> Sig.map2 (fun x y -> (x + y) land mask) (pick ()) (pick ())
      | 2 -> Sig.pre ~init:0 (pick ())
      | 3 -> Sig.fold ~init:0 (fun a x -> (a + x) land mask) (Sig.changes (pick ()))
      | _ -> Sig.hold ~init:0 (Ev.filter (fun x -> x land 1 = 1) (Sig.changes (pick ())))
    in
    pool := Array.append !pool [| s |]
  done;
  let sched = Result.get_ok (Sched.compile ~strategy net) in
  Sched.run sched (Sampler.create tr (Net.domains net))

let run p ~select ~nodes path =
  let { Vcd.header; _ }, header_s = time (fun () -> Vcd_fst.open_file path) in
  let resolver, resolver_s = time (fun () -> Vcd.Resolver.make header) in
  Printf.printf "header  %.3f s, resolver %.3f s for %d signals\n" header_s resolver_s
    (Vcd.Resolver.fold (fun _ n -> n + 1) resolver 0);
  let events, read_s = time (fun () -> read path) in
  Printf.printf "decode  %d events in %.3f s, header included\n" events read_s;
  let events, read_s = time (fun () -> read_tracked p ~select path) in
  Printf.printf "decode  %d events in %.3f s, header included, %s\n" events read_s
    (if select then "tracked signals only" else "no selection");
  let open_s, ticks, inputs, drain_s, (st : Sampler.stats) = sample p ~select path in
  Printf.printf "open    %.3f s\n" open_s;
  Printf.printf "sample  %d inputs, %d ticks in %.3f s; %d of %d changes tracked\n" inputs ticks
    drain_s st.changes_tracked st.changes_seen;
  List.iter
    (fun (name, strategy) ->
      let st = engine p ~select ~nodes ~strategy path in
      let eval_s = st.wall_s -. drain_s in
      Printf.printf "%-12s %d nodes, %d evals in %.3f s" name (List.length st.per_node)
        st.node_evals st.wall_s;
      if eval_s > 0.001 then
        Printf.printf ", %.0f evals/s after sampling" (float st.node_evals /. eval_s);
      print_newline ())
    [ ("incremental", Sched.Incremental); ("sweep", Sched.Sweep) ]
