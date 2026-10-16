open Hwfrp
open Vcd_types

let vcd =
  {|$timescale 1ps $end
$scope module top $end
$scope module core $end
$var wire 1 ! clk $end
$var wire 1 " io_a_valid $end
$var wire 8 # io_a_bits_x $end
$var wire 4 $ io_a_bits_y $end
$var wire 1 % io_lane_0_v $end
$var wire 1 & io_lane_1_v $end
$var wire 1 ' io_lane_3_v $end
$var real 64 ( temp $end
$upscope $end
$scope module other $end
$var wire 1 ) x $end
$upscope $end
$upscope $end
$enddefinitions $end
#0
$dumpvars
0!
0"
bx #
b0 $
0%
1&
0'
r1.5 (
0)
$end
#1
1!
#2
0!
1"
b101 #
b1100 $
#3
1!
#4
0!
0"
b1x1 #
#5
1!
#6
0!
|}

let core = Reference.of_list [ "top"; "core" ]
let at name = Reference.of_list [ "top"; "core"; name ]

type k = { k : 'c. Trace.t -> Net.t -> 'c Bind.scope -> unit }

let setup { k } =
  let tr = Trace.of_string vcd in
  let net = Net.create () in
  match Bind.clock net tr ~model:"m" ~name:"clk" ~purpose:"clock" After_falling (at "clk") with
  | None -> assert false
  | Some (Clock.Any c) -> k tr net (Bind.root net tr c ~model:"m" core)

let%expect_test "discovery" =
  setup
    {
      k =
        (fun tr _ sc ->
          List.iter
            (fun p ->
              Printf.printf "%s: %s\n" p
                (String.concat " "
                   (List.map Reference.to_string (Bind.find_roots tr (Filter_parser.parse_exn p)))))
            [ "**"; "**.core"; "top.*" ];
          Printf.printf "lanes %s\n"
            (String.concat "," (List.map string_of_int (Bundle.lanes sc "io_lane_%d_v")));
          let b = Bundle.discover sc "io_a_bits" in
          List.iter (fun (f, w) -> Printf.printf "field %s %d\n" f w) (Bundle.fields b));
    };
  [%expect
    {|
    **: top top.core top.other
    **.core: top.core
    top.*: top.core top.other
    lanes 0,1,3
    field x 8
    field y 4 |}]

let%expect_test "check" =
  setup
    {
      k =
        (fun tr net sc ->
          ignore (Bind.signal sc "io_a_bits_x" Bind.uint ~purpose:"x");
          ignore (Bind.signal sc "io_a_bits_y" Bind.bool ~purpose:"too wide");
          ignore (Bind.signal sc "temp" Bind.uint);
          ignore (Bind.signal sc "nope" Bind.uint ~purpose:"absent");
          ignore (Bind.optional sc "maybe" Bind.uint ~purpose:"absent, optional");
          ignore (Bind.signal (Bind.sub sc "deeper") "z" Bind.bool);
          List.iter (Format.printf "%a@." Bind.pp_report) (Bind.check tr (Bind.requirements net));
          match Sched.compile net with
          | Ok _ -> print_endline "compiled"
          | Error es ->
              List.iter
                (function
                  | Sched.Check_failed s -> print_endline s | Unbound_source s -> print_endline s)
                es);
    };
  [%expect
    {|
    m at top.core
      bound   clk 1: clock
      bound   io_a_bits_x 8: x
      width   io_a_bits_y 4, expected 1: too wide
      type    temp real
      missing nope: absent
      missing maybe (optional): absent, optional
      missing deeper.z
      width   io_a_bits_y 4, expected 1: too wide
      type    temp real
      missing nope: absent
      missing deeper.z |}]

let%expect_test "values" =
  let tr = Trace.of_string vcd in
  let net = Net.create () in
  match Bind.clock net tr ~model:"m" ~name:"clk" After_falling (at "clk") with
  | None -> assert false
  | Some (Clock.Any c) ->
      let sc = Bind.root net tr c ~model:"m" core in
      let a = Bundle.valid sc "io_a" in
      let x = Bundle.get a.v_bits "x" Bind.uint in
      let lo = Bind.signal sc "io_a_bits_x" (Bind.field ~lo:0 ~width:2) in
      let y = Bundle.get a.v_bits "y" Bind.bits in
      let maybe = Bind.optional sc "maybe" Bind.uint in
      let row =
        let open Sig in
        let+ cycle = cycle c
        and+ v = a.v_valid
        and+ x = x
        and+ lo = lo
        and+ y = y
        and+ maybe = maybe in
        Printf.sprintf "cycle %d valid=%b x=%d lo=%d y=%s maybe=%s" cycle v x lo (Bits.to_hex y)
          (match maybe with Some m -> string_of_int m | None -> "none")
      in
      Ev.subscribe (Ev.when_ (Sig.const c true) row) print_endline;
      let sched = Result.get_ok (Sched.compile net) in
      ignore (Sched.run sched (Sampler.create tr (Net.domains net)));
      Seq.iter (Format.printf "%a@." Diag.pp) (Diag.stream net);
      [%expect
        {|
        cycle 0 valid=true x=5 lo=1 y=c maybe=none
        cycle 1 valid=false x=0 lo=0 y=c maybe=none
        cycle 2 valid=false x=0 lo=0 y=c maybe=none
        warning[bind.unknown-bits] m cycle 1 time 4: uint of 000001x1
        top.core.io_a_bits_x
        warning[bind.unknown-bits] m cycle 1 time 4: field[0+:2] of 000001x1
        top.core.io_a_bits_x |}]
