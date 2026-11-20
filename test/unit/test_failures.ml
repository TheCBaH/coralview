open Hwfrp
open Coralview

let read file = In_channel.with_open_bin file In_channel.input_all

let platform file =
  match Platform.of_string (read file) with
  | Ok f -> List.hd (Platform.configurations f)
  | Error e -> failwith e

let noise (c : _ Core.t) n =
  for i = 1 to n do
    Diag.report c.net (Diag.make ~source:"noise" ~code:"noise.x" (string_of_int i))
  done

let show relations failures status =
  let failed = List.filter (fun (_, _, n) -> n > 0) relations in
  Printf.printf "failures: %s; details kept: %d; status %d\n"
    (String.concat " " (List.map (fun (code, _, n) -> Printf.sprintf "%s=%d" code n) failed))
    failures status

let registers ~cap ~noise:n =
  let (Core.Any c) =
    Core.bind ~max_diags:cap
      (platform "../registers.t/reg-core.json")
      (Hwfrp_vcd.of_string (read "../registers.t/bad.vcd"))
      ~model:"registers"
  in
  let _, summary = Registers.build Registers.Config.default c in
  noise c n;
  let s = summary (Core.run c) in
  show s.relations (List.length s.failures) (Registers.status s)

let vectors ~cap ~noise:n =
  let (Core.Any c) =
    Core.bind ~max_diags:cap
      (platform "../vectors.t/vector-core.json")
      (Hwfrp_vcd.of_string (read "../vectors.t/bad.vcd"))
      ~model:"vectors"
  in
  let _, summary = Vectors.build Vectors.Config.default c in
  noise c n;
  let s = summary (Core.run c) in
  show s.relations (List.length s.failures) (Vectors.status s)

let%expect_test "an unrelated code spends the budget before the first model failure" =
  registers ~cap:2 ~noise:2;
  vectors ~cap:2 ~noise:2;
  [%expect
    {|
    failures: registers.storage=1 registers.architectural=1; details kept: 0; status 1
    failures: vectors.storage=1 vectors.retired=1; details kept: 0; status 1 |}]

let%expect_test "a model fails more often than the budget" =
  registers ~cap:1 ~noise:0;
  vectors ~cap:1 ~noise:0;
  [%expect
    {|
    failures: registers.storage=1 registers.architectural=1; details kept: 1; status 1
    failures: vectors.storage=1 vectors.retired=1; details kept: 1; status 1 |}]
