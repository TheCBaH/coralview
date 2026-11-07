open Coralview

let commit pc ~dispatched ~retired : Commits.commit =
  {
    lane = 0;
    pc;
    word = None;
    dispatched = Some dispatched;
    written = None;
    retired;
    dest = None;
    store = false;
    trap = false;
    charged = 1;
  }

let op ?lmul_orig pc cycle ~sew ~lmul ~vl : Ops.op =
  {
    cycle;
    pc = Some pc;
    unit = "alu";
    mnemonic = None;
    sew;
    lmul;
    lmul_orig;
    vl;
    vstart = 0;
    tile = None;
    kind = Ops.Arith;
    float = false;
    elements = vl;
    ops = vl;
  }

let static = function
  | 0x10 -> Some "e32,m4,ta,ma avl 16"
  | 0x20 -> Some "e16,m1,ta,ma avl x10"
  | _ -> None

let%expect_test
    "notes follow the instance, not the PC, and flag a vtype that differs from the static one" =
  let commits =
    [
      commit 0x10 ~dispatched:2 ~retired:9;
      commit 0x10 ~dispatched:20 ~retired:27;
      commit 0x20 ~dispatched:30 ~retired:35;
      commit 0x30 ~dispatched:40 ~retired:44;
    ]
  in
  let ops =
    [
      op 0x10 4 ~sew:32 ~lmul:"4" ~vl:16;
      (* The second instance runs under a shorter vl, and a squashed dispatch at 15 is nobody's. *)
      op 0x10 22 ~sew:32 ~lmul:"4" ~vl:7;
      op 0x20 32 ~sew:32 ~lmul:"1/2" ~lmul_orig:"1" ~vl:4;
    ]
  in
  let note = Vector_notes.notes ~static commits ops in
  List.iter
    (fun (pc, cycle) ->
      Printf.printf "%x@%d: %s\n" pc cycle (Option.value (note ~pc ~cycle) ~default:"-"))
    [ (0x10, 9); (0x10, 27); (0x20, 35); (0x30, 44); (0x10, 5) ];
  [%expect
    {|
    10@9: e32,m4 vl 16
    10@27: e32,m4 vl 7
    20@35: e32,m1 vl 4 (static e16,m1)
    30@44: -
    10@5: -
    |}]
