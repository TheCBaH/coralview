open Coralview

(* The scalar scoreboard's view of an instruction, at the RTL release the platforms are built against:
   Decode.scala's [writesRd] with [floatWritesRd] and [rvvWritesRd]. *)
let words =
  [
    (0x02a00413, "addi x8, x0, 42");
    (0x0000a403, "lw x8, 0(x1)");
    (0x00000013, "addi x0, x0, 0 (rd x0)");
    (0x01007457, "vsetvli x8, x0, e32, m1");
    (0xc1027457, "vsetivli x8, 4, e32, m1");
    (0x8020f457, "vsetvl x8, x1, x2");
    (0x42202457, "vmv.x.s x8, v2");
    (0x42282457, "vcpop.m x8, v2");
    (0x4228a457, "vfirst.m x8, v2");
    (0x02208457, "vadd.vv v8, v2, v1");
    (0x5e00c457, "vmv.v.x v8, x1");
    (0x42201457, "vfmv.f.s f8, v2");
    (0x0000a407, "flw f8, 0(x1)");
    (0x0200e407, "vle32.v v8, (x1)");
    (0xe0008453, "fmv.x.w x8, f1");
    (0xe0009453, "fclass.s x8, f1");
    (0xa020a453, "feq.s x8, f1, f2");
    (0xa0209453, "flt.s x8, f1, f2");
    (0xa0208453, "fle.s x8, f1, f2");
    (0xc0008453, "fcvt.w.s x8, f1");
    (0xe0008053, "fmv.x.w x0, f1 (rd x0)");
    (0x00208453, "fadd.s f8, f1, f2");
    (0xf0008453, "fmv.w.x f8, x1");
    (0xd0008453, "fcvt.s.w f8, x1");
    (0x43e06457, "vtzero mt4");
    (0xf2040077, "vtmmu.tvv");
  ]

let%expect_test "which instructions write an x register" =
  List.iter
    (fun (w, name) ->
      Printf.printf "%08x %-40s %s\n" w name (if Stalls.writes_rd w then "x" else "-"))
    words;
  [%expect
    {|
    02a00413 addi x8, x0, 42                          x
    0000a403 lw x8, 0(x1)                             x
    00000013 addi x0, x0, 0 (rd x0)                   -
    01007457 vsetvli x8, x0, e32, m1                  x
    c1027457 vsetivli x8, 4, e32, m1                  x
    8020f457 vsetvl x8, x1, x2                        x
    42202457 vmv.x.s x8, v2                           x
    42282457 vcpop.m x8, v2                           x
    4228a457 vfirst.m x8, v2                          x
    02208457 vadd.vv v8, v2, v1                       -
    5e00c457 vmv.v.x v8, x1                           -
    42201457 vfmv.f.s f8, v2                          -
    0000a407 flw f8, 0(x1)                            -
    0200e407 vle32.v v8, (x1)                         -
    e0008453 fmv.x.w x8, f1                           x
    e0009453 fclass.s x8, f1                          x
    a020a453 feq.s x8, f1, f2                         x
    a0209453 flt.s x8, f1, f2                         x
    a0208453 fle.s x8, f1, f2                         x
    c0008453 fcvt.w.s x8, f1                          x
    e0008053 fmv.x.w x0, f1 (rd x0)                   -
    00208453 fadd.s f8, f1, f2                        -
    f0008453 fmv.w.x f8, x1                           -
    d0008453 fcvt.s.w f8, x1                          -
    43e06457 vtzero mt4                               -
    f2040077 vtmmu.tvv                                -
    |}]

let core : Stalls.core =
  {
    halted = false;
    interlock = false;
    regd = 0;
    n_space = 8;
    rob_empty = true;
    trap_pending = false;
    lsu_cap = 8;
    rvv_cap = 8;
  }

(* One stalled lane whose x8 is busy in the scoreboard. *)
let reason ?(comb = 1 lsl 8) ?(fcomb = 0) word =
  let port : Stalls.port =
    { valid = true; ready = false; try_ = false; pc = 0x100; word; comb; fcomb }
  in
  match Stalls.classify core [ port ] with [ l ] -> Stalls.reason_name l.reason | _ -> "?"

let%expect_test "a stalled instruction whose x destination is busy waits on it" =
  List.iter
    (fun (w, name) -> Printf.printf "%-28s %s\n" name (reason w))
    [
      (0x02a00413, "addi x8, x0, 42");
      (0xe0008453, "fmv.x.w x8, f1");
      (0xa020a453, "feq.s x8, f1, f2");
      (0xc0008453, "fcvt.w.s x8, f1");
      (0x42202457, "vmv.x.s x8, v2");
      (0x01007457, "vsetvli x8, x0, e32, m1");
      (0x02208457, "vadd.vv v8, v2, v1");
      (0x00208453, "fadd.s f8, f1, f2");
      (0x43e06457, "vtzero mt4");
    ];
  [%expect
    {|
    addi x8, x0, 42              waw
    fmv.x.w x8, f1               waw
    feq.s x8, f1, f2             waw
    fcvt.w.s x8, f1              waw
    vmv.x.s x8, v2               waw
    vsetvli x8, x0, e32, m1      waw
    vadd.vv v8, v2, v1           other
    fadd.s f8, f1, f2            other
    vtzero mt4                   other
    |}]
