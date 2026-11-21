[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

type 'k row = { key : 'k; count : int; weight : int; total : int }

module Acc = struct
  type ('e, 'k) t = {
    table : ('k, int * int * int) Hashtbl.t;
    of_key : 'e -> 'k option;
    of_weight : 'e -> int;
    of_total : 'e -> int;
  }

  let create ?(buckets = 64) ~key ?(weight = fun _ -> 0) ?(total = fun _ -> 0) () =
    { table = Hashtbl.create buckets; of_key = key; of_weight = weight; of_total = total }

  let add t e =
    match t.of_key e with
    | None -> ()
    | Some k ->
        let n, w, s = Option.value (Hashtbl.find_opt t.table k) ~default:(0, 0, 0) in
        Hashtbl.replace t.table k (n + 1, w + t.of_weight e, s + t.of_total e)

  let rows t =
    Hashtbl.fold
      (fun key (count, weight, total) acc -> { key; count; weight; total } :: acc)
      t.table []
    |> List.sort (fun a b ->
        match Int.compare b.weight a.weight with 0 -> compare a.key b.key | c -> c)
end

let by ?buckets ~key ?weight ?total events =
  let acc = Acc.create ?buckets ~key ?weight ?total () in
  Seq.iter (Acc.add acc) events;
  Acc.rows acc

let by_pc ?buckets ~pc ?weight ?total events = by ?buckets ~key:pc ?weight ?total events

let pc_jsont =
  Jsont.Object.map ~kind:"profile" (fun key count weight total -> { key; count; weight; total })
  |> Jsont.Object.mem "pc" Jsont.int ~enc:(fun r -> r.key)
  |> Jsont.Object.mem "count" Jsont.int ~enc:(fun r -> r.count)
  |> Jsont.Object.mem "weight" Jsont.int ~enc:(fun r -> r.weight)
  |> Jsont.Object.mem "total" Jsont.int ~enc:(fun r -> r.total)
  |> Jsont.Object.finish
