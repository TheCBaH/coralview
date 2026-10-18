open Coralview

let profile =
  QCheck2.Test.make ~name:"Profile.by" ~count:500
    ~print:QCheck2.Print.(list (pair (option int) (pair int int)))
    QCheck2.Gen.(list (pair (option (int_bound 9)) (pair (int_bound 50) (int_bound 50))))
    (fun events ->
      let rows =
        Profile.by ~key:fst
          ~weight:(fun (_, (w, _)) -> w)
          ~total:(fun (_, (_, t)) -> t)
          (List.to_seq events)
      in
      let keys = List.sort_uniq compare (List.filter_map fst events) in
      let expect k =
        let mine = List.filter (fun (k', _) -> k' = Some k) events in
        ( List.length mine,
          List.fold_left (fun a (_, (w, _)) -> a + w) 0 mine,
          List.fold_left (fun a (_, (_, t)) -> a + t) 0 mine )
      in
      List.length rows = List.length keys
      && List.for_all
           (fun (r : int Profile.row) -> expect r.key = (r.count, r.weight, r.total))
           rows
      && fst
           (List.fold_left
              (fun (ok, prev) (r : int Profile.row) -> (ok && r.weight <= prev, r.weight))
              (true, max_int) rows))

let%expect_test "Profile" =
  QCheck2.Test.check_exn ~rand:(Random.State.make [| 2026 |]) profile;
  print_endline (Codec.to_line Profile.pc_jsont { key = 0x100; count = 2; weight = 32; total = 9 });
  [%expect {| {"pc":256,"count":2,"weight":32,"total":9} |}]
