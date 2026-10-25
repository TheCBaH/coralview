[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

open Hwfrp
open Vcd_types

let vcd =
  {|$timescale 1ps $end
$scope module top $end
$var wire 1 ! clk $end
$var wire 1 " en $end
$scope module core.x $end
$var wire 8 # a $end
$var wire 8 # a_alias $end
$var wire 4 $ b $end
$var wire 1 % flag $end
$upscope $end
$scope module other $end
$var wire 1 & z $end
$upscope $end
$upscope $end
$enddefinitions $end
#0
$dumpvars
0!
1"
b0 #
b0 $
0%
0&
$end
|}

let replace_all ~sub ~by s =
  let n = String.length sub in
  let b = Buffer.create (String.length s) in
  let i = ref 0 in
  while !i < String.length s do
    if !i + n <= String.length s && String.sub s !i n = sub then begin
      Buffer.add_string b by;
      i := !i + n
    end
    else begin
      Buffer.add_char b s.[!i];
      incr i
    end
  done;
  Buffer.contents b

let at l = Reference.of_list ("top" :: l)
let core = at [ "core.x" ]

(* One graph: the clock with its enable and the named signals of [core.x]. *)
let graph ?(extra = fun _ -> ()) text model signals =
  let tr = Trace.of_string text in
  let net = Net.create () in
  let (Clock.Any c) =
    Bind.clock net tr ~model ~purpose:"clock" ~name:"clk" ~enable:(at [ "en" ]) After_rising (at [ "clk" ])
  in
  let sc = Bind.root net tr c ~model core in
  List.iter (fun s -> ignore (Bind.signal sc s Bind.uint ~purpose:("use " ^ s))) signals;
  extra tr;
  (tr, net)

let plan_of ?extra text model signals =
  let tr, net = graph ?extra text model signals in
  Capture.plan ~origin:model tr [ net ]

let show_errors = function Ok () -> print_endline "ok" | Error l -> List.iter print_endline l

let show_union = function
  | Ok p -> print_string (Capture.to_file p)
  | Error l -> List.iter (Printf.printf "error: %s\n") l

let%expect_test "plan: clock, enable, aliases, direct tracking" =
  let p = plan_of vcd "m1" [ "a"; "b" ] ~extra:(fun tr -> ignore (Trace.find tr [ "top"; "other"; "z" ])) in
  print_string (Capture.to_file p);
  List.iter
    (fun (e : Capture.entry) ->
      Printf.printf "%s: %s\n"
        (Reference.to_string (List.hd e.aliases))
        (String.concat "; " (List.map (fun (m, p) -> m ^ "/" ^ p) e.provenance)))
    (Capture.entries p);
  [%expect {||}]

let%expect_test "plan: events pulled" =
  let tr, net = graph vcd "m1" [ "a" ] in
  ignore (Trace.events tr);
  (match Capture.plan ~origin:"m1" tr [ net ] with
  | _ -> print_endline "planned"
  | exception Invalid_argument m -> print_endline m);
  (match Capture.plan ~origin:"a,b" (Trace.of_string vcd) [] with
  | _ -> print_endline "planned"
  | exception Invalid_argument m -> print_endline m);
  [%expect {||}]

let%expect_test "union: origins merge, conflicts fail" =
  let m1 = plan_of vcd "m1" [ "a"; "b" ] and m2 = plan_of vcd "m2" [ "a"; "flag" ] in
  show_union (Capture.union [ m1; m2 ]);
  print_endline "-- wider a";
  show_union (Capture.union [ m1; plan_of (replace_all ~sub:"wire 8 #" ~by:"wire 16 #" vcd) "m3" [ "a" ] ]);
  print_endline "-- a_alias no longer an alias";
  show_union
    (Capture.union
       [ m1; plan_of (replace_all ~sub:"wire 8 # a_alias" ~by:"wire 8 ' a_alias" vcd) "m3" [ "a"; "a_alias" ] ]);
  print_endline "-- different type";
  show_union (Capture.union [ m1; plan_of (replace_all ~sub:"wire 4 $" ~by:"reg 4 $" vcd) "m3" [ "b" ] ]);
  [%expect {||}]

let%expect_test "check" =
  let m1 = plan_of vcd "m1" [ "a"; "b" ] and m2 = plan_of vcd "m2" [ "a"; "flag" ] in
  let both = Result.get_ok (Capture.union [ m1; m2 ]) in
  let run label plan origins text signals =
    let tr, _ = graph text "run" signals in
    Printf.printf "-- %s\n" label;
    show_errors (Capture.check plan ~origins tr)
  in
  run "same" both [ "m1" ] vcd [ "a"; "b" ];
  run "subset ignores the other origin" both [ "m2" ] vcd [ "a"; "flag" ];
  run "both origins" both [ "m1"; "m2" ] vcd [ "a"; "b"; "flag" ];
  run "binding dropped" both [ "m1" ] vcd [ "a" ];
  run "extra binding" both [ "m1" ] vcd [ "a"; "b"; "flag" ];
  run "narrower width" both [ "m1" ] (replace_all ~sub:"wire 8 #" ~by:"wire 4 #" vcd) [ "a"; "b" ];
  run "changed alias group" both [ "m1" ] (replace_all ~sub:"wire 8 # a_alias" ~by:"wire 8 ' a_alias" vcd)
    [ "a"; "b" ];
  run "other type" both [ "m1" ] (replace_all ~sub:"wire 4 $" ~by:"reg 4 $" vcd) [ "a"; "b" ];
  run "signal absent" both [ "m1" ] (replace_all ~sub:"$var wire 4 $ b $end\n" ~by:"" vcd) [ "a" ];
  run "unknown origin" both [ "m1"; "nope" ] vcd [ "a"; "b" ];
  [%expect {||}]

let%expect_test "plan file" =
  let p = Result.get_ok (Capture.union [ plan_of vcd "m1" [ "a"; "b" ] ]) in
  let text = Capture.to_file p in
  Printf.printf "round trip %b\n" (Capture.of_file text |> Result.get_ok |> Capture.to_file = text);
  List.iter
    (fun (label, t) ->
      Printf.printf "%s: %s\n" label (match Capture.of_file t with Ok _ -> "ok" | Error m -> m))
    [
      ("no header", "signal 1 wire m\ttop\tclk\n");
      ("unknown line", "hwfrp-capture-plan 1\nbogus\n");
      ("alias first", "hwfrp-capture-plan 1\nalias\ttop\tx\n");
      ("bad width", "hwfrp-capture-plan 1\nsignal 0 wire m\ttop\tclk\n");
      ("duplicate", "hwfrp-capture-plan 1\nsignal 1 wire m\ttop\tclk\nsignal 1 wire m\ttop\tclk\n");
      ("no final newline", "hwfrp-capture-plan 1\nsignal 1 wire m\ttop\tclk");
      ("version", "hwfrp-capture-plan 2\n");
    ];
  [%expect {||}]

(* Random traces with aliases, dotted scope names and several widths and types. *)
type var = { scope : int; width : int; ty : int; id : int }

let scopes = [| [ "top" ]; [ "top"; "core.x" ]; [ "top"; "a_b" ]; [ "top"; "x"; "y" ] |]
let types = [| "wire"; "reg"; "integer"; "logic" |]

let gen_vars =
  let open QCheck2.Gen in
  list_size (int_range 1 12)
    (map (fun (scope, width, ty, id) -> { scope; width; ty; id })
       (quad (int_bound 3) (int_range 1 70) (int_bound 3) (int_bound 5)))

let vcd_of vars =
  let b = Buffer.create 256 in
  Buffer.add_string b "$timescale 1ps $end\n";
  Array.iteri
    (fun si path ->
      let mine = List.filter (fun (_, v) -> v.scope = si) (List.mapi (fun i v -> (i, v)) vars) in
      if mine <> [] then begin
        List.iter (Printf.bprintf b "$scope module %s $end\n") path;
        List.iter
          (fun (i, v) ->
            Printf.bprintf b "$var %s %d %c v%d $end\n" types.(v.ty) v.width (Char.chr (33 + v.id)) i)
          mine;
        List.iter (fun _ -> Buffer.add_string b "$upscope $end\n") path
      end)
    scopes;
  Buffer.add_string b "$enddefinitions $end\n";
  Buffer.contents b

let file_round_trip =
  QCheck2.Test.make ~name:"plan file round trip" ~count:300 gen_vars (fun vars ->
      let text = vcd_of vars in
      let tr = Trace.of_string text in
      Vcd.Resolver.fold
        (fun e () -> ignore (Trace.track tr e))
        (Trace.resolver tr) ();
      let p = Capture.plan ~origin:"o" tr [] in
      let file = Capture.to_file p in
      match Capture.of_file file with
      | Error m -> QCheck2.Test.fail_reportf "of_file: %s\n%s" m file
      | Ok q ->
          if Capture.to_file q <> file then QCheck2.Test.fail_reportf "differs:\n%s\n%s" file (Capture.to_file q);
          if List.length (Capture.entries q) <> List.length (Capture.entries p) then
            QCheck2.Test.fail_reportf "entries";
          (* the plan describes its own trace *)
          let tr2 = Trace.of_string text in
          Vcd.Resolver.fold (fun e () -> ignore (Trace.track tr2 e)) (Trace.resolver tr2) ();
          (match Capture.check q ~origins:[ "o" ] tr2 with
          | Ok () -> ()
          | Error l -> QCheck2.Test.fail_reportf "check: %s" (String.concat "; " l));
          true)

let%expect_test "properties" =
  let rand = Random.State.make [| 7 |] in
  QCheck2.Test.check_exn ~rand file_round_trip;
  [%expect {||}]
