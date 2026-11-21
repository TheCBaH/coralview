open Coralview

(* The log of a whole list of instructions, ordered by cycle, as {!Kanata.write} first made it. *)
let reference (insns : Kanata.insn list) =
  let lines = ref [] and seq = ref 0 and rid = ref 0 in
  let at cycle line =
    incr seq;
    lines := (cycle, !seq, line) :: !lines
  in
  List.iteri
    (fun id (i : Kanata.insn) ->
      match i.stages with
      | [] -> ()
      | first :: _ ->
          at first.start (Printf.sprintf "I\t%d\t%d\t0" id id);
          at first.start (Printf.sprintf "L\t%d\t0\t%s" id i.label);
          Option.iter (fun d -> at first.start (Printf.sprintf "L\t%d\t1\t%s" id d)) i.detail;
          List.iter
            (fun (s : Kanata.stage) ->
              at s.start (Printf.sprintf "S\t%d\t%d\t%s" id s.lane s.name);
              at (s.stop + 1) (Printf.sprintf "E\t%d\t%d\t%s" id s.lane s.name))
            i.stages;
          Option.iter
            (fun r ->
              at r (Printf.sprintf "R\t%d\t%d\t0" id !rid);
              incr rid)
            i.retired;
          Option.iter (fun c -> at c (Printf.sprintf "R\t%d\t%d\t1" id !rid)) i.flushed)
    insns;
  let lines = List.sort compare !lines in
  let b = Buffer.create 256 in
  Buffer.add_string b "Kanata\t0004\n";
  (match lines with
  | (c, _, _) :: _ -> Buffer.add_string b (Printf.sprintf "C=\t%d\n" c)
  | [] -> ());
  ignore
    (List.fold_left
       (fun now (c, _, line) ->
         if c > now then Buffer.add_string b (Printf.sprintf "C\t%d\n" (c - now));
         Buffer.add_string b line;
         Buffer.add_char b '\n';
         max now c)
       (match lines with (c, _, _) :: _ -> c | [] -> 0)
       lines);
  Buffer.contents b

let insn ?(stall = 0) ~start ~len ?(retired = true) () : Kanata.insn =
  let ex = { Kanata.name = "Ex"; lane = 0; start; stop = start + len - 1 } in
  {
    label = Printf.sprintf "i@%d" start;
    detail = (if stall > 0 then Some "stalled" else None);
    stages =
      (if stall > 0 then [ { name = "St"; lane = 1; start = start - stall; stop = start - 1 }; ex ]
       else [ ex ]);
    retired = (if retired then Some (start + len) else None);
    flushed = (if retired then None else Some (start + len));
  }

let first (i : Kanata.insn) = (List.hd i.stages).start

(* Instructions ordered by the start of their first stage, and a legal watermark after each. *)
let gen =
  QCheck2.Gen.(
    list_size (int_bound 30) (triple (int_bound 4) (int_range 1 9) (pair (int_bound 3) bool))
    >|= fun spec ->
    let t = ref 10 in
    List.map
      (fun (gap, len, (stall, retired)) ->
        t := !t + gap;
        insn ~stall:(min stall !t) ~start:!t ~len ~retired ())
      spec
    |> List.stable_sort (fun a b -> compare (first a) (first b)))

let writer =
  QCheck2.Test.make ~name:"Kanata.write of ordered instructions is the whole-list log" ~count:500
    gen (fun insns ->
      let file = Filename.temp_file "kanata" ".log" in
      let oc = open_out_bin file in
      Kanata.write oc (List.to_seq insns);
      close_out oc;
      let got = In_channel.with_open_bin file In_channel.input_all in
      Sys.remove file;
      got = reference insns)

let watermark =
  QCheck2.Test.make ~name:"a Writer told any legal watermark gives the whole-list log" ~count:500
    gen (fun insns ->
      let b = Buffer.create 256 in
      let w = Kanata.Writer.create (Buffer.add_string b) in
      let rec go = function
        | [] -> ()
        | i :: rest ->
            Kanata.Writer.add w i;
            (* The least start of the rest bounds what it can still write. *)
            (match rest with
            | next :: _ -> Kanata.Writer.advance w (first next - 1)
            | [] -> ());
            go rest
      in
      go insns;
      Kanata.Writer.finish w;
      Buffer.contents b = reference insns)

