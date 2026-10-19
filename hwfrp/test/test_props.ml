open Hwfrp
open Vcd_types

(* Random traces: clocks [top.clk<k>] and 4-bit data [top.d<i>], with value -1 for x. *)
type wave = {
  nclk : int;
  ndata : int;
  rules : Trace.sample_rule array;
  steps : (int * (int * int) list) list;  (** time delta, changes *)
}

let rule_name = function
  | Trace.After_falling -> "after_falling"
  | Before_rising -> "before_rising"
  | After_rising -> "after_rising"

let id i = String.make 1 (Char.chr (33 + i))

let vcd w =
  let b = Buffer.create 1024 in
  let p fmt = Printf.bprintf b fmt in
  p "$timescale 1ps $end\n$scope module top $end\n";
  for k = 0 to w.nclk - 1 do
    p "$var wire 1 %s clk%d $end\n" (id k) k
  done;
  for i = 0 to w.ndata - 1 do
    p "$var wire 4 %s d%d $end\n" (id (w.nclk + i)) i
  done;
  p "$upscope $end\n$enddefinitions $end\n#0\n$dumpvars\n";
  for k = 0 to w.nclk - 1 do
    p "0%s\n" (id k)
  done;
  for i = 0 to w.ndata - 1 do
    p "b0 %s\n" (id (w.nclk + i))
  done;
  p "$end\n";
  ignore
    (List.fold_left
       (fun t (dt, changes) ->
         let t = t + dt in
         p "#%d\n" t;
         List.iter
           (fun (s, v) ->
             if s < w.nclk then p "%d%s\n" (v land 1) (id s)
             else if v < 0 then p "bx %s\n" (id s)
             else
               p "b%s %s\n"
                 (String.init 4 (fun j -> if v land (1 lsl (3 - j)) <> 0 then '1' else '0'))
                 (id s))
           changes;
         t)
       0 w.steps);
  Buffer.contents b

let rules = [| Trace.After_falling; Before_rising; After_rising |]

let gen_wave =
  let open QCheck2.Gen in
  int_range 1 2 >>= fun nclk ->
  int_range 1 3 >>= fun ndata ->
  list_size (return nclk) (int_bound 2) >>= fun rs ->
  list_size (int_range 1 40)
    (pair (int_range 1 3)
       (list_size (int_range 0 4) (pair (int_bound (nclk + ndata - 1)) (int_range (-1) 15))))
  >|= fun steps -> { nclk; ndata; rules = Array.of_list (List.map (Array.get rules) rs); steps }

