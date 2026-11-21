[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

module SM = Map.Make (struct
  type t = string * string

  let compare = compare
end)

type row = { cls : string; region : string; count : int; cycles : int; d_to_r : int }

let row_jsont =
  Codec.record "cost.row" (fun cls region count cycles d_to_r ->
      { cls; region; count; cycles; d_to_r })
  |> Jsont.Object.mem "class" Jsont.string ~enc:(fun r -> r.cls)
  |> Jsont.Object.mem "region" Jsont.string ~enc:(fun r -> r.region)
  |> Jsont.Object.mem "count" Jsont.int ~enc:(fun r -> r.count)
  |> Jsont.Object.mem "cycles" Jsont.int ~enc:(fun r -> r.cycles)
  |> Jsont.Object.mem "d_to_r" Jsont.int ~enc:(fun r -> r.d_to_r)
  |> Jsont.Object.finish

let region_name (a : Memory.Event.access) = match a.access.region with Some r -> r | None -> "mem"

(* The instances of a PC in dispatch order, so a request's owner is the last one dispatched at or before
   it: a store can make its request after it retired, but not before it was dispatched. A binary search
   finds it, and the later of equal dispatch cycles wins. *)
let owner instances ~pc ~cycle =
  match Hashtbl.find_opt instances pc with
  | None -> None
  | Some a ->
      let lo = ref 0 and hi = ref (Array.length a) in
      while !lo < !hi do
        let mid = (!lo + !hi) / 2 in
        if fst a.(mid) <= cycle then lo := mid + 1 else hi := mid
      done;
      if !lo = 0 then None else Some (snd a.(!lo - 1))

let join ~classify ~(window : Text.window) (commits : Commits.commit list)
    (accesses : Memory.Event.access list) =
  let by_pc = Hashtbl.create 64 in
  List.iteri
    (fun i (c : Commits.commit) ->
      let at = Option.value c.dispatched ~default:c.retired in
      Hashtbl.replace by_pc c.pc ((at, i) :: Option.value (Hashtbl.find_opt by_pc c.pc) ~default:[]))
    commits;
  let instances = Hashtbl.create (Hashtbl.length by_pc) in
  Hashtbl.iter (fun pc l -> Hashtbl.replace instances pc (Array.of_list (List.rev l))) by_pc;
  let commits = Array.of_list commits in
  let region = Array.make (Array.length commits) None in
  List.iter
    (fun (a : Memory.Event.access) ->
      match owner instances ~pc:a.pc ~cycle:a.cycle with
      | Some i -> if region.(i) = None then region.(i) <- Some (region_name a)
      | None -> ())
    accesses;
  let m = ref SM.empty in
  let selected = Text.selected window in
  Array.iteri
    (fun i (c : Commits.commit) ->
      if selected ~cycle:c.retired ~pc:c.pc then begin
        let key =
          ( (match c.word with Some w -> classify w | None -> "unknown"),
            Option.value region.(i) ~default:"-" )
        in
        let d = match c.dispatched with Some x -> c.retired - x | None -> 0 in
        m :=
          SM.update key
            (fun r ->
              let r = Option.value r ~default:(0, 0, 0) in
              let n, cy, dr = r in
              Some (n + 1, cy + c.charged, dr + d))
            !m
      end)
    commits;
  SM.bindings !m
  |> List.map (fun ((cls, region), (count, cycles, d_to_r)) ->
      { cls; region; count; cycles; d_to_r })
  |> List.stable_sort (fun a b -> compare (b.cycles, a.cls, a.region) (a.cycles, b.cls, b.region))

let text rows =
  Printf.printf "%-12s %-10s %6s %7s %8s\n" "class" "region" "count" "cycles" "d->r";
  List.iter
    (fun r ->
      Printf.printf "%-12s %-10s %6d %7d %8.2f\n" r.cls r.region r.count r.cycles
        (float r.d_to_r /. float r.count))
    rows
