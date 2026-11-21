open Coralview

let ctx ~limit : Text.ctx =
  {
    root = "r";
    disasm = (fun _ -> "?");
    instruction_class = (fun _ -> "?");
    symbol = (fun _ -> None);
    profile_by = Text.Pc;
    region = Region.none;
    window = Text.everything;
    limit;
    profile = 0;
    legend = false;
    note = (fun ~pc:_ ~cycle:_ -> None);
  }

let%expect_test "drain adds the events as they are pulled, then finishes once" =
  let pulled = ref 0 in
  let seen = ref [] in
  let sink : int Text.sink =
    {
      add = (fun x -> seen := Printf.sprintf "add %d (pulled %d)" x !pulled :: !seen);
      finish = (fun () -> seen := "finish" :: !seen);
    }
  in
  Text.drain sink
    (Seq.map
       (fun x ->
         incr pulled;
         x)
       (List.to_seq [ 1; 2; 3 ]));
  List.iter print_endline (List.rev !seen);
  [%expect {|
    add 1 (pulled 1)
    add 2 (pulled 2)
    add 3 (pulled 3)
    finish |}]

let summary : Memory.Summary.t = { reads = 0; writes = 0; pcs = 0; faults = 0; unmatched = 0 }

let access ~id cycle : Memory.Event.t =
  Access
    {
      cycle;
      pc = id;
      access = { Access.address = 0; bytes = 1; write = false; region = None };
      lanes = [ 0 ];
      data = Hwfrp.Bits.zero 8;
    }

let fault ~id cycle : Memory.Event.t =
  Fault { cycle; pc = id; address = 0; write = false; region = None; request = None }

let unmatched ~id cycle : Memory.Event.t = Unmatched { cycle; source = id }

(* The ids of the rows of [Memory.text], in the order printed. *)
let rows events ~limit =
  let buf = Buffer.create 256 in
  let ppf = Format.formatter_of_buffer buf in
  Text.drain (Memory.text (ctx ~limit) ppf (fun () -> summary)) (List.to_seq events);
  Format.pp_print_flush ppf ();
  String.split_on_char '\n' (Buffer.contents buf)
  |> List.filter_map (fun line ->
      match List.filter (( <> ) "") (String.split_on_char ' ' line) with
      | [ _; ("R" | "W"); "pc"; pc; _; _; _; _; _ ] -> Some (int_of_string ("0x" ^ pc))
      | _ :: "fault" :: _ :: "pc" :: pc :: _ -> Some (int_of_string ("0x" ^ pc))
      | [ _; "unmatched"; _; _; _; n ] -> Some (int_of_string n)
      | _ -> None)

let id_of : Memory.Event.t -> int = function
  | Access a -> a.pc
  | Fault f -> f.pc
  | Unmatched u -> u.source

let reference events ~limit =
  let sorted =
    List.stable_sort (fun a b -> compare (Memory.Event.cycle a) (Memory.Event.cycle b)) events
  in
  let shown = ref 0 in
  List.filter_map
    (fun (e : Memory.Event.t) ->
      match e with
      | Access _ when !shown >= limit -> None
      | Access _ ->
          incr shown;
          Some (id_of e)
      | Fault _ | Unmatched _ -> Some (id_of e))
    sorted

let ordering =
  QCheck2.Test.make ~name:"Memory.text rows in request order, as many requests as the limit"
    ~count:500
    ~print:QCheck2.Print.(pair (list (pair int int)) int)
    QCheck2.Gen.(pair (list_size (int_bound 40) (pair (int_bound 3) (int_bound 12))) (int_bound 8))
    (fun (spec, limit) ->
      let events =
        List.mapi
          (fun id (kind, cycle) ->
            match kind with
            | 0 -> fault ~id cycle
            | 1 -> unmatched ~id cycle
            | _ -> access ~id cycle)
          spec
      in
      rows events ~limit = reference events ~limit)

let%expect_test "Memory.text keeps the requests in request order whatever the arrival order" =
  QCheck2.Test.check_exn ~rand:(Random.State.make [| 2026 |]) ordering;
  (* A read is emitted with its response, after later writes. *)
  List.iter
    (fun id -> Printf.printf "%d " id)
    (rows [ access ~id:1 5; access ~id:2 6; access ~id:3 3; fault ~id:4 4 ] ~limit:2);
  print_newline ();
  [%expect {| 3 4 1 |}]
