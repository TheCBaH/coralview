[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

type 'k row = { key : 'k; count : int; weight : int; total : int }

let by ?(buckets = 64) ~key ?(weight = fun _ -> 0) ?(total = fun _ -> 0) events =
  let t = Hashtbl.create buckets in
  Seq.iter
    (fun e ->
      match key e with
      | None -> ()
      | Some k ->
          let n, w, s = Option.value (Hashtbl.find_opt t k) ~default:(0, 0, 0) in
          Hashtbl.replace t k (n + 1, w + weight e, s + total e))
    events;
  Hashtbl.fold (fun key (count, weight, total) acc -> { key; count; weight; total } :: acc) t []
  |> List.sort (fun a b -> Int.compare b.weight a.weight)

let by_pc ?buckets ~pc ?weight ?total events = by ?buckets ~key:pc ?weight ?total events

let pc_jsont =
  Jsont.Object.map ~kind:"profile" (fun key count weight total -> { key; count; weight; total })
  |> Jsont.Object.mem "pc" Jsont.int ~enc:(fun r -> r.key)
  |> Jsont.Object.mem "count" Jsont.int ~enc:(fun r -> r.count)
  |> Jsont.Object.mem "weight" Jsont.int ~enc:(fun r -> r.weight)
  |> Jsont.Object.mem "total" Jsont.int ~enc:(fun r -> r.total)
  |> Jsont.Object.finish
