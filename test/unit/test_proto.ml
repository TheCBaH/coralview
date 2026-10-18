open Hwfrp
open Coralview

(* A VCD under [top] with a clock and the declared wires; [cycles] gives each cycle's nonzero values,
   set before its rising edge. *)
let vcd decls cycles n =
  let b = Buffer.create 4096 in
  let id i = Printf.sprintf "s%d" i in
  Buffer.add_string b "$timescale 1ps $end\n$scope module top $end\n$var wire 1 c clk $end\n";
  List.iteri (fun i (name, w) -> Printf.bprintf b "$var wire %d %s %s $end\n" w (id i) name) decls;
  Buffer.add_string b "$upscope $end\n$enddefinitions $end\n";
  let bin v =
    if v = 0 then "0"
    else
      String.concat ""
        (List.rev (List.init 63 (fun k -> if (v lsr k) land 1 = 1 then "1" else "0")))
  in
  let prev = Hashtbl.create 64 in
  for k = 0 to n - 1 do
    Printf.bprintf b "#%d\n0c\n" (2 * k);
    let now = Option.value (List.assoc_opt k cycles) ~default:[] in
    List.iteri
      (fun i (name, _) ->
        let v = Option.value (List.assoc_opt name now) ~default:0 in
        if Hashtbl.find_opt prev name <> Some v then begin
          Hashtbl.replace prev name v;
          Printf.bprintf b "b%s %s\n" (bin v) (id i)
        end)
      decls;
    Printf.bprintf b "#%d\n1c\n" ((2 * k) + 1)
  done;
  Printf.bprintf b "#%d\n0c\n" (2 * n);
  Buffer.contents b