(* Random programs over int signals and events, per domain; arguments index the domain's pools. *)
type op =
  | Map of int * int
  | Map2 of int * int
  | Pre of int
  | All of int * int
  | Hold of int
  | Fold of int
  | Machine of int * bool
  | Changes of int
  | When of int * int
  | Rising of int
  | Merge of int * int
  | Union of int * int
  | Tag of int * int
  | Scan of int
  | Filter of int
  | Resample of int
  | Gather of int * int
  | Current of int

let op_name = function
  | Map (f, a) -> Printf.sprintf "map%d s%d" f a
  | Map2 (a, b) -> Printf.sprintf "map2 s%d s%d" a b
  | Pre a -> Printf.sprintf "pre s%d" a
  | All (a, b) -> Printf.sprintf "all s%d s%d" a b
  | Hold e -> Printf.sprintf "hold e%d" e
  | Fold e -> Printf.sprintf "fold e%d" e
  | Machine (a, every) -> Printf.sprintf "machine s%d every=%b" a every
  | Changes a -> Printf.sprintf "changes s%d" a
  | When (c, s) -> Printf.sprintf "when s%d s%d" c s
  | Rising a -> Printf.sprintf "rising s%d" a
  | Merge (a, b) -> Printf.sprintf "merge e%d e%d" a b
  | Union (a, b) -> Printf.sprintf "union e%d e%d" a b
  | Tag (s, e) -> Printf.sprintf "tag s%d e%d" s e
  | Scan e -> Printf.sprintf "scan e%d" e
  | Filter e -> Printf.sprintf "filter e%d" e
  | Resample a -> Printf.sprintf "resample s%d" a
  | Gather (a, b) -> Printf.sprintf "gather s%d s%d" a b
  | Current e -> Printf.sprintf "current e%d" e

let gen_op =
  let open QCheck2.Gen in
  let i = int_bound 1000 in
  int_bound 17 >>= function
  | 0 -> map2 (fun f a -> Map (f, a)) (int_bound 3) i
  | 1 -> map2 (fun a b -> Map2 (a, b)) i i
  | 2 -> map (fun a -> Pre a) i
  | 3 -> map2 (fun a b -> All (a, b)) i i
  | 4 -> map (fun e -> Hold e) i
  | 5 -> map (fun e -> Fold e) i
  | 6 -> map2 (fun a every -> Machine (a, every)) i bool
  | 7 -> map (fun a -> Changes a) i
  | 8 -> map2 (fun c s -> When (c, s)) i i
  | 9 -> map (fun a -> Rising a) i
  | 10 -> map2 (fun a b -> Merge (a, b)) i i
  | 11 -> map2 (fun a b -> Union (a, b)) i i
  | 12 -> map2 (fun s e -> Tag (s, e)) i i
  | 13 -> map (fun e -> Scan e) i
  | 14 -> map (fun e -> Filter e) i
  | 15 -> map (fun a -> Resample a) i
  | 16 -> map2 (fun a b -> Gather (a, b)) i i
  | _ -> map (fun e -> Current e) i

let gen_prog = QCheck2.Gen.(pair gen_wave (list_size (int_range 1 40) (pair (int_bound 1) gen_op)))

let print_prog (w, ops) =
  Printf.sprintf "rules %s\n%s%s"
    (String.concat "," (Array.to_list (Array.map rule_name w.rules)))
    (vcd w)
    (String.concat "\n" (List.map (fun (d, op) -> Printf.sprintf "d%d: %s" d (op_name op)) ops))

let mask = 0xffff
let fns = [| (fun x -> x + 1); (fun x -> x * 3); (fun x -> x lsr 1); (fun x -> x land 5) |]

type 'c pool = {
  clk : 'c Clock.t;
  mutable sigs : (int, 'c) Sig.t array;
  mutable evs : (int, 'c) Ev.t array;
}

type any_pool = P : 'c pool -> any_pool

let get a i = a.(i mod Array.length a)
let add_sig p s = p.sigs <- Array.append p.sigs [| s |]
let add_ev p e = p.evs <- Array.append p.evs [| e |]
let odd x = x land 1 = 1

let apply p = function
  | Map (f, a) -> add_sig p (Sig.map (fun x -> fns.(f) x land mask) (get p.sigs a))
  | Map2 (a, b) -> add_sig p (Sig.map2 (fun x y -> (x + y) land mask) (get p.sigs a) (get p.sigs b))
  | Pre a -> add_sig p (Sig.pre ~init:7 (get p.sigs a))
  | All (a, b) ->
      add_sig p (Sig.map (List.fold_left ( lxor ) 0) (Sig.all [ get p.sigs a; get p.sigs b ]))
  | Hold e -> add_sig p (Sig.hold ~init:3 (get p.evs e))
  | Fold e -> add_sig p (Sig.fold ~init:0 (fun s x -> (s + x) land mask) (get p.evs e))
  | Machine (a, every_tick) ->
      let out, st =
        Machine.run
          {
            name = "m";
            init = 0;
            step =
              (fun ~tick s i -> ((s + i + tick.index) land mask, if odd i then [ s; i ] else []));
            finish = (fun s -> [ s ]);
            every_tick;
          }
          (get p.sigs a)
      in
      add_sig p st;
      add_ev p (Ev.map (List.fold_left ( + ) 0) out)
  | Changes a -> add_ev p (Sig.changes (get p.sigs a))
  | When (c, s) -> add_ev p (Ev.when_ (Sig.map odd (get p.sigs c)) (get p.sigs s))
  | Rising a -> add_ev p (Ev.map (fun () -> 1) (Ev.rising (Sig.map odd (get p.sigs a))))
  | Merge (a, b) -> add_ev p (Ev.merge ( - ) (get p.evs a) (get p.evs b))
  | Union (a, b) -> add_ev p (Ev.map List.length (Ev.union [ get p.evs a; get p.evs b ]))
  | Tag (s, e) ->
      add_ev p (Ev.map (fun (x, y) -> x * y land mask) (Ev.tag (get p.sigs s) (get p.evs e)))
  | Scan e ->
      add_ev p
        (Ev.scan ~init:0
           (fun s x -> ((s + x) land mask, if odd s then Some s else None))
           (get p.evs e))
  | Filter e -> add_ev p (Ev.filter odd (get p.evs e))
  | Gather (a, b) ->
      let some s = Sig.map (fun x -> if odd x then Some x else None) s in
      add_ev p
        (Ev.map (List.fold_left ( + ) 1) (Ev.gather [ some (get p.sigs a); some (get p.sigs b) ]))
  | Current e ->
      add_sig p (Sig.map (function Some x -> x | None -> -1) (Ev.current (get p.evs e)))
  | Resample _ -> ()

let decode : Value.t -> int = function Int n -> n | Scalar B0 -> 0 | Scalar B1 -> 1 | _ -> -1

let build (w, ops) =
  let tr = Trace.of_string (vcd w) in
  let net = Net.create () in
  let pools =
    Array.init w.nclk (fun k ->
        let clk = Option.get (Trace.track_path tr (Printf.sprintf "top.clk%d" k)) in
        match
          Clock.define net ~name:(Printf.sprintf "clk%d" k)
            { clock = clk.slot; rule = w.rules.(k); enable = None }
        with
        | Clock.Any c ->
            let src i =
              Source.value c
                (Option.get (Trace.track_path tr (Printf.sprintf "top.d%d" i)))
                ~init:0 decode
            in
            let srcs = Array.init w.ndata src in
            P
              {
                clk = c;
                sigs = Array.append srcs [| Sig.cycle c |];
                evs = [| Sig.changes srcs.(0) |];
              })
  in
  List.iter
    (fun (d, op) ->
      let d = d mod w.nclk in
      match (op, pools.(d), pools.((d + 1) mod w.nclk)) with
      | Resample a, P p, P q -> add_sig p (Clock_cross.resample (get q.sigs a) p.clk)
      | op, P p, _ -> apply p op)
    ops;
  (tr, net, pools)

(* A run to the end: [Sched.run], or the same through [Run]. *)
let run_all ~stepped sched sampler =
  if stepped then begin
    let r = Run.start sched sampler in
    while Run.step r do
      ()
    done;
    Run.finish r
  end
  else Sched.run sched sampler

(* Everything every node computes, sample by sample. *)
let observe ?(stepped = false) strategy prog =
  let tr, net, pools = build prog in
  let log = Buffer.create 4096 in
  Array.iteri
    (fun d (P p) ->
      let always = Sig.const p.clk true in
      Ev.subscribe
        (Ev.when_ always (Sig.cycle p.clk))
        (fun n -> Printf.bprintf log "\nd%d c%d:" d n);
      Array.iteri
        (fun i s -> Ev.subscribe (Ev.when_ always s) (fun v -> Printf.bprintf log " s%d=%d" i v))
        p.sigs;
      Array.iteri (fun i e -> Ev.subscribe e (fun v -> Printf.bprintf log " e%d=%d" i v)) p.evs)
    pools;
  let sched = Result.get_ok (Sched.compile ~strategy net) in
  let st = run_all ~stepped sched (Sampler.create tr (Net.domains net)) in
  (Buffer.contents log, st.node_evals, st.ticks)

(* The reference: the program interpreted directly, each operator knowing its own inputs, so a
   dependency the engine fails to record shows up as a difference. *)
module Ref = struct
  type node = {
    mutable v : int;
    mutable ch : bool;  (** changed, or fired for an event, in the current pass *)
    inputs : node list;
    every : bool;  (** evaluated at every sample *)
    step : node -> unit;
  }

  type ctx = { mutable index : int; mutable finishing : bool }

  type dom = {
    mutable nodes : node list;  (** newest first *)
    mutable pres : (node * node) list;  (** newest first *)
    mutable machines : (node * node * int list ref) list;
    mutable sigs : node array;
    mutable evs : node array;
    cycle : node;
  }

  let set n v =
    n.ch <- v <> n.v;
    n.v <- v

  let fire n v =
    n.v <- v;
    n.ch <- true

  let node ?(every = false) d ~init inputs step =
    let n = { v = init; ch = false; inputs; every; step } in
    d.nodes <- n :: d.nodes;
    n

  let ev d inputs step = node d ~init:0 inputs step
  let sg d inputs f = node d ~init:(f ()) inputs (fun n -> set n (f ()))
  let add_sig d n = d.sigs <- Array.append d.sigs [| n |]
  let add_ev d n = d.evs <- Array.append d.evs [| n |]
  let on e f n = if e.ch then f n e.v
  let odd_node d a = sg d [ a ] (fun () -> if odd a.v then 1 else 0)

  let apply ctx d other op =
    let s i = get d.sigs i and e i = get d.evs i in
    match op with
    | Map (f, a) ->
        let a = s a in
        add_sig d (sg d [ a ] (fun () -> fns.(f) a.v land mask))
    | Map2 (a, b) ->
        let a = s a and b = s b in
        add_sig d (sg d [ a; b ] (fun () -> (a.v + b.v) land mask))
    | Pre a ->
        let a = s a in
        let n = node d ~init:7 [] ignore in
        d.pres <- (n, a) :: d.pres;
        add_sig d n
    | All (a, b) ->
        let a = s a and b = s b in
        add_sig d (sg d [ a; b ] (fun () -> a.v lxor b.v))
    | Hold x ->
        let x = e x in
        add_sig d (node d ~init:3 [ x ] (fun n -> on x set n))
    | Fold x ->
        let x = e x in
        add_sig d (node d ~init:0 [ x ] (fun n -> on x (fun n y -> set n ((n.v + y) land mask)) n))
    | Machine (a, every) ->
        let a = s a in
        let pending = ref [] in
        let st =
          node ~every d ~init:0 [ a ] (fun n ->
              if not ctx.finishing then begin
                let o = if odd a.v then [ n.v; a.v ] else [] in
                let s' = (n.v + a.v + ctx.index) land mask in
                pending := o;
                n.ch <- s' <> n.v || o <> [];
                n.v <- s'
              end)
        in
        let out =
          ev d [ st ] (fun n ->
              match !pending with
              | [] -> ()
              | l ->
                  pending := [];
                  fire n (List.fold_left ( + ) 0 l))
        in
        d.machines <- (st, out, pending) :: d.machines;
        add_sig d st;
        add_ev d out
    | Changes a ->
        let a = s a in
        let prev = ref None in
        add_ev d
          (ev d [ a ] (fun n ->
               let p = !prev in
               prev := Some a.v;
               match p with Some p when p <> a.v -> fire n a.v | _ -> ()))
    | When (c, x) ->
        let c = odd_node d (s c) and x = s x in
        add_ev d (node ~every:true d ~init:0 [ c; x ] (fun n -> if c.v = 1 then fire n x.v))
    | Rising a ->
        let b = odd_node d (s a) in
        let prev = ref None in
        add_ev d
          (ev d [ b ] (fun n ->
               let p = !prev in
               prev := Some b.v;
               if p = Some 0 && b.v = 1 then fire n 1))
    | Merge (a, b) ->
        let a = e a and b = e b in
        add_ev d
          (ev d [ a; b ] (fun n ->
               match (a.ch, b.ch) with
               | true, true -> fire n (a.v - b.v)
               | true, false -> fire n a.v
               | false, true -> fire n b.v
               | false, false -> ()))
    | Union (a, b) ->
        let a = e a and b = e b in
        add_ev d
          (ev d [ a; b ] (fun n ->
               match List.length (List.filter (fun x -> x.ch) [ a; b ]) with
               | 0 -> ()
               | k -> fire n k))
    | Tag (x, y) ->
        let x = s x and y = e y in
        add_ev d (ev d [ y; x ] (fun n -> if y.ch then fire n (y.v * x.v land mask)))
    | Scan x ->
        let x = e x in
        let st = ref 0 in
        add_ev d
          (ev d [ x ] (fun n ->
               if x.ch then begin
                 let s = !st in
                 st := (s + x.v) land mask;
                 if odd s then fire n s
               end))
    | Filter x ->
        let x = e x in
        add_ev d (ev d [ x ] (fun n -> if x.ch && odd x.v then fire n x.v))
    | Resample a ->
        let a = get other.sigs a in
        add_sig d (node ~every:true d ~init:a.v [] (fun n -> set n a.v))
    | Current x ->
        let x = e x in
        add_sig d (node ~every:true d ~init:(-1) [ x ] (fun n -> set n (if x.ch then x.v else -1)))
    | Gather (a, b) ->
        (* An option as [min_int] for None; a fresh [Some] is a change even to an equal value. *)
        let some a =
          let f () = if odd a.v then a.v else min_int in
          node d ~init:(f ()) [ a ] (fun n ->
              let v = f () in
              n.ch <- not (v = min_int && n.v = min_int);
              n.v <- v)
        in
        let a = some (s a) and b = some (s b) in
        add_ev d
          (node ~every:true d ~init:0 [ a; b ] (fun n ->
               match List.filter (fun v -> v <> min_int) [ a.v; b.v ] with
               | [] -> ()
               | l -> fire n (List.fold_left ( + ) 1 l)))

  let finish d queued =
    List.iter (fun n -> n.ch <- false) d.nodes;
    d.cycle.ch <- false;
    List.iter
      (fun n -> if List.memq n queued || List.exists (fun i -> i.ch) n.inputs then n.step n)
      (List.rev d.nodes)

  let log_pass log d =
    Array.iteri (fun i n -> if n.ch then Printf.bprintf log " s%d=%d" i n.v) d.sigs;
    Array.iteri (fun i n -> if n.ch then Printf.bprintf log " e%d=%d" i n.v) d.evs

  let run (w, ops) =
    let tr = Trace.of_string (vcd w) in
    let clocks =
      Array.init w.nclk (fun k -> Option.get (Trace.track_path tr (Printf.sprintf "top.clk%d" k)))
    in
    let data =
      Array.init w.ndata (fun i -> Option.get (Trace.track_path tr (Printf.sprintf "top.d%d" i)))
    in
    let sampler =
      Sampler.create tr
        (Array.mapi
           (fun k (c : Trace.signal) -> { Trace.clock = c.slot; rule = w.rules.(k); enable = None })
           clocks)
    in
    let ctx = { index = 0; finishing = false } in
    let doms =
      Array.init w.nclk (fun _ ->
          let cycle = { v = 0; ch = false; inputs = []; every = false; step = ignore } in
          let d = { nodes = []; pres = []; machines = []; sigs = [||]; evs = [||]; cycle } in
          let srcs =
            Array.map
              (fun (sg : Trace.signal) ->
                node ~every:true d ~init:0 [] (fun n ->
                    set n (decode (Sampler.value sampler sg.slot))))
              data
          in
          d.sigs <- Array.append srcs [| cycle |];
          let src0 = srcs.(0) in
          let prev = ref None in
          d.evs <-
            [|
              ev d [ src0 ] (fun n ->
                  let p = !prev in
                  prev := Some src0.v;
                  match p with Some p when p <> src0.v -> fire n src0.v | _ -> ());
            |];
          d)
    in
    List.iter
      (fun (k, op) ->
        let k = k mod w.nclk in
        apply ctx doms.(k) doms.((k + 1) mod w.nclk) op)
      ops;
    let log = Buffer.create 4096 in
    let rec go () =
      match Sampler.next sampler with
      | None -> ()
      | Some tk ->
          let d = doms.(tk.domain) in
          ctx.index <- tk.index;
          List.iter (fun n -> n.ch <- false) d.nodes;
          if tk.index > 0 then List.iter (fun (p, a) -> set p a.v) d.pres;
          d.cycle.v <- tk.index;
          d.cycle.ch <- true;
          List.iter
            (fun n ->
              if tk.index = 0 || n.every || List.exists (fun i -> i.ch) n.inputs then n.step n)
            (List.rev d.nodes);
          Printf.bprintf log "\nd%d c%d:" tk.domain tk.index;
          Array.iteri (fun i n -> Printf.bprintf log " s%d=%d" i n.v) d.sigs;
          Array.iteri (fun i n -> if n.ch then Printf.bprintf log " e%d=%d" i n.v) d.evs;
          go ()
    in
    go ();
    ctx.finishing <- true;
    Array.iter
      (fun d ->
        if d.machines <> [] then begin
          List.iter (fun (st, _, pending) -> pending := [ st.v ]) d.machines;
          finish d (List.map (fun (_, out, _) -> out) d.machines);
          log_pass log d
        end)
      doms;
    Buffer.contents log
end

let evals = ref (0, 0)

let equivalence =
  QCheck2.Test.make ~name:"incremental = sweep = reference" ~count:1000 ~print:print_prog gen_prog
    (fun prog ->
      let a, ea, _ = observe Sched.Incremental prog and b, eb, _ = observe Sched.Sweep prog in
      let r = Ref.run prog in
      evals := (fst !evals + ea, snd !evals + eb);
      if a <> r then QCheck2.Test.fail_reportf "incremental:%s\nreference:%s" a r;
      if a <> b then QCheck2.Test.fail_reportf "incremental:%s\nsweep:%s" a b;
      true)

(* [Vcd.Stateful.stream] is the oracle for the sampled values. *)
let sampled_state =
  QCheck2.Test.make ~name:"sampler = Stateful" ~count:500
    ~print:(fun w -> rule_name w.rules.(0) ^ "\n" ^ vcd w)
    gen_wave
    (fun w ->
      let text = vcd w in
      let tr = Trace.of_string text in
      let signals =
        List.init (w.nclk + w.ndata) (fun i ->
            Option.get
              (Trace.track_path tr
                 (if i < w.nclk then Printf.sprintf "top.clk%d" i
                  else Printf.sprintf "top.d%d" (i - w.nclk))))
      in
      let clk = List.hd signals in
      let rule = w.rules.(0) in
      let s = Sampler.create tr [| { clock = clk.slot; rule; enable = None } |] in
      let states = Hashtbl.create 64 in
      Seq.iter
        (fun (e : Vcd.Stateful.event) ->
          let after = Vcd.ID_map.union (fun _ _ c -> Some c) e.state e.changes in
          Hashtbl.replace states (Timestamp.to_int64 e.time)
            (if rule = Before_rising then e.state else after))
        (Vcd.Stateful.stream (Vcd.parse_string text).simulation);
      let rec go () =
        match Sampler.next s with
        | None -> true
        | Some tk ->
            let st = Hashtbl.find states (Timestamp.to_int64 tk.time) in
            List.iter
              (fun (sg : Trace.signal) ->
                let want = Option.value (Vcd.Stateful.find st sg.id) ~default:(Value.Scalar X) in
                let got = Sampler.value s sg.slot in
                if want <> got then
                  QCheck2.Test.fail_reportf "#%Ld %s: sampled %s, Stateful %s"
                    (Timestamp.to_int64 tk.time) (Reference.to_string sg.path) (Value.to_string got)
                    (Value.to_string want))
              signals;
            go ()
      in
      go ())

let stepped =
  QCheck2.Test.make ~name:"Sched.run = Run.step loop" ~count:1000 ~print:print_prog gen_prog
    (fun prog ->
      let a, _, ta = observe Sched.Incremental prog
      and b, _, tb = observe ~stepped:true Sched.Incremental prog in
      if ta <> tb then QCheck2.Test.fail_reportf "ticks differ";
      if a <> b then QCheck2.Test.fail_reportf "run:%s\nstepped:%s" a b;
      true)

(* Up to three events of a random program, each read through a port in a random interleaving and
   also subscribed to: the two must see the same occurrences. *)
let gen_pull =
  QCheck2.Gen.(triple gen_prog (list_size (int_range 1 3) (int_bound 1000)) (list (int_bound 2)))

let print_pull (prog, evs, _) =
  print_prog prog ^ "\nports " ^ String.concat "," (List.map string_of_int evs)

let pull_push =
  QCheck2.Test.make ~name:"Port pull = push" ~count:1000 ~print:print_pull gen_pull
    (fun (((w, _) as prog), evs, picks) ->
      let tr, net, pools = build prog in
      let chosen =
        List.mapi
          (fun i k ->
            match pools.((i + k) mod w.nclk) with
            | P p ->
                let e = Ev.map (fun x -> (i, x)) (get p.evs k) in
                let pushed = ref [] in
                Ev.subscribe e (fun x -> pushed := x :: !pushed);
                (Port.create e, pushed))
          evs
      in
      let sched = Result.get_ok (Sched.compile net) in
      let run = Run.start sched (Sampler.create tr (Net.domains net)) in
      let n = List.length chosen in
      let seqs = Array.of_list (List.map (fun (p, _) -> Port.seq run p) chosen) in
      let pulled = Array.make n [] and ended = Array.make n false in
      let pull i =
        (not ended.(i))
        &&
        match seqs.(i) () with
        | Seq.Nil ->
            ended.(i) <- true;
            false
        | Cons (x, rest) ->
            pulled.(i) <- x :: pulled.(i);
            seqs.(i) <- rest;
            true
      in
      List.iter (fun k -> ignore (pull (k mod n))) picks;
      for i = 0 to n - 1 do
        while pull i do
          ()
        done
      done;
      List.iteri
        (fun i (port, pushed) ->
          if pulled.(i) <> !pushed then QCheck2.Test.fail_reportf "port %d: pulled <> pushed" i;
          if Port.pending port <> 0 then QCheck2.Test.fail_reportf "port %d: left pending" i)
        chosen;
      true)

(* The sampled ticks and values of the clock and a strict subset of the data, and the stats. *)
let sample_subset ~select w keep =
  let text = vcd w in
  let tr = Trace.of_string ~select text in
  let track n = Option.get (Trace.track_path tr n) in
  let clk = track "top.clk0" in
  let data =
    List.filteri (fun i _ -> List.nth keep i) (List.init w.ndata (Printf.sprintf "top.d%d"))
    |> List.map track
  in
  let signals = clk :: data in
  let s = Sampler.create tr [| { clock = clk.slot; rule = w.rules.(0); enable = None } |] in
  let rec go acc =
    match Sampler.next s with
    | None -> List.rev acc
    | Some tk ->
        go
          (( tk.index,
             Timestamp.to_int64 tk.time,
             List.map (fun (sg : Trace.signal) -> (sg.id, Sampler.value s sg.slot)) signals )
          :: acc)
  in
  let ticks = go [] in
  (ticks, Sampler.stats s, text)

(* Untracked signals keep changing, alone at some timestamps: selection must change what is
   read, never what is sampled. *)
let selected_subset =
  QCheck2.Test.make ~name:"selected sampler = unselected = Stateful, on a subset" ~count:500
    ~print:(fun (w, _) -> rule_name w.rules.(0) ^ "\n" ^ vcd w)
    QCheck2.Gen.(
      gen_wave >>= fun w ->
      list_size (return w.ndata) bool >|= fun keep ->
      (* With one clock, one data signal at least stays untracked. *)
      let strict = w.nclk > 1 || not (List.for_all Fun.id keep) in
      (w, if strict then keep else List.mapi (fun i k -> k && i > 0) keep))
    (fun (w, keep) ->
      let a, sa, text = sample_subset ~select:true w keep in
      let b, sb, _ = sample_subset ~select:false w keep in
      if a <> b then QCheck2.Test.fail_reportf "ticks or values differ with selection";
      if sa.changes_tracked <> sb.changes_tracked then
        QCheck2.Test.fail_reportf "tracked %d vs %d" sa.changes_tracked sb.changes_tracked;
      if sa.changes_seen <> sa.changes_tracked then
        QCheck2.Test.fail_reportf "selected: %d changes seen, %d tracked" sa.changes_seen
          sa.changes_tracked;
      let states = Hashtbl.create 64 in
      Seq.iter
        (fun (e : Vcd.Stateful.event) ->
          let after = Vcd.ID_map.union (fun _ _ c -> Some c) e.state e.changes in
          Hashtbl.replace states e.time (if w.rules.(0) = Before_rising then e.state else after))
        (Vcd.Stateful.stream (Vcd.parse_string text).simulation);
      List.iter
        (fun (_, time, values) ->
          let st = Hashtbl.find states (Timestamp.of_int64 time) in
          List.iter
            (fun (id, got) ->
              let want = Option.value (Vcd.Stateful.find st id) ~default:(Value.Scalar X) in
              if want <> got then
                QCheck2.Test.fail_reportf "#%Ld %s: sampled %s, Stateful %s" time (ID.to_string id)
                  (Value.to_string got) (Value.to_string want))
            values)
        a;
      true)

let%expect_test "selection reads fewer changes, samples the same" =
  let w =
    {
      nclk = 2;
      ndata = 2;
      rules = [| After_rising |];
      steps = [ (1, [ (0, 1); (2, 3) ]); (1, [ (3, 5) ]); (1, [ (0, 0); (1, 1) ]); (1, [ (0, 1) ]) ];
    }
  in
  List.iter
    (fun select ->
      let ticks, st, _ = sample_subset ~select w [ true; false ] in
      Printf.printf "select %b: %d ticks, %d of %d changes tracked\n" select (List.length ticks)
        st.changes_tracked st.changes_seen)
    [ true; false ];
  [%expect
    {|
    select true: 2 ticks, 6 of 6 changes tracked
    select false: 2 ticks, 6 of 10 changes tracked |}]

let%expect_test "properties" =
  let rand = Random.State.make [| 2026 |] in
  QCheck2.Test.check_exn ~rand equivalence;
  QCheck2.Test.check_exn ~rand sampled_state;
  QCheck2.Test.check_exn ~rand stepped;
  QCheck2.Test.check_exn ~rand pull_push;
  QCheck2.Test.check_exn ~rand selected_subset;
  let inc, sweep = !evals in
  Printf.printf "evals: incremental %s sweep\n" (if inc <= sweep then "<=" else ">");
  [%expect {| evals: incremental <= sweep |}]
