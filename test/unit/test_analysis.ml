open Hwfrp
open Coralview

(* One dispatch lane; it fires at cycles 1, 2 and 4 with PCs 0x10, 0x14 and 0x18. *)
let vcd =
  let b = Buffer.create 1024 in
  Buffer.add_string b
    "$timescale 1ps $end\n\
     $scope module TOP $end\n\
     $scope module core $end\n\
     $var wire 1 c io_aclk $end\n\
     $var wire 1 f io_debug_dispatch_0_instFire $end\n\
     $var wire 32 a io_debug_dispatch_0_instAddr $end\n\
     $var wire 32 i io_debug_dispatch_0_instInst $end\n\
     $upscope $end\n\
     $upscope $end\n\
     $enddefinitions $end\n";
  let fire = [ (1, 0x10); (2, 0x14); (4, 0x18) ] in
  for k = 0 to 5 do
    let f, pc = match List.assoc_opt k fire with Some pc -> (1, pc) | None -> (0, 0) in
    Printf.bprintf b "#%d\n1c\n#%d\n0c\n%df\nb%s a\nb10011 i\n" (2 * k)
      ((2 * k) + 1)
      f
      (String.init 32 (fun j -> if pc land (1 lsl (31 - j)) <> 0 then '1' else '0'))
  done;
  Buffer.contents b

let platform =
  match
    Platform.of_string
      {|{ "schema_version": "1.0", "name": "toy",
          "configurations": [ { "name": "toy-core", "top_level": "Core", "trace_root": ["TOP", "core"] } ],
          "clock": "io_aclk", "sample": "after_falling",
          "blocks": { "dispatch_debug": { "scope": [], "lanes": 1 } } }|}
  with
  | Ok f -> List.hd (Platform.configurations f)
  | Error e -> failwith e

let builds = ref 0

(* Dispatches, and their count. *)
module Toy = struct
  let name = "toy"
  let doc = "dispatches"
  let needs = [ "dispatch_debug" ]

  module Config = struct
    type t = unit

    let default = ()
  end

  module Event = struct
    type t = { cycle : int; pc : int }

    let dispatch =
      Codec.case "toy.dispatch" Fun.id
        (Jsont.Object.map (fun cycle pc -> { cycle; pc })
        |> Jsont.Object.mem "cycle" Jsont.int ~enc:(fun e -> e.cycle)
        |> Jsont.Object.mem "pc" Jsont.int ~enc:(fun e -> e.pc)
        |> Jsont.Object.finish)

    let jsont =
      Codec.cases "toy.event"
        (fun e -> Jsont.Object.Case.value dispatch e)
        [ Jsont.Object.Case.make dispatch ]

    let cycle e = e.cycle
    let pc e = Some e.pc
  end

  module Summary = struct
    type t = { dispatches : int }

    let jsont =
      Codec.record "toy.summary" (fun dispatches -> { dispatches })
      |> Jsont.Object.mem "dispatches" Jsont.int ~enc:(fun s -> s.dispatches)
      |> Jsont.Object.finish
  end

  type 'c Core.dep += Built of (Event.t list, 'c) Ev.t * (Sched.run_stats -> Summary.t)

  let build () (c : _ Core.t) =
    Analysis.shared c name
      ~inj:(fun (e, s) -> Built (e, s))
      ~prj:(function Built (e, s) -> Some (e, s) | _ -> None)
      (fun () ->
        incr builds;
        let cycle = Sig.cycle c.clk in
        let ev =
          Ev.map
            (fun (l, cyc) ->
              List.map (fun (d : Core.dispatched) -> { Event.cycle = cyc; pc = d.d_pc }) l)
            (Ev.tag cycle (Ev.gather (Core.dispatch c)))
        in
        let n = Sig.fold ~init:0 (fun n l -> n + List.length l) ev in
        (ev, fun _ -> { Summary.dispatches = Sig.peek n }))
end

(* Built on Toy through the registry: the dispatches at even cycles. *)
module Even = struct
  include Toy

  let name = "even"

  let build () c =
    let ev, s = Toy.build () c in
    (Ev.map (List.filter (fun (e : Event.t) -> e.cycle mod 2 = 0)) ev, s)
end

let toy : (Toy.Event.t, Toy.Summary.t) Analysis.t = (module Toy)
let show (e : Toy.Event.t) = Printf.sprintf "%d:%x" e.cycle e.pc

let%expect_test "pull = subscribe; a dependency is shared" =
  let p = Analysis.pull (module Toy) () platform (Trace.of_string vcd) in
  let pulled = List.of_seq p.events in
  Printf.printf "pulled %s; summary %d\n"
    (String.concat " " (List.map show pulled))
    (p.summary ()).dispatches;
  let (Core.Any c) = Core.bind platform (Trace.of_string vcd) ~model:"toy" in
  builds := 0;
  let pushed = ref [] and even = ref [] in
  let s = Analysis.subscribe (module Toy) () c (fun e -> pushed := e :: !pushed) in
  let (_ : Sched.run_stats -> Toy.Summary.t) =
    Analysis.subscribe (module Even) () c (fun e -> even := e :: !even)
  in
  let st = Core.run c in
  Printf.printf "pushed equal %b; even %s; builds %d; summary %d\n"
    (List.rev !pushed = pulled)
    (String.concat " " (List.rev_map show !even))
    !builds (s st).dispatches;
  [%expect
    {|
    pulled 1:10 2:14 4:18; summary 3
    pushed equal true; even 2:14 4:18; builds 1; summary 3 |}]

let%expect_test "JSONL" =
  let p = Analysis.pull (module Toy) () platform (Trace.of_string vcd) in
  let file = Filename.temp_file "toy" ".jsonl" in
  Out_channel.with_open_text file (fun oc ->
      Jsonl.write oc
        (Jsonl.header ~model:"toy" ~platform:"toy-core" ~trace:"toy.vcd")
        toy p.events ~diags:p.diags p.summary);
  print_string (In_channel.with_open_text file In_channel.input_all);
  In_channel.with_open_text file (fun ic ->
      Seq.iter
        (function
          | Ok (Jsonl.Header h) -> Printf.printf "header %s\n" h.model
          | Ok (Event e) -> Printf.printf "event %s\n" (show e)
          | Ok (Diag d) -> Printf.printf "diag %s\n" d.code
          | Ok (Summary s) -> Printf.printf "summary %d\n" s.Toy.Summary.dispatches
          | Error e -> Printf.printf "error %s\n" e)
        (Jsonl.read toy ic));
  Sys.remove file;
  [%expect
    {|
    {"type":"coralview","schema_version":1,"model":"toy","platform":"toy-core","trace":"toy.vcd"}
    {"type":"toy.dispatch","cycle":1,"pc":16}
    {"type":"toy.dispatch","cycle":2,"pc":20}
    {"type":"toy.dispatch","cycle":4,"pc":24}
    {"type":"toy.summary","dispatches":3}
    header toy
    event 1:10
    event 2:14
    event 4:18
    summary 3 |}]
