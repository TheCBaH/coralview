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

let write oc insns =
  let lines = ref [] and seq = ref 0 in
  let at cycle line =
    incr seq;
    lines := (cycle, !seq, line) :: !lines
  in
  let rid = ref 0 in
  List.iteri
    (fun id i ->
      match i.stages with
      | [] -> ()
      | first :: _ ->
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
              at r (Printf.sprintf "R\t%d\t%d\t0" id !rid);
              incr rid)
            i.retired;
          Option.iter (fun c -> at c (Printf.sprintf "R\t%d\t%d\t1" id !rid)) i.flushed)
    insns;
  let lines = List.sort compare !lines in
  output_string oc "Kanata\t0004\n";
  (match lines with (c, _, _) :: _ -> Printf.fprintf oc "C=\t%d\n" c | [] -> ());
  ignore
    (List.fold_left
       (fun now (c, _, line) ->
         if c > now then Printf.fprintf oc "C\t%d\n" (c - now);
         output_string oc line;
         output_char oc '\n';
         max now c)
       (match lines with (c, _, _) :: _ -> c | [] -> 0)
       lines);
  flush oc

let of_run ~disasm commits stalls =
  let stalled = Hashtbl.create 1024 in
  List.iter
    (fun (Stalls.Event.Stall_span x) ->
      match (x.reason, x.span.stop) with
      | (Stalls.Dispatched | Empty), _ | _, None -> ()
      | r, Some stop -> Hashtbl.replace stalled (x.pc, stop) (x.span.start, Stalls.reason_name r))
    stalls;
  let last =
    List.fold_left
      (fun m -> function Commits.Event.Commit c -> max m c.retired | In_flight f -> max m f.cycle)
      0 commits
  in
  let insn ~pc ~word ~dispatched ~retired =
    let st =
      match Hashtbl.find_opt stalled (pc, dispatched - 1) with
      | Some (start, reason) ->
          ([ { name = "St"; lane = 1; start; stop = dispatched - 1 } ], Some reason)
      | None -> ([], None)
    in
    let stall, reason = st in
    let ex_stop = match retired with Some r -> max dispatched (r - 1) | None -> last in
    {
      label = Printf.sprintf "%08x %s" pc (match word with Some w -> disasm w | None -> "?");
      detail = Option.map (fun r -> "stalled: " ^ r) reason;
      stages = stall @ [ { name = "Ex"; lane = 0; start = dispatched; stop = ex_stop } ];
      retired;
      flushed = (if retired = None then Some (last + 1) else None);
    }
  in
  List.filter_map
    (function
      | Commits.Event.Commit c ->
          Option.map
            (fun d -> insn ~pc:c.pc ~word:c.word ~dispatched:d ~retired:(Some c.retired))
            c.dispatched
      | In_flight f -> Some (insn ~pc:f.pc ~word:(Some f.word) ~dispatched:f.cycle ~retired:None))
    commits
