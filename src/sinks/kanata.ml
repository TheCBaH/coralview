[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

type stage = { name : string; lane : int; start : int; stop : int }

type insn = {
  label : string;
  detail : string option;
  stages : stage list;
  retired : int option;
  flushed : int option;
}

module Lines = Map.Make (struct
  type t = int * int

  let compare = compare
end)

module Writer = struct
  type t = {
    put : string -> unit;
    mutable pending : string Lines.t;  (** By cycle, then by the order the lines were made. *)
    mutable seq : int;
    mutable id : int;
    mutable rid : int;
    mutable mark : int;
    mutable now : int option;  (** The cycle of the last line written. *)
  }

  let create put =
    put "Kanata\t0004\n";
    { put; pending = Lines.empty; seq = 0; id = 0; rid = 0; mark = min_int; now = None }

  let emit w cycle line =
    (match w.now with
    | None ->
        w.put (Printf.sprintf "C=\t%d\n" cycle);
        w.now <- Some cycle
    | Some now when cycle > now ->
        w.put (Printf.sprintf "C\t%d\n" (cycle - now));
        w.now <- Some cycle
    | Some _ -> ());
    w.put line;
    w.put "\n"

  let flush_before w limit =
    let rec go () =
      match Lines.min_binding_opt w.pending with
      | Some (((cycle, _) as key), line) when cycle < limit ->
          w.pending <- Lines.remove key w.pending;
          emit w cycle line;
          go ()
      | _ -> ()
    in
    go ()

  let advance w watermark =
    if watermark > w.mark then begin
      w.mark <- watermark;
      flush_before w watermark
    end

  let add w i =
    let id = w.id in
    w.id <- id + 1;
    match i.stages with
    | [] -> ()
    | first :: _ ->
        if first.start < w.mark then
          invalid_arg
            (Printf.sprintf "Kanata.Writer.add: instruction %d starts at cycle %d, before cycle %d"
               id first.start w.mark);
        let at cycle line =
          w.seq <- w.seq + 1;
          w.pending <- Lines.add (cycle, w.seq) line w.pending
        in
        at first.start (Printf.sprintf "I\t%d\t%d\t0" id id);
        at first.start (Printf.sprintf "L\t%d\t0\t%s" id i.label);
        Option.iter (fun d -> at first.start (Printf.sprintf "L\t%d\t1\t%s" id d)) i.detail;
        List.iter
          (fun s ->
            at s.start (Printf.sprintf "S\t%d\t%d\t%s" id s.lane s.name);
            at (s.stop + 1) (Printf.sprintf "E\t%d\t%d\t%s" id s.lane s.name))
          i.stages;
        Option.iter
          (fun r ->
            at r (Printf.sprintf "R\t%d\t%d\t0" id w.rid);
            w.rid <- w.rid + 1)
          i.retired;
        Option.iter (fun c -> at c (Printf.sprintf "R\t%d\t%d\t1" id w.rid)) i.flushed

  let finish w = flush_before w max_int
end

let write oc insns =
  let w = Writer.create (output_string oc) in
  Seq.iter
    (fun i ->
      (match i.stages with first :: _ -> Writer.advance w first.start | [] -> ());
      Writer.add w i)
    insns;
  Writer.finish w;
  flush oc

module Builder = struct
  module Spans = Map.Make (struct
    type t = int * int

    let compare = compare
  end)

  type t = {
    disasm : int -> string;
    writer : Writer.t;
    mutable stalled : (int * string) Spans.t;  (** By stop, then PC. *)
    mutable last : int;
    mutable in_flight : Commits.Event.t list;  (** Latest first. *)
    mutable dispatch : int;
        (** The latest dispatch cycle seen, and the two distinct ones before it. *)
    mutable before : int;
    mutable before2 : int;
  }

  let create ~disasm writer =
    {
      disasm;
      writer;
      stalled = Spans.empty;
      last = 0;
      in_flight = [];
      dispatch = -1;
      before = -1;
      before2 = -1;
    }

  let stall t (Stalls.Event.Stall_span x) =
    match (x.reason, x.span.stop) with
    | (Stalls.Dispatched | Empty), _ | _, None -> ()
    | r, Some stop ->
        t.stalled <- Spans.add (stop, x.pc) (x.span.start, Stalls.reason_name r) t.stalled

  let insn t ~pc ~word ~dispatched ~retired =
    let stall, reason =
      match Spans.find_opt (dispatched - 1, pc) t.stalled with
      | Some (start, reason) ->
          ([ { name = "St"; lane = 1; start; stop = dispatched - 1 } ], Some reason)
      | None -> ([], None)
    in
    let ex_stop = match retired with Some r -> max dispatched (r - 1) | None -> t.last in
    {
      label = Printf.sprintf "%08x %s" pc (match word with Some w -> t.disasm w | None -> "?");
      detail = Option.map (fun r -> "stalled: " ^ r) reason;
      stages = stall @ [ { name = "Ex"; lane = 0; start = dispatched; stop = ex_stop } ];
      retired;
      flushed = (if retired = None then Some (t.last + 1) else None);
    }

  (* Dispatch is in order, so the dispatch cycles of the instructions that arrive never go back. A stall
     span is a run in one lane, and a dispatch moves every instruction behind it to another lane, so the
     span that ends the cycle before an instruction dispatches began after the second dispatch cycle
     before that: no instruction to come has a line before the third latest dispatch cycle seen. *)
  let commit t = function
    | Commits.Event.Commit c -> (
        t.last <- max t.last c.retired;
        match c.dispatched with
        | None -> ()
        | Some d ->
            if d > t.dispatch then begin
              t.before2 <- t.before;
              t.before <- t.dispatch;
              t.dispatch <- d
            end;
            let rec prune () =
              match Spans.min_binding_opt t.stalled with
              | Some (((stop, _) as key), _) when stop < t.dispatch - 1 ->
                  t.stalled <- Spans.remove key t.stalled;
                  prune ()
              | _ -> ()
            in
            prune ();
            Writer.add t.writer
              (insn t ~pc:c.pc ~word:c.word ~dispatched:d ~retired:(Some c.retired));
            Writer.advance t.writer (t.before2 + 1))
    | In_flight f as e ->
        t.last <- max t.last f.cycle;
        t.in_flight <- e :: t.in_flight

  let finish t =
    List.iter
      (function
        | Commits.Event.In_flight f ->
            Writer.add t.writer
              (insn t ~pc:f.pc ~word:(Some f.word) ~dispatched:f.cycle ~retired:None)
        | Commit _ -> ())
      (List.rev t.in_flight);
    Writer.finish t.writer
end
