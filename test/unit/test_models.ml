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
