open Coralview

let names = List.map Models.name Models.all

let%expect_test "the registry lists the ten models in the order platforms prints them" =
  print_endline (String.concat " " names);
  [%expect {| commits stalls memory axi dma registers tiles ops traps vectors |}]

let%test "each is found by its name" =
  List.for_all (fun n -> Option.map Models.name (Models.find n) = Some n) names
  && Models.find "nosuch" = None

let%test "a platform has the models whose blocks it describes" =
  let p = Platform.find "rvv-core-mini-axi" |> Result.get_ok in
  List.for_all
    (fun m -> List.for_all (fun b -> List.mem b (Platform.blocks p)) (Models.needs m))
    (Models.available p)

let%test "each model needs only known blocks, and what those blocks need" =
  List.for_all
    (fun m ->
      let needs = Models.needs m in
      List.for_all
        (fun b ->
          match List.assoc_opt b Platform.known_blocks with
          | None -> false
          | Some requires -> List.for_all (fun r -> List.mem r needs) requires)
        needs)
    Models.all

let%test "a platform describes known blocks, in registry order" =
  let known = List.map fst Platform.known_blocks in
  List.for_all
    (fun (p : Platform.t) ->
      let described = Platform.blocks p in
      List.filter (fun b -> List.mem b described) known = described)
    (Lazy.force Platform.builtin)

let described text =
  match Platform.of_string text with
  | Ok f -> (
      match Platform.configurations f with
      | p :: _ -> Ok (p.name, p.sample, Platform.blocks p, p.reset <> None)
      | [] -> Error "no configuration")
  | Error e -> Error e

let overlay extra =
  {|{ "schema_version": "1.0", "name": "mine", "extends": "core-mini",
      "configurations": [ { "name": "mine-core", "top_level": "T", "trace_root": ["T"] } ]|}
  ^ extra ^ "}"

let%expect_test "a description extends a built-in one by name" =
  let show text =
    match described text with
    | Ok (name, sample, blocks, reset) ->
        Printf.printf "%s %s reset %b: %s\n" name
          (match sample with
          | Hwfrp.Trace.After_falling -> "after_falling"
          | Before_rising -> "before_rising"
          | After_rising -> "after_rising")
          reset (String.concat " " blocks)
    | Error e -> print_endline e
  in
  show (overlay "");
  show (overlay {|, "sample": "after_rising", "blocks": { "lsu": null, "traps": null }|});
  show (overlay {|, "reset": null|});
  List.iter
    (fun (p : Platform.t) ->
      Printf.printf "%s: %s\n" p.name (String.concat " " (Platform.blocks p)))
    (List.filter
       (fun (p : Platform.t) ->
         List.mem p.name [ "core-mini-axi"; "rvv-core-mini-axi"; "vme-core-mini-axi" ])
       (Lazy.force Platform.builtin));
  show {|{ "extends": "core-mini-axi" }|};
  [%expect
    {|
    mine-core after_falling reset true: dispatch_debug retirement_debug regfile_writeback float_writeback dispatch lsu axi_master x_registers f_registers traps
    mine-core after_rising reset true: dispatch_debug retirement_debug regfile_writeback float_writeback dispatch axi_master x_registers f_registers
    mine-core after_falling reset false: dispatch_debug retirement_debug regfile_writeback float_writeback dispatch lsu axi_master x_registers f_registers traps
    core-mini-axi: dispatch_debug retirement_debug regfile_writeback float_writeback dispatch lsu axi_master x_registers f_registers traps
    rvv-core-mini-axi: dispatch_debug retirement_debug regfile_writeback float_writeback dispatch lsu axi_master x_registers f_registers v_registers v_dispatch traps
    vme-core-mini-axi: dispatch_debug retirement_debug regfile_writeback float_writeback dispatch lsu vme axi_master x_registers f_registers v_registers v_dispatch traps
    extends: no built-in description core-mini-axi (a file is a path ending in .json)
    File "-", line 1, characters 13-28: |}]
