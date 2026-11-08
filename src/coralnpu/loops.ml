[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

module IM = Map.Make (Int)

type trip = { start : int; instructions : int; cycles : int }
type pc_stat = { pc : int; word : int option; count : int; cycles : int }

type loop = {
  header : int;
  tail : int;
  trips : trip list;
  body : pc_stat list;
  parent : int option;
}

(* A conditional branch, or a jal that links nowhere (a call links to x1). *)
let branches (c : Commits.commit) =
  match c.word with
  | None -> true
  | Some w -> (
      match w land 0x7f with 0x63 -> true | 0x6f -> (w lsr 7) land 0x1f = 0 | _ -> false)

type acc = { mutable tail : int; mutable trips : trip list; mutable body : pc_stat IM.t }

let detect commits =
  let c = Array.of_list commits in
  let n = Array.length c in
  let prefix = Array.make (n + 1) 0 in
  Array.iteri (fun i (x : Commits.commit) -> prefix.(i + 1) <- prefix.(i) + x.charged) c;
  let backward j = j > 0 && c.(j - 1).pc >= c.(j).pc && branches c.(j - 1) in
  (* The back edges, as (header, tail): a loop that is never branched back to is not found. *)
  let edges = Hashtbl.create 16 in
  for j = 1 to n - 1 do
    if backward j then Hashtbl.replace edges (c.(j).pc, c.(j - 1).pc) ()
  done;
  let tails = Hashtbl.create 16 in
  Hashtbl.iter (fun (h, t) () -> Hashtbl.add tails t h) edges;
  let last = Hashtbl.create 64 and loops = Hashtbl.create 16 in
  let record header s e =
    let a =
      match Hashtbl.find_opt loops header with
      | Some a -> a
      | None ->
          let a = { tail = c.(e).pc; trips = []; body = IM.empty } in
          Hashtbl.add loops header a;
          a
    in
    a.tail <- max a.tail c.(e).pc;
    a.trips <-
      { start = c.(s).retired; instructions = e - s + 1; cycles = prefix.(e + 1) - prefix.(s) }
      :: a.trips;
    for k = s to e do
      let x = c.(k) in
      a.body <-
        IM.update x.pc
          (function
            | None -> Some { pc = x.pc; word = x.word; count = 1; cycles = x.charged }
            | Some p -> Some { p with count = p.count + 1; cycles = p.cycles + x.charged })
          a.body
    done
  in
  for j = 0 to n - 1 do
    let pc = c.(j).pc in
    if j > 0 then
      if backward j then
        match Hashtbl.find_opt last pc with Some s -> record pc s (j - 1) | None -> ()
      else if pc = c.(j - 1).pc + 4 then
        (* The last trip leaves through the same branch, not taken. *)
        List.iter
          (fun h -> match Hashtbl.find_opt last h with Some s -> record h s (j - 1) | None -> ())
          (Hashtbl.find_all tails c.(j - 1).pc);
    Hashtbl.replace last pc j
  done;
  (* The run ends on a tail: that iteration is complete too. *)
  if n > 0 then
    List.iter
      (fun h -> match Hashtbl.find_opt last h with Some s -> record h s (n - 1) | None -> ())
      (Hashtbl.find_all tails c.(n - 1).pc);
  let spans = Hashtbl.fold (fun header (a : acc) l -> (header, a.tail) :: l) loops [] in
  (* The innermost loop whose range holds this one's. *)
  let parent header tail =
    List.fold_left
      (fun best (h, t) ->
        if (h, t) <> (header, tail) && h <= header && tail <= t then
          match best with Some (bh, bt) when bt - bh <= t - h -> best | _ -> Some (h, t)
        else best)
      None spans
    |> Option.map fst
  in
  Hashtbl.fold
    (fun header a l ->
      {
        header;
        tail = a.tail;
        trips = List.rev a.trips;
        body = List.map snd (IM.bindings a.body);
        parent = parent header a.tail;
      }
      :: l)
    loops []
  |> List.sort (fun (a : loop) (b : loop) ->
      let total (l : loop) = List.fold_left (fun n (t : trip) -> n + t.cycles) 0 l.trips in
      compare (total b, a.header) (total a, b.header))

let median = function [] -> 0 | l -> List.nth (List.sort compare l) ((List.length l - 1) / 2)

let trip_jsont =
  Jsont.Object.map ~kind:"trip" (fun start instructions cycles : trip ->
      { start; instructions; cycles })
  |> Jsont.Object.mem "start" Jsont.int ~enc:(fun (t : trip) -> t.start)
  |> Jsont.Object.mem "instructions" Jsont.int ~enc:(fun (t : trip) -> t.instructions)
  |> Jsont.Object.mem "cycles" Jsont.int ~enc:(fun (t : trip) -> t.cycles)
  |> Jsont.Object.finish

let pc_jsont =
  Jsont.Object.map ~kind:"loop pc" (fun pc word count cycles : pc_stat ->
      { pc; word; count; cycles })
  |> Jsont.Object.mem "pc" Jsont.int ~enc:(fun (p : pc_stat) -> p.pc)
  |> Codec.opt (fun (p : pc_stat) -> p.word) "word" Jsont.int
  |> Jsont.Object.mem "count" Jsont.int ~enc:(fun (p : pc_stat) -> p.count)
  |> Jsont.Object.mem "cycles" Jsont.int ~enc:(fun (p : pc_stat) -> p.cycles)
  |> Jsont.Object.finish

let loop_jsont =
  Codec.record "loops.loop" (fun header tail trips body parent : loop ->
      { header; tail; trips; body; parent })
  |> Jsont.Object.mem "header" Jsont.int ~enc:(fun (l : loop) -> l.header)
  |> Jsont.Object.mem "tail" Jsont.int ~enc:(fun (l : loop) -> l.tail)
  |> Jsont.Object.mem "trips" (Jsont.list trip_jsont) ~enc:(fun (l : loop) -> l.trips)
  |> Jsont.Object.mem "pcs" (Jsont.list pc_jsont) ~enc:(fun (l : loop) -> l.body)
  |> Codec.opt (fun (l : loop) -> l.parent) "parent" Jsont.int
  |> Jsont.Object.finish

let stats l =
  let sorted = List.sort compare l in
  Printf.sprintf "%d (%d..%d)" (median l) (List.hd sorted)
    (List.nth sorted (List.length sorted - 1))

let text ~disasm ~symbol loops =
  let at pc =
    match symbol pc with
    | Some (name, 0) -> Printf.sprintf " <%s>" name
    | Some (name, off) -> Printf.sprintf " <%s+%d>" name off
    | None -> ""
  in
  List.iter
    (fun (l : loop) ->
      let n = List.length l.trips in
      Printf.printf "loop %08x%s, back edge at %08x: %d trips%s\n" l.header (at l.header) l.tail n
        (match l.parent with Some h -> Printf.sprintf ", inside loop %08x" h | None -> "");
      Printf.printf "  instructions a trip %s\n"
        (stats (List.map (fun (t : trip) -> t.instructions) l.trips));
      Printf.printf "  cycles a trip %s\n" (stats (List.map (fun (t : trip) -> t.cycles) l.trips));
      Printf.printf "  cycles by trip: %s\n"
        (String.concat " " (List.map (fun (t : trip) -> string_of_int t.cycles) l.trips));
      Printf.printf "  %8s %6s %7s  %s\n" "pc" "count" "cyc/trip" "instruction";
      List.iter
        (fun (p : pc_stat) ->
          Printf.printf "  %08x %6d %7.2f  %s\n" p.pc p.count
            (float p.cycles /. float n)
            (match p.word with Some w -> disasm w | None -> "?"))
        l.body)
    loops
