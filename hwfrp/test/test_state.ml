open Hwfrp

(* State's stores against a naive rebuild of the whole state at every sample. *)

type k = { k : 'c. Trace.t -> Net.t -> 'c Clock.t -> 'c Bind.scope -> bool }

let setup (w : Test_props.wave) { k } =
  let tr = Trace.of_string (Test_props.vcd w) in
  let net = Net.create () in
  let at s = Vcd_types.Reference.of_list [ "top"; s ] in
  let (Clock.Any c) = Bind.clock net tr ~model:"t" ~name:"clk" w.rules.(0) (at "clk0") in
  k tr net c (Bind.root net tr c ~model:"t" (Vcd_types.Reference.of_list [ "top" ]))

let run tr net =
  let sched = Result.get_ok (Sched.compile net) in
  ignore (Sched.run sched (Sampler.create tr (Net.domains net)))

let show f l = String.concat "," (List.map (fun (k, v) -> Printf.sprintf "%d=%s" k (f v)) l)

(* The naive store: every entry read at every sample, changes by diffing consecutive snapshots. *)
let naive c (entries : (int * ('v, 'c) Sig.t) list) =
  let all = Sig.all (List.map snd entries) in
  let prev = ref None in
  Ev.map
    (fun vs ->
      let snap = List.combine (List.map fst entries) vs in
      let changes =
        match !prev with
        | None -> snap
        | Some p -> List.filter (fun (k, v) -> List.assoc k p <> v) snap
      in
      prev := Some snap;
      (List.sort compare snap, changes))
    (Ev.when_ (Sig.const c true) all)

let compare_logs name f a b =
  if a <> b then QCheck2.Test.fail_reportf "%s\nstore:%s\nnaive:%s" name a b;
  ignore f;
  true

let log_store c (s : _ State.store) f =
  let b = Buffer.create 256 in
  Ev.subscribe
    (Ev.when_ (Sig.const c true) s.state)
    (fun st -> Printf.bprintf b "\n[%s]" (show f (State.bindings st)));
  Ev.subscribe s.changes (fun ch -> Printf.bprintf b " +%s" (show f ch));
  b

let log_naive ev f =
  let b = Buffer.create 256 in
  Ev.subscribe ev (fun (snap, ch) ->
      Printf.bprintf b "\n[%s]" (show f snap);
      if ch <> [] then Printf.bprintf b " +%s" (show f ch));
  b

let names (w : Test_props.wave) = List.init w.ndata (fun i -> (i * 3, Printf.sprintf "d%d" i))

let mirror =
  QCheck2.Test.make ~name:"mirror = naive" ~count:300
    ~print:(fun w -> Test_props.vcd w)
    Test_props.gen_wave
    (fun w ->
      setup w
      @@ {
           k =
             (fun tr net c sc ->
               let s = State.mirror sc (names w) Bind.logic in
               let n =
                 naive c (List.map (fun (k, name) -> (k, Bind.signal sc name Bind.logic)) (names w))
               in
               let a = log_store c s Logic.to_string and b = log_naive n Logic.to_string in
               run tr net;
               compare_logs "mirror" () (Buffer.contents a) (Buffer.contents b));
         })

let packed =
  QCheck2.Test.make ~name:"mirror_packed = naive" ~count:300
    ~print:(fun w -> Test_props.vcd w)
    Test_props.gen_wave
    (fun w ->
      setup w
      @@ {
           k =
             (fun tr net c sc ->
               let s = State.mirror_packed sc "d0" ~entries:2 ~width:2 Bits.to_int_exn in
               let whole = Bind.signal sc "d0" { Bind.bits with dwidth = Exact 4 } in
               let n =
                 naive c
                   (List.init 2 (fun i ->
                        (i, Sig.map (fun b -> Bits.field_int b ~lo:(2 * i) ~width:2) whole)))
               in
               let a = log_store c s string_of_int and b = log_naive n string_of_int in
               run tr net;
               compare_logs "packed" () (Buffer.contents a) (Buffer.contents b));
         })

let writes c sc (w : Test_props.wave) =
  let ds = List.map (fun (_, name) -> Bind.signal sc name Bind.uint) (names w) in
  Ev.filter
    (fun l -> l <> [])
    (Ev.when_ (Sig.const c true)
       (Sig.map
          (List.filter_map (fun v -> if v land 1 = 1 then Some (v land 3, v) else None))
          (Sig.all ds)))

let merge old w = (Option.value old ~default:0 + w) land 0xff

let replay =
  QCheck2.Test.make ~name:"replay = naive" ~count:300
    ~print:(fun w -> Test_props.vcd w)
    Test_props.gen_wave
    (fun w ->
      setup w
      @@ {
           k =
             (fun tr net c sc ->
               let ws = writes c sc w in
               let s = State.replay ~init:(State.of_list [ (1, 7) ]) merge ws in
               let a = Buffer.create 256 and b = Buffer.create 256 in
               Ev.subscribe s.changes (fun ch -> Printf.bprintf a " +%s" (show string_of_int ch));
               Ev.subscribe (Ev.tag s.state ws) (fun (_, st) ->
                   Printf.bprintf a "\n[%s]" (show string_of_int (State.bindings st)));
               let st = ref [ (1, 7) ] in
               Ev.subscribe ws (fun l ->
                   let prev = !st in
                   List.iter
                     (fun (k, v) ->
                       st := (k, merge (List.assoc_opt k !st) v) :: List.remove_assoc k !st)
                     l;
                   let snap = List.sort compare !st in
                   let ch = List.filter (fun (k, v) -> List.assoc_opt k prev <> Some v) snap in
                   if ch <> [] then Printf.bprintf b " +%s" (show string_of_int ch);
                   Printf.bprintf b "\n[%s]" (show string_of_int snap));
               run tr net;
               compare_logs "replay" () (Buffer.contents a) (Buffer.contents b));
         })

let fields =
  QCheck2.Test.make ~name:"mirror_fields = naive" ~count:300
    ~print:(fun w -> Test_props.vcd w)
    Test_props.gen_wave
    (fun w ->
      setup w
      @@ {
           k =
             (fun tr net c sc ->
               let last = Printf.sprintf "d%d" (w.ndata - 1) in
               let w4 = Bind.Exact 4 in
               let s =
                 State.mirror_fields sc
                   [ (0, [ ("d0", w4) ]); (5, [ ("d0", w4); (last, w4) ]) ]
                   (fun l -> String.concat "" (List.map Logic.to_string l))
               in
               let sg name = Bind.signal sc name Bind.logic in
               let n =
                 naive c
                   [
                     (0, Sig.map Logic.to_string (sg "d0"));
                     ( 5,
                       Sig.map2
                         (fun a b -> Logic.to_string a ^ Logic.to_string b)
                         (sg "d0") (sg last) );
                   ]
               in
               let a = log_store c s Fun.id and b = log_naive n Fun.id in
               run tr net;
               compare_logs "fields" () (Buffer.contents a) (Buffer.contents b));
         })

let previous =
  QCheck2.Test.make ~name:"previous = naive one sample late" ~count:300
    ~print:(fun w -> Test_props.vcd w)
    Test_props.gen_wave
    (fun w ->
      setup w
      @@ {
           k =
             (fun tr net c sc ->
               let s = State.previous c (State.mirror sc (names w) Bind.logic) in
               let n =
                 naive c (List.map (fun (k, name) -> (k, Bind.signal sc name Bind.logic)) (names w))
               in
               let a = log_store c s Logic.to_string in
               let b = Buffer.create 256 and last = ref ([], []) in
               Ev.subscribe n (fun (snap, ch) ->
                   let psnap, pch = !last in
                   Printf.bprintf b "\n[%s]" (show Logic.to_string psnap);
                   if pch <> [] then Printf.bprintf b " +%s" (show Logic.to_string pch);
                   last := (snap, ch));
               run tr net;
               compare_logs "previous" () (Buffer.contents a) (Buffer.contents b));
         })

(* Diagnostics when a key starts failing, against checking every key at every sample. *)
let relate =
  QCheck2.Test.make ~name:"relate = naive" ~count:300
    ~print:(fun w -> Test_props.vcd w)
    Test_props.gen_wave
    (fun w ->
      setup w
      @@ {
           k =
             (fun tr net c sc ->
               let s = State.mirror sc (names w) Bind.uint in
               let keys = List.map fst (names w) in
               let check k =
                 match State.get (Sig.peek s.state) k with
                 | Some v when v land 1 = 1 -> Some (Printf.sprintf "odd %d" v)
                 | _ -> None
               in
               State.relate c net ~source:"t" ~code:"odd" ~keys [ State.keys s ] check;
               let naive = Buffer.create 256 and failing = Hashtbl.create 8 in
               Ev.subscribe
                 (Ev.tag (Sig.cycle c) (Ev.when_ (Sig.const c true) s.state))
                 (fun (_, cycle) ->
                   List.iter
                     (fun k ->
                       match check k with
                       | None -> Hashtbl.remove failing k
                       | Some m ->
                           if not (Hashtbl.mem failing k) then begin
                             Hashtbl.replace failing k ();
                             Printf.bprintf naive "\n%d key %d: %s" cycle k m
                           end)
                     keys);
               run tr net;
               let got = Buffer.create 256 in
               Seq.iter
                 (fun (d : Diag.t) ->
                   if d.code = "odd" then
                     Printf.bprintf got "\n%d %s" (Option.value d.cycle ~default:(-1)) d.message)
                 (Diag.stream net);
               compare_logs "relate" () (Buffer.contents got) (Buffer.contents naive));
         })

let%expect_test "state properties" =
  let rand = Random.State.make [| 2027 |] in
  List.iter
    (fun t -> QCheck2.Test.check_exn ~rand t)
    [ mirror; fields; packed; previous; replay; relate ];
  print_endline "ok";
  [%expect {| ok |}]
