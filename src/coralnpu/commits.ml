[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Hwfrp

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

let model = "commits"
let needs = [ "dispatch_debug"; "retirement_debug"; "regfile_writeback" ]

type flight = { pc : int; word : int; cycle : int; mutable charged : int }

type state = {
  queue : flight Queue.t;  (** dispatch order, which is program order *)
  values : (int, (int * int) Queue.t) Hashtbl.t;  (** register -> (value, cycle), oldest first *)
  mutable sum : summary;
  mutable started : bool;
}

let take_value st reg =
  match Hashtbl.find_opt st.values reg with
  | Some q when not (Queue.is_empty q) -> Some (Queue.pop q)
  | _ -> None

(* Oldest first; the instructions passed over are dropped. *)
let take_flight st pc =
  if Queue.fold (fun found f -> found || f.pc = pc) false st.queue then begin
    let rec pop () =
      let f = Queue.pop st.queue in
      if f.pc = pc then f
      else begin
        st.sum <- { st.sum with skipped = st.sum.skipped + 1 };
        pop ()
      end
    in
    Some (pop ())
  end
  else None

let step ~no_write ~store st cycle
    ((dispatched : Core.dispatched list), (writes : Core.write list), retired) =
  if dispatched <> [] then st.started <- true;
  List.iter
    (fun (d : Core.dispatched) ->
      Queue.push { pc = d.d_pc; word = d.d_word; cycle; charged = 0 } st.queue)
    dispatched;
  List.iter
    (fun (w : Core.write) ->
      let q =
        match Hashtbl.find_opt st.values w.reg with
        | Some q -> q
        | None ->
            let q = Queue.create () in
            Hashtbl.add st.values w.reg q;
            q
      in
      Queue.push (w.value, cycle) q)
    writes;
  (match Queue.peek_opt st.queue with
  | Some f -> f.charged <- f.charged + 1
  | None ->
      if st.started then st.sum <- { st.sum with empty = st.sum.empty + 1 }
      else st.sum <- { st.sum with before = st.sum.before + 1 });
  st.sum <- { st.sum with cycles = st.sum.cycles + 1 };
  List.map
    (fun (r : Core.retired) ->
      let f = take_flight st r.r_pc in
      if f = None then st.sum <- { st.sum with unmatched_retires = st.sum.unmatched_retires + 1 };
      let dest, written =
        if r.r_idx = no_write || r.r_idx = store then (None, None)
        else
          match take_value st r.r_idx with
          | Some (v, c) -> (Some (r.r_idx, Some v), Some c)
          | None ->
              st.sum <- { st.sum with missing_values = st.sum.missing_values + 1 };
              (Some (r.r_idx, None), None)
      in
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
      })
    retired

let events (c : _ Core.t) =
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
        name = model;
        init = { queue = Queue.create (); values = Hashtbl.create 64; sum = zero; started = false };
        step = (fun ~tick st i -> (st, step ~no_write ~store st tick.index i));
        finish = (fun _ -> []);
        every_tick = true;
      }
      input
  in
  let finish _ =
    let st = Sig.peek st in
    {
      st.sum with
      in_flight = Queue.length st.queue;
      pending = List.of_seq (Seq.map (fun f -> (f.pc, f.word, f.cycle)) (Queue.to_seq st.queue));
    }
  in
  (out, finish)

let graph c f =
  let out, finish = events c in
  Ev.subscribe out (List.iter f);
  finish

let run p tr f =
  let (Core.Any c) = Core.bind p tr ~model in
  let finish = graph c f in
  finish (Core.run c)
