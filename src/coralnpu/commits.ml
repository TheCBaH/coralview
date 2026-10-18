[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Hwfrp

let name = "commits"
let doc = "Retired instructions with values and per-instruction cycles."
let needs = [ "dispatch_debug"; "retirement_debug"; "regfile_writeback" ]

module IM = Map.Make (Int)

module Config = struct
  type t = unit

  let default = ()
end

type commit = {
  lane : int;
  pc : int;
  word : int option;
  dispatched : int option;
  written : int option;
  retired : int;
  dest : (int * int option) option;
  store : bool;
  trap : bool;
  charged : int;
}

type flight = { pc : int; word : int; cycle : int; charged : int }

let instance (c : commit) =
  {
    Instance.pc = c.pc;
    word = c.word;
    dispatched = c.dispatched;
    issued = None;
    retired = Some c.retired;
  }

module Event = struct
  type t = Commit of commit | In_flight of flight

  let dest =
    Jsont.Object.map ~kind:"dest" (fun reg value -> (reg, value))
    |> Jsont.Object.mem "reg" Jsont.int ~enc:fst
    |> Codec.opt snd "value" Jsont.int |> Jsont.Object.finish

  let commit =
    Codec.case "commits.commit"
      (fun c -> Commit c)
      (Jsont.Object.map (fun lane (i : Instance.t) written dest store trap charged ->
           {
             lane;
             pc = i.pc;
             word = i.word;
             dispatched = i.dispatched;
             written;
             retired = Option.get i.retired;
             dest;
             store;
             trap;
             charged;
           })
      |> Jsont.Object.mem "lane" Jsont.int ~enc:(fun (c : commit) -> c.lane)
      |> Jsont.Object.mem "instance" Instance.jsont ~enc:instance
      |> Codec.opt (fun (c : commit) -> c.written) "written" Jsont.int
      |> Codec.opt (fun (c : commit) -> c.dest) "dest" dest
      |> Jsont.Object.mem "store" Jsont.bool ~enc:(fun (c : commit) -> c.store)
      |> Jsont.Object.mem "trap" Jsont.bool ~enc:(fun (c : commit) -> c.trap)
      |> Jsont.Object.mem "charged" Jsont.int ~enc:(fun (c : commit) -> c.charged)
      |> Jsont.Object.finish)

  let in_flight =
    Codec.case "commits.in_flight"
      (fun f -> In_flight f)
      (Jsont.Object.map (fun pc word cycle charged -> { pc; word; cycle; charged })
      |> Jsont.Object.mem "pc" Jsont.int ~enc:(fun (f : flight) -> f.pc)
      |> Jsont.Object.mem "word" Jsont.int ~enc:(fun (f : flight) -> f.word)
      |> Jsont.Object.mem "dispatched" Jsont.int ~enc:(fun f -> f.cycle)
      |> Jsont.Object.mem "charged" Jsont.int ~enc:(fun (f : flight) -> f.charged)
      |> Jsont.Object.finish)

  let jsont =
    Codec.cases "commits.event"
      (function
        | Commit c -> Jsont.Object.Case.value commit c
        | In_flight f -> Jsont.Object.Case.value in_flight f)
      Jsont.Object.Case.[ make commit; make in_flight ]

  let cycle = function Commit c -> c.retired | In_flight f -> f.cycle
  let pc = function Commit c -> Some c.pc | In_flight f -> Some f.pc
end

type summary = {
  cycles : int;
  before : int;
  empty : int;
  unmatched_retires : int;
  skipped : int;
  missing_values : int;
  in_flight : int;
  pending : (int * int * int) list;
}

module Summary = struct
  type t = summary

  let pending =
    Jsont.Object.map ~kind:"pending" (fun pc word cycle -> (pc, word, cycle))
    |> Jsont.Object.mem "pc" Jsont.int ~enc:(fun (p, _, _) -> p)
    |> Jsont.Object.mem "word" Jsont.int ~enc:(fun (_, w, _) -> w)
    |> Jsont.Object.mem "dispatched" Jsont.int ~enc:(fun (_, _, c) -> c)
    |> Jsont.Object.finish

  let jsont =
    Codec.record "commits.summary"
      (fun cycles before empty unmatched_retires skipped missing_values in_flight pending ->
        { cycles; before; empty; unmatched_retires; skipped; missing_values; in_flight; pending })
    |> Jsont.Object.mem "cycles" Jsont.int ~enc:(fun s -> s.cycles)
    |> Jsont.Object.mem "before" Jsont.int ~enc:(fun s -> s.before)
    |> Jsont.Object.mem "empty" Jsont.int ~enc:(fun s -> s.empty)
    |> Jsont.Object.mem "unmatched_retires" Jsont.int ~enc:(fun s -> s.unmatched_retires)
    |> Jsont.Object.mem "skipped" Jsont.int ~enc:(fun s -> s.skipped)
    |> Jsont.Object.mem "missing_values" Jsont.int ~enc:(fun s -> s.missing_values)
    |> Jsont.Object.mem "in_flight" Jsont.int ~enc:(fun s -> s.in_flight)
    |> Jsont.Object.mem "pending" (Jsont.list pending) ~enc:(fun s -> s.pending)
    |> Jsont.Object.finish
end

type state = {
  queue : flight list;  (** Dispatch order, which is program order. *)
  values : (int * int) list IM.t;  (** Register -> (value, cycle), oldest first. *)
  sum : summary;
  started : bool;
}

let take_value st reg =
  match IM.find_opt reg st.values with
  | Some (v :: rest) -> (Some v, { st with values = IM.add reg rest st.values })
  | _ -> (None, st)

(* Oldest first; the instructions passed over are dropped. *)
let take_flight st pc =
  if List.exists (fun (f : flight) -> f.pc = pc) st.queue then
    let rec pop skipped = function
      | (f : flight) :: rest when f.pc = pc -> (f, skipped, rest)
      | _ :: rest -> pop (skipped + 1) rest
      | [] -> assert false
    in
    let f, skipped, queue = pop 0 st.queue in
    (Some f, { st with queue; sum = { st.sum with skipped = st.sum.skipped + skipped } })
  else (None, st)

let step ~no_write ~store st cycle
    ((dispatched : Core.dispatched list), (writes : Core.write list), retired) =
  let st = if dispatched <> [] then { st with started = true } else st in
  let st =
    {
      st with
      queue =
        (if dispatched = [] then st.queue
         else
           st.queue
           @ List.map
               (fun (d : Core.dispatched) -> { pc = d.d_pc; word = d.d_word; cycle; charged = 0 })
               dispatched);
      values =
        List.fold_left
          (fun values (w : Core.write) ->
            IM.update w.reg
              (fun q -> Some (Option.value q ~default:[] @ [ (w.value, cycle) ]))
              values)
          st.values writes;
    }
  in
  let st =
    match st.queue with
    | f :: rest -> { st with queue = { f with charged = f.charged + 1 } :: rest }
    | [] ->
        if st.started then { st with sum = { st.sum with empty = st.sum.empty + 1 } }
        else { st with sum = { st.sum with before = st.sum.before + 1 } }
  in
  let st = { st with sum = { st.sum with cycles = st.sum.cycles + 1 } } in
  let st, out =
    List.fold_left
      (fun (st, out) (r : Core.retired) ->
        let f, st = take_flight st r.r_pc in
        let st =
          if f = None then
            { st with sum = { st.sum with unmatched_retires = st.sum.unmatched_retires + 1 } }
          else st
        in
        let (dest, written), st =
          if r.r_idx = no_write || r.r_idx = store then ((None, None), st)
          else
            match take_value st r.r_idx with
            | Some (v, c), st -> ((Some (r.r_idx, Some v), Some c), st)
            | None, st ->
                ( (Some (r.r_idx, None), None),
                  { st with sum = { st.sum with missing_values = st.sum.missing_values + 1 } } )
        in
        let c =
          {
            lane = r.r_lane;
            pc = r.r_pc;
            word = Option.map (fun (f : flight) -> f.word) f;
            dispatched = Option.map (fun (f : flight) -> f.cycle) f;
            written;
            retired = cycle;
            dest;
            store = r.r_idx = store;
            trap = r.r_trap;
            charged = (match f with Some f -> f.charged | None -> 0);
          }
        in
        (st, Event.Commit c :: out))
      (st, []) retired
  in
  (st, List.rev out)

let summary_of st =
  {
    st.sum with
    in_flight = List.length st.queue;
    pending = List.map (fun (f : flight) -> (f.pc, f.word, f.cycle)) st.queue;
  }

let build () (c : _ Core.t) =
  let lanes l = Core.present c l in
  let input =
    let open Sig in
    let+ d = lanes (Core.dispatch c)
    and+ w = lanes (Core.writes c)
    and+ r = lanes (Core.retire c) in
    (d, w, r)
  in
  let no_write = Core.no_write c and store = Core.store c in
  let zero =
    {
      cycles = 0;
      before = 0;
      empty = 0;
      unmatched_retires = 0;
      skipped = 0;
      missing_values = 0;
      in_flight = 0;
      pending = [];
    }
  in
  let out, st =
    Machine.run
      {
        name;
        init = { queue = []; values = IM.empty; sum = zero; started = false };
        step = (fun ~tick st i -> step ~no_write ~store st tick.index i);
        finish = (fun st -> List.map (fun f -> Event.In_flight f) st.queue);
        every_tick = true;
      }
      input
  in
  (out, fun _ -> summary_of (Sig.peek st))

type 'c Core.dep += Shared of ((Event.t list, 'c) Ev.t * (Sched.run_stats -> summary))