type build = { build : 'c. 'c Clock.t -> 'c Bind.scope -> unit }

let setup text { build } =
  let tr = Trace.of_string text in
  let net = Net.create () in
  let at = Vcd_types.Reference.of_list in
  let (Clock.Any clk) =
    Bind.clock net tr ~model:"t" ~name:"clk" Before_rising (at [ "top"; "clk" ])
  in
  build clk (Bind.root net tr clk ~model:"t" (at [ "top" ]));
  ignore (Sched.run (Result.get_ok (Sched.compile net)) (Sampler.create tr (Net.domains net)))

let addr_wires ch =
  [
    (ch ^ "_valid", 1);
    (ch ^ "_ready", 1);
    (ch ^ "_bits_addr", 32);
    (ch ^ "_bits_id", 4);
    (ch ^ "_bits_len", 8);
    (ch ^ "_bits_size", 3);
    (ch ^ "_bits_burst", 2);
  ]

let axi_wires =
  List.map
    (fun (n, w) -> ("m_" ^ n, w))
    (addr_wires "read_addr" @ addr_wires "write_addr"
    @ [
        ("read_data_valid", 1);
        ("read_data_ready", 1);
        ("read_data_bits_id", 4);
        ("read_data_bits_resp", 2);
        ("read_data_bits_last", 1);
        ("write_data_valid", 1);
        ("write_data_ready", 1);
        ("write_data_bits_strb", 4);
        ("write_data_bits_last", 1);
        ("write_resp_valid", 1);
        ("write_resp_ready", 1);
        ("write_resp_bits_id", 4);
        ("write_resp_bits_resp", 2);
      ])

let ar ?(ready = 1) id addr len =
  [
    ("m_read_addr_valid", 1);
    ("m_read_addr_ready", ready);
    ("m_read_addr_bits_id", id);
    ("m_read_addr_bits_addr", addr);
    ("m_read_addr_bits_len", len);
    ("m_read_addr_bits_size", 2);
    ("m_read_addr_bits_burst", 1);
  ]

let aw id addr len =
  [
    ("m_write_addr_valid", 1);
    ("m_write_addr_ready", 1);
    ("m_write_addr_bits_id", id);
    ("m_write_addr_bits_addr", addr);
    ("m_write_addr_bits_len", len);
    ("m_write_addr_bits_size", 2);
    ("m_write_addr_bits_burst", 1);
  ]

let r id resp last =
  [
    ("m_read_data_valid", 1);
    ("m_read_data_ready", 1);
    ("m_read_data_bits_id", id);
    ("m_read_data_bits_resp", resp);
    ("m_read_data_bits_last", last);
  ]

let w strb last =
  [
    ("m_write_data_valid", 1);
    ("m_write_data_ready", 1);
    ("m_write_data_bits_strb", strb);
    ("m_write_data_bits_last", last);
  ]

let b id resp =
  [
    ("m_write_resp_valid", 1);
    ("m_write_resp_ready", 1);
    ("m_write_resp_bits_id", id);
    ("m_write_resp_bits_resp", resp);
  ]

let pp_txn (t : Transaction.t) (x : Axi4.extra) =
  let o = function Some c -> string_of_int c | None -> "-" in
  Printf.sprintf
    "#%d %s id %d %x %dB %d beats of %d, req %d acc %d data %s done %s status %d out %d" x.serial
    (if t.write then "W" else "R")
    t.id t.address t.bytes t.beats x.beat_bytes t.requested t.accepted (o t.first_data)
    (o t.completed) t.status t.outstanding

let%expect_test "Axi4" =
  let cycles =
    [
      (0, ar 0 0x100 0);
      (1, ar ~ready:0 1 0x200 1);
      (2, ar 1 0x200 1 @ w 0xf 0);
      (3, r 1 0 0 @ w 0x3 1);
      (4, r 1 2 1 @ aw 0 0x300 1);
      (5, r 0 0 1 @ b 3 0);
      (6, b 0 3);
      (7, aw 2 0x400 0);
      (8, r 5 0 1);
      (9, w 0x1 1);
      (10, w 0x1 1);
    ]
  in
  setup (vcd axi_wires cycles 12)
    {
      build =
        (fun _ sc ->
          let events, counts = Axi4.track (Axi4.bind sc (Axi4.chisel "m_") ~data_bytes:4) in
          Ev.subscribe events
            (List.iter (function
              | Axi4.Accepted (t, x) -> print_endline ("accepted " ^ pp_txn t x)
              | Done (t, x) -> print_endline ("done     " ^ pp_txn t x)
              | Open_at_end (t, x) -> print_endline ("open     " ^ pp_txn t x)
              | Unmatched { cycle; write; id; what } ->
                  Printf.printf "unmatched cycle %d %s id %d: %s\n" cycle
                    (if write then "W" else "R")
                    id what));
          Ev.subscribe
            (Ev.when_ (Sig.const (Bind.clock_of sc) true) (Sig.cycle (Bind.clock_of sc)))
            (fun c ->
              if c = 11 then
                let { Axi4.max_reads; max_writes } = Sig.peek counts in
                Printf.printf "max reads %d writes %d\n" max_reads max_writes));
    };
  [%expect
    {|
    accepted #0 R id 0 100 0B 1 beats of 4, req 0 acc 0 data - done - status 0 out 1
    accepted #1 R id 1 200 0B 2 beats of 4, req 1 acc 2 data - done - status 0 out 2
    done     #1 R id 1 200 8B 2 beats of 4, req 1 acc 2 data 3 done 4 status 2 out 2
    accepted #2 W id 0 300 6B 2 beats of 4, req 4 acc 4 data 2 done - status 0 out 2
    done     #0 R id 0 100 4B 1 beats of 4, req 0 acc 0 data 5 done 5 status 0 out 1
    unmatched cycle 5 W id 3: write response with no outstanding write
    done     #2 W id 0 300 6B 2 beats of 4, req 4 acc 4 data 2 done 6 status 3 out 2
    accepted #3 W id 2 400 0B 1 beats of 4, req 7 acc 7 data - done - status 0 out 1
    unmatched cycle 8 R id 5: read data with no outstanding read
    max reads 2 writes 1
    unmatched cycle 10 W id -1: write data with no write address
    open     #3 W id 2 400 1B 1 beats of 4, req 7 acc 7 data 9 done - status 0 out 1 |}]

let tl_wires =
  List.map
    (fun (n, w) -> ("t_" ^ n, w))
    [
      ("a_valid", 1);
      ("a_ready", 1);
      ("a_bits_opcode", 3);
      ("a_bits_size", 2);
      ("a_bits_source", 4);
      ("a_bits_address", 32);
      ("a_bits_mask", 4);
      ("a_bits_data", 32);
      ("d_valid", 1);
      ("d_ready", 1);
      ("d_bits_source", 4);
      ("d_bits_data", 32);
      ("d_bits_error", 1);
    ]

let a ?(ready = 1) op src addr data =
  [
    ("t_a_valid", 1);
    ("t_a_ready", ready);
    ("t_a_bits_opcode", op);
    ("t_a_bits_size", 2);
    ("t_a_bits_source", src);
    ("t_a_bits_address", addr);
    ("t_a_bits_mask", 0xf);
    ("t_a_bits_data", data);
  ]

let d ?(ready = 1) ?(error = 0) src data =
  [
    ("t_d_valid", 1);
    ("t_d_ready", ready);
    ("t_d_bits_source", src);
    ("t_d_bits_data", data);
    ("t_d_bits_error", error);
  ]

let%expect_test "Tlul" =
  let cycles =
    [
      (0, a ~ready:0 4 1 0x10 0);
      (1, a 4 1 0x10 0);
      (2, a 0 2 0x20 0xabcd);
      (3, d 1 0x1234 @ d 2 0);
      (4, d 2 0x5678 @ a 4 1 0x14 0);
      (5, d ~error:1 1 0);
      (6, d ~ready:0 3 0);
    ]
  in
  let pp (t : Tlul.transaction) =
    Printf.sprintf "%s src %d %x req %d acc %d resp %s data %x%s"
      (if Tlul.is_get t.request then "Get" else "Put")
      t.request.source t.request.address t.requested t.accepted
      (match t.responded with Some c -> string_of_int c | None -> "-")
      (Tlul.value ~data_bytes:4 t.request t.response)
      (if t.error then " error" else "")
  in
  List.iter
    (fun d_ready ->
      Printf.printf "d_ready %b\n" d_ready;
      setup (vcd tl_wires cycles 8)
        {
          build =
            (fun clk sc ->
              let p = Tlul.bind sc { prefix = "t_"; d_ready } ~data_bytes:4 in
              let st = ref Tlul.init in
              Ev.subscribe
                (Ev.when_ (Sig.const clk true)
                   (Sig.map2 (fun c s -> (c, s)) (Sig.cycle clk) (Tlul.sample p)))
                (fun (c, s) ->
                  let s, evs = Tlul.step p !st c s in
                  st := s;
                  List.iter
                    (function
                      | Tlul.Accepted t -> Printf.printf "%d accepted %s\n" c (pp t)
                      | Responded t -> Printf.printf "%d responded %s\n" c (pp t)
                      | Unmatched s -> Printf.printf "%d unmatched source %d\n" c s)
                    evs;
                  if c = 7 then Printf.printf "max outstanding %d\n" (Tlul.max_outstanding !st)));
        })
    [ true; false ];
  [%expect
    {|
    d_ready true
    1 accepted Get src 1 10 req 0 acc 1 resp - data 0
    2 accepted Put src 2 20 req 2 acc 2 resp - data 0
    3 responded Get src 1 10 req 0 acc 1 resp 3 data 1234
    4 accepted Get src 1 14 req 4 acc 4 resp - data 0
    4 responded Put src 2 20 req 2 acc 2 resp 4 data 5678
    5 responded Get src 1 14 req 4 acc 4 resp 5 data 0 error
    max outstanding 2
    d_ready false
    1 accepted Get src 1 10 req 0 acc 1 resp - data 0
    2 accepted Put src 2 20 req 2 acc 2 resp - data 0
    3 responded Get src 1 10 req 0 acc 1 resp 3 data 1234
    4 accepted Get src 1 14 req 4 acc 4 resp - data 0
    4 responded Put src 2 20 req 2 acc 2 resp 4 data 5678
    5 responded Get src 1 14 req 4 acc 4 resp 5 data 0 error
    6 unmatched source 3
    max outstanding 2 |}]