let%expect_test "ordered instructions are written as they come" =
  QCheck2.Test.check_exn ~rand:(Random.State.make [| 2026 |]) writer;
  QCheck2.Test.check_exn ~rand:(Random.State.make [| 2027 |]) watermark;
  let b = Buffer.create 256 in
  let w = Kanata.Writer.create (Buffer.add_string b) in
  Kanata.Writer.add w (insn ~start:10 ~len:3 ());
  Kanata.Writer.add w (insn ~start:11 ~len:1 ());
  Printf.printf "held: %d bytes\n" (Buffer.length b);
  Kanata.Writer.advance w 12;
  print_string (Buffer.contents b);
  [%expect
    {|
    held: 12 bytes
    Kanata	0004
    C=	10
    I	0	0	0
    L	0	0	i@10
    S	0	0	Ex
    C	1
    I	1	1	0
    L	1	0	i@11
    S	1	0	Ex
    |}]

let%expect_test "a line before the watermark is refused" =
  let w = Kanata.Writer.create ignore in
  Kanata.Writer.add w (insn ~start:10 ~len:3 ());
  Kanata.Writer.advance w 12;
  Kanata.Writer.advance w 5;
  (try Kanata.Writer.add w (insn ~start:11 ~len:1 ()) with Invalid_argument m -> print_endline m);
  Kanata.Writer.add w (insn ~start:12 ~len:1 ());
  (try Kanata.write stdout (List.to_seq [ insn ~start:5 ~len:1 (); insn ~start:4 ~len:1 () ])
   with Invalid_argument m -> print_endline m);
  [%expect
    {|
    Kanata.Writer.add: instruction 1 starts at cycle 11, before cycle 12
    Kanata	0004
    Kanata.Writer.add: instruction 1 starts at cycle 4, before cycle 5 |}]

(* The log of events as the builder writes it. *)
let build ~stalls ~commits =
  let b = Buffer.create 256 in
  let t =
    Kanata.Builder.create ~disasm:(Printf.sprintf "op%x")
      (Kanata.Writer.create (Buffer.add_string b))
  in
  List.iter (Kanata.Builder.stall t) stalls;
  List.iter (Kanata.Builder.commit t) commits;
  Kanata.Builder.finish t;
  Buffer.contents b

let commit ~pc ~dispatched ~retired : Commits.Event.t =
  Commit
    {
      lane = 0;
      pc;
      word = Some pc;
      dispatched = Some dispatched;
      written = None;
      retired;
      dest = None;
      store = false;
      trap = false;
      charged = 1;
    }

let%expect_test "the builder: a stall before dispatch, one never used, an instruction in flight" =
  let stall pc start stop : Stalls.Event.t =
    Stall_span
      { lane = 1; reason = Raw; pc; word = pc; span = { Hwfrp.Span.start; stop = Some stop } }
  in
  print_string
    (build
       ~stalls:[ stall 0x10 3 5; stall 0x99 4 4 ]
       ~commits:
         [
           commit ~pc:0x08 ~dispatched:2 ~retired:4;
           commit ~pc:0x10 ~dispatched:6 ~retired:9;
           In_flight { pc = 0x14; word = 0x14; cycle = 7; charged = 1 };
         ]);
  [%expect
    {|
    Kanata	0004
    C=	2
    I	0	0	0
    L	0	0	00000008 op8
    S	0	0	Ex
    C	1
    I	1	1	0
    L	1	0	00000010 op10
    L	1	1	stalled: raw
    S	1	1	St
    C	1
    E	0	0	Ex
    R	0	0	0
    C	2
    E	1	1	St
    S	1	0	Ex
    C	1
    I	2	2	0
    L	2	0	00000014 op14
    S	2	0	Ex
    C	2
    E	1	0	Ex
    R	1	1	0
    C	1
    E	2	0	Ex
    R	2	2	1
    |}]
