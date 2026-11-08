[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

module IM = Map.Make (Int)

type side = {
  trace : string;
  summary : Window_summary.t;
  window : Text.window;
  commits : Commits.commit list;
  base : int;
  disasm : int -> string;
}

type stat = { count : int; cycles : int; text : string }
type row = { offset : int; a : stat option; b : stat option }

let stats (s : side) =
  List.fold_left
    (fun m (c : Commits.commit) ->
      if Text.selected s.window ~cycle:c.retired ~pc:c.pc then
        IM.update (c.pc - s.base)
          (function
            | None ->
                Some
                  {
                    count = 1;
                    cycles = c.charged;
                    text = (match c.word with Some w -> s.disasm w | None -> "?");
                  }
            | Some x -> Some { x with count = x.count + 1; cycles = x.cycles + c.charged })
          m
      else m)
    IM.empty s.commits

let delta r =
  let cycles = function Some x -> x.cycles | None -> 0 in
  cycles r.b - cycles r.a

let rows ~top a b =
  let sa = stats a and sb = stats b in
  let keys = IM.union (fun _ x _ -> Some x) (IM.map ignore sa) (IM.map ignore sb) in
  IM.fold
    (fun offset () l -> { offset; a = IM.find_opt offset sa; b = IM.find_opt offset sb } :: l)
    keys []
  |> List.sort (fun x y -> compare (abs (delta y), x.offset) (abs (delta x), y.offset))
  |> List.filteri (fun i r -> i < top && delta r <> 0)

let stat_jsont =
  Jsont.Object.map ~kind:"stat" (fun count cycles text -> { count; cycles; text })
  |> Jsont.Object.mem "count" Jsont.int ~enc:(fun (s : stat) -> s.count)
  |> Jsont.Object.mem "cycles" Jsont.int ~enc:(fun (s : stat) -> s.cycles)
  |> Jsont.Object.mem "text" Jsont.string ~enc:(fun (s : stat) -> s.text)
  |> Jsont.Object.finish

let row_jsont =
  Codec.record "compare.pc" (fun offset a b _ : row -> { offset; a; b })
  |> Jsont.Object.mem "offset" Jsont.int ~enc:(fun (r : row) -> r.offset)
  |> Codec.opt (fun (r : row) -> r.a) "a" stat_jsont
  |> Codec.opt (fun (r : row) -> r.b) "b" stat_jsont
  |> Jsont.Object.mem "delta" Jsont.int ~enc:delta
  |> Jsont.Object.finish

let summary_jsont =
  Codec.record "compare.summary" (fun a b -> (a, b))
  |> Jsont.Object.mem "a" Window_summary.jsont ~enc:fst
  |> Jsont.Object.mem "b" Window_summary.jsont ~enc:snd
  |> Jsont.Object.finish

let text ~top a b =
  let sa = a.summary and sb = b.summary in
  Printf.printf "A %s\nB %s\n" a.trace b.trace;
  Printf.printf "%-22s %12s %12s %12s\n" "" "A" "B" "B-A";
  let line name x y = Printf.printf "%-22s %12d %12d %+12d\n" name x y (y - x) in
  line "instructions" sa.instructions sb.instructions;
  line "cycles charged" sa.cycles sb.cycles;
  let opt name f = match (f sa, f sb) with Some x, Some y -> line name x y | _ -> () in
  opt "loads" (fun (s : Window_summary.t) -> s.loads);
  opt "stores" (fun (s : Window_summary.t) -> s.stores);
  opt "vector instructions" (fun (s : Window_summary.t) -> s.vector_instructions);
  opt "vector operations" (fun (s : Window_summary.t) -> s.vector_ops);
  (match (sa.stalls, sb.stalls) with
  | Some x, Some y ->
      let names = List.sort_uniq compare (List.map fst x @ List.map fst y) in
      let get l n = Option.value (List.assoc_opt n l) ~default:0 in
      List.iter (fun n -> line ("dispatch " ^ n) (get x n) (get y n)) names
  | _ -> ());
  let rs = rows ~top a b in
  if rs <> [] then begin
    Printf.printf "\nlargest differences in cycles charged, by offset from the window's function:\n";
    Printf.printf "%8s %6s %7s %6s %7s %7s  %s\n" "offset" "A n" "A cyc" "B n" "B cyc" "B-A"
      "instruction (A | B)";
    let n = function Some x -> string_of_int x.count | None -> "-" in
    let c = function Some x -> string_of_int x.cycles | None -> "-" in
    let t = function Some x -> x.text | None -> "-" in
    List.iter
      (fun r ->
        Printf.printf "%8x %6s %7s %6s %7s %+7d  %s%s\n" r.offset (n r.a) (c r.a) (n r.b) (c r.b)
          (delta r) (t r.a)
          (match (r.a, r.b) with Some x, Some y when x.text = y.text -> "" | _ -> " | " ^ t r.b))
      rs
  end

type loop_stat = {
  header : int;
  trips : int;
  instructions : int;
  cycles_per_trip : int;
  cycles : int;
}

type loop_row = { rank : int; a : loop_stat option; b : loop_stat option }

let loop_stats (s : side) =
  let selected =
    List.filter
      (fun (c : Commits.commit) -> Text.selected s.window ~cycle:c.retired ~pc:c.pc)
      s.commits
  in
  List.map
    (fun (l : Loops.loop) ->
      let per f = Loops.median (List.map f l.trips) in
      {
        header = l.header - s.base;
        trips = List.length l.trips;
        instructions = per (fun (t : Loops.trip) -> t.instructions);
        cycles_per_trip = per (fun (t : Loops.trip) -> t.cycles);
        cycles = List.fold_left (fun n (t : Loops.trip) -> n + t.cycles) 0 l.trips;
      })
    (Loops.detect selected)

let loop_rows ~top a b =
  let la = loop_stats a and lb = loop_stats b in
  List.init
    (min top (max (List.length la) (List.length lb)))
    (fun i -> { rank = i + 1; a = List.nth_opt la i; b = List.nth_opt lb i })

let loop_delta r =
  let cycles = function Some (x : loop_stat) -> x.cycles | None -> 0 in
  cycles r.b - cycles r.a

let loop_stat_jsont =
  Jsont.Object.map ~kind:"loop stat" (fun header trips instructions cycles_per_trip cycles ->
      { header; trips; instructions; cycles_per_trip; cycles })
  |> Jsont.Object.mem "header" Jsont.int ~enc:(fun (l : loop_stat) -> l.header)
  |> Jsont.Object.mem "trips" Jsont.int ~enc:(fun (l : loop_stat) -> l.trips)
  |> Jsont.Object.mem "instructions" Jsont.int ~enc:(fun (l : loop_stat) -> l.instructions)
  |> Jsont.Object.mem "cycles_per_trip" Jsont.int ~enc:(fun (l : loop_stat) -> l.cycles_per_trip)
  |> Jsont.Object.mem "cycles" Jsont.int ~enc:(fun (l : loop_stat) -> l.cycles)
  |> Jsont.Object.finish

let loop_row_jsont =
  Codec.record "compare.loop" (fun rank a b _ : loop_row -> { rank; a; b })
  |> Jsont.Object.mem "rank" Jsont.int ~enc:(fun (r : loop_row) -> r.rank)
  |> Codec.opt (fun (r : loop_row) -> r.a) "a" loop_stat_jsont
  |> Codec.opt (fun (r : loop_row) -> r.b) "b" loop_stat_jsont
  |> Jsont.Object.mem "delta" Jsont.int ~enc:loop_delta
  |> Jsont.Object.finish

let text_loops ~top a b =
  let rs = loop_rows ~top a b in
  if rs <> [] then begin
    Printf.printf
      "\nloops paired by rank of cycles in the loop, header offsets from the window's function:\n";
    let head = Printf.sprintf "%8s %6s %6s %8s %8s" "offset" "trips" "ins" "cyc/trip" "cycles" in
    Printf.printf "%4s  %-40s  %-40s  %8s\n" "" "A" "B" "B-A";
    Printf.printf "%4s  %s  %s\n" "rank" head head;
    let cell = function
      | Some (l : loop_stat) ->
          Printf.sprintf "%8x %6d %6d %8d %8d" l.header l.trips l.instructions l.cycles_per_trip
            l.cycles
      | None -> Printf.sprintf "%40s" "-"
    in
    List.iter
      (fun r -> Printf.printf "%4d  %s  %s  %+8d\n" r.rank (cell r.a) (cell r.b) (loop_delta r))
      rs
  end
