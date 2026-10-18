[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

module Stats = struct
  type t = { n : int; min : int; max : int; sum : int }

  let empty = { n = 0; min = max_int; max = min_int; sum = 0 }
  let add s x = { n = s.n + 1; min = Int.min s.min x; max = Int.max s.max x; sum = s.sum + x }
  let of_seq = Seq.fold_left add empty
  let mean s = if s.n = 0 then Float.nan else float s.sum /. float s.n
end

module Histogram = struct
  module M = Map.Make (Int)

  type t = int M.t

  let empty = M.empty

  let add ?(count = 1) h k =
    if count = 0 then h
    else
      M.update k (fun c -> match Option.value c ~default:0 + count with 0 -> None | c -> Some c) h

  let of_seq = Seq.fold_left (fun h k -> add h k) empty
  let to_list = M.bindings
  let total h = M.fold (fun _ c a -> a + c) h 0
end

module Group = struct
  let by key f init s =
    let tbl = Hashtbl.create 64 and order = ref [] in
    Seq.iter
      (fun x ->
        let k = key x in
        match Hashtbl.find_opt tbl k with
        | Some acc -> Hashtbl.replace tbl k (f acc x)
        | None ->
            order := k :: !order;
            Hashtbl.replace tbl k (f init x))
      s;
    List.rev_map (fun k -> (k, Hashtbl.find tbl k)) !order
end