let shared c =
  Analysis.shared c name
    ~inj:(fun x -> Shared x)
    ~prj:(function Shared x -> Some x | _ -> None)
    (fun () -> build () c)

let commits = List.filter_map (function Event.Commit c -> Some c | In_flight _ -> None)

let events c =
  let out, summary = shared c in
  (Ev.filter (( <> ) []) (Ev.map commits out), summary)

let text (ctx : Text.ctx) events (s : Summary.t) =
  let shown = ref 0 in
  let disasm w = match w with Some w -> ctx.disasm w | None -> "?" in
  let delta a b = match (a, b) with Some a, Some b -> string_of_int (b - a) | _ -> "-" in
  let commits = commits events in
  List.iter
    (fun (c : commit) ->
      if Text.selected ctx.window ~cycle:c.retired ~pc:c.pc && !shown < ctx.limit then begin
        incr shown;
        Printf.printf "%8d %d %08x %s %-32s %-16s %3s %3s %3d%s\n" c.retired c.lane c.pc
          (match c.word with Some w -> Printf.sprintf "%08x" w | None -> "????????")
          (disasm c.word)
          (match c.dest with
          | Some (r, Some v) -> Printf.sprintf "%s=%08x" (Core.reg_name r) v
          | Some (r, None) -> Core.reg_name r ^ "=?"
          | None -> if c.store then "store" else "")
          (delta c.dispatched (Some c.retired))
          (delta c.dispatched c.written) c.charged
          (if c.trap then "  TRAP" else "")
      end)
    commits;
  Printf.printf
    "root %s: %d cycles, %d before the first dispatch, %d later with nothing in flight; %d retires \
     without dispatch, %d dispatches skipped, %d values missing, %d in flight at the end\n"
    ctx.root s.cycles s.before s.empty s.unmatched_retires s.skipped s.missing_values s.in_flight;
  if s.pending <> [] then begin
    Printf.printf "in flight at the end, oldest first:\n";
    List.iter
      (fun (pc, word, cycle) ->
        Printf.printf "  dispatched %8d pc %08x %08x %s\n" cycle pc word (disasm (Some word)))
      s.pending
  end;
  if ctx.profile > 0 then begin
    (* The word of a PC is its first retirement's. *)
    let words =
      List.fold_left
        (fun m (c : commit) -> if IM.mem c.pc m then m else IM.add c.pc c.word m)
        IM.empty commits
    in
    Printf.printf "%8s %6s %7s %6s %8s  %s\n" "pc" "count" "cycles" "share" "d->r" "instruction";
    Profile.by_pc ~buckets:256
      ~pc:(fun (c : commit) -> Some c.pc)
      ~weight:(fun (c : commit) -> c.charged)
      ~total:(fun (c : commit) -> match c.dispatched with Some x -> c.retired - x | None -> 0)
      (List.to_seq commits)
    |> List.iteri (fun i (r : int Profile.row) ->
        if i < ctx.profile then
          Printf.printf "%08x %6d %7d %5.1f%% %8.2f  %s\n" r.key r.count r.weight
            (100. *. float r.weight /. float (max 1 s.cycles))
            (float r.total /. float r.count)
            (disasm (IM.find r.key words)))
  end
