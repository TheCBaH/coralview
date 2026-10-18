open Hwfrp

let%expect_test "Span and Transaction" =
  let t =
    {
      Transaction.id = 0;
      write = false;
      address = 0x100;
      bytes = 16;
      beats = 1;
      requested = 3;
      accepted = 5;
      first_data = Some 7;
      completed = Some 8;
      status = 0;
      outstanding = 1;
    }
  in
  let opt f = function Some x -> f x | None -> "-" in
  Printf.printf "latency %s span %s throughput %s\n"
    (opt string_of_int (Transaction.latency t))
    (opt string_of_int (Span.length (Transaction.span t)))
    (opt (Printf.sprintf "%.2f") (Transaction.throughput t));
  let t = { t with completed = None } in
  Printf.printf "open: latency %s span %s throughput %s\n"
    (opt string_of_int (Transaction.latency t))
    (opt string_of_int (Span.length (Transaction.span t)))
    (opt (Printf.sprintf "%.2f") (Transaction.throughput t));
  [%expect {|
    latency 3 span 6 throughput 2.67
    open: latency - span - throughput -
    |}]

let reduce =
  let open QCheck2 in
  let l = Gen.(list (int_range (-50) 50)) in
  [
    Test.make ~name:"Stats" ~count:500
      ~print:Print.(list int)
      l
      (fun xs ->
        let s = Reduce.Stats.of_seq (List.to_seq xs) in
        s.n = List.length xs
        && s.sum = List.fold_left ( + ) 0 xs
        && (xs = []
           || (s.min = List.fold_left min max_int xs && s.max = List.fold_left max min_int xs))
        && (xs = [] || Float.abs (Reduce.Stats.mean s -. (float s.sum /. float s.n)) < 1e-9)
        && (xs <> [] || Float.is_nan (Reduce.Stats.mean s)));
    Test.make ~name:"Histogram" ~count:500
      ~print:Print.(list int)
      l
      (fun xs ->
        let h = Reduce.Histogram.of_seq (List.to_seq xs) in
        let keys = List.sort_uniq compare xs in
        Reduce.Histogram.to_list h
        = List.map (fun k -> (k, List.length (List.filter (( = ) k) xs))) keys
        && Reduce.Histogram.total h = List.length xs);
    Test.make ~name:"Group.by" ~count:500
      ~print:Print.(list int)
      l
      (fun xs ->
        let key x = x mod 7 in
        let firsts =
          List.fold_left (fun acc x -> if List.mem (key x) acc then acc else acc @ [ key x ]) [] xs
        in
        Reduce.Group.by key (fun acc x -> acc @ [ x ]) [] (List.to_seq xs)
        = List.map (fun k -> (k, List.filter (fun x -> key x = k) xs)) firsts);
  ]

let%expect_test "Reduce" =
  let rand = Random.State.make [| 2026 |] in
  List.iter (QCheck2.Test.check_exn ~rand) reduce;
  let h = Reduce.Histogram.(add ~count:(-1) (add (add empty 3) 3) 3) in
  Printf.printf "%s\n"
    (String.concat " "
       (List.map (fun (k, c) -> Printf.sprintf "%d:%d" k c) (Reduce.Histogram.to_list h)));
  [%expect {| 3:1 |}]
