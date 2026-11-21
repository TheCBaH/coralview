[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Hwfrp

type record = { cycle : int option; time : int64; path : string; width : int; value : Logic.t }

exception Missing of string
exception Stop

let model = "signals"

module Event = struct
  type sample = {
    phase : string;
    cycle : int option;
    time : int64;
    path : string;
    width : int;
    value : string;
  }

  type t = Sample of sample

  let body m =
    m
    |> Jsont.Object.mem "phase" Jsont.string ~enc:(fun s -> s.phase)
    |> Codec.opt (fun s -> s.cycle) "cycle" Jsont.int
    |> Jsont.Object.mem "time" Jsont.int64 ~enc:(fun s -> s.time)
    |> Jsont.Object.mem "path" Jsont.string ~enc:(fun s -> s.path)
    |> Jsont.Object.mem "width" Jsont.int ~enc:(fun s -> s.width)
    |> Jsont.Object.mem "value" Jsont.string ~enc:(fun s -> s.value)
    |> Jsont.Object.finish

  let make phase cycle time path width value = { phase; cycle; time; path; width; value }
  let json = body (Jsont.Object.map ~kind:"sample" make)
  let sample = Codec.case "signals.sample" (fun s -> Sample s) json

  let jsont =
    Codec.cases "signals.event"
      (fun (Sample s) -> Jsont.Object.Case.value sample s)
      Jsont.Object.Case.[ make sample ]
end

module Summary = struct
  type t = { samples : int }

  let jsont =
    Codec.record "signals.summary" (fun samples -> { samples })
    |> Jsont.Object.mem "samples" Jsont.int ~enc:(fun s -> s.samples)
    |> Jsont.Object.finish
end

let sample_rule_name : Trace.sample_rule -> string = function
  | After_falling -> "after_falling"
  | Before_rising -> "before_rising"
  | After_rising -> "after_rising"

let components path = List.filter (( <> ) "") (String.split_on_char '/' path)
let same (a : Logic.t) (b : Logic.t) = Bits.equal a.bits b.bits && Bits.equal a.unknown b.unknown

let to_string (v : Logic.t) =
  if Logic.is_known v then "0x" ^ Bits.to_hex v.bits else "0b" ^ Logic.to_string v

let sample ~phase (r : record) =
  {
    Event.phase;
    cycle = r.cycle;
    time = r.time;
    path = r.path;
    width = r.width;
    value = to_string r.value;
  }

let require tr paths =
  List.iter
    (fun path ->
      if
        components path = []
        || Trace.lookup tr (Vcd_types.Reference.of_list (components path)) = None
      then raise (Missing path))
    paths

let bind_paths (c : _ Core.t) tr paths =
  List.map
    (fun path ->
      match List.rev (components path) with
      | [] -> raise (Missing path)
      | name :: up ->
          let sc = Bind.root c.net tr c.clk ~model (Vcd_types.Reference.of_list (List.rev up)) in
          Bind.signal sc name Bind.logic ~purpose:"requested signal")
    paths

let net (p : Platform.t) tr paths =
  require tr paths;
  let (Core.Any c) = Core.bind p tr ~model in
  ignore (bind_paths c tr paths);
  c.net

let sampled ?gate (p : Platform.t) tr paths ~from ~until ~changes f =
  require tr paths;
  let (Core.Any c) = Core.bind p tr ~model in
  let values = bind_paths c tr paths in
  let now =
    let open Sig in
    let+ vs = all values and+ cycle = cycle c.clk and+ time = time c.clk in
    (cycle, Vcd_types.Timestamp.to_int64 time, vs)
  in
  let previous = ref [] in
  Ev.subscribe
    (Ev.when_ (Sig.const c.clk true) now)
    (fun (cycle, time, vs) ->
      if cycle > until then raise Stop;
      if cycle >= from then begin
        let rec emit paths vs before =
          match (paths, vs) with
          | path :: paths, (v : Logic.t) :: vs ->
              let same, before =
                match before with b :: before -> (same b v, before) | [] -> (false, [])
              in
              if not (changes && same) then
                f { cycle = Some cycle; time; path; width = Logic.width v; value = v };
              emit paths vs before
          | _ -> ()
        in
        emit paths vs (if cycle = from then [] else !previous)
      end;
      previous := vs);
  (try ignore (Core.run ?gate c : Sched.run_stats) with Stop -> ());
  Seq.iter
    (fun (d : Diag.t) ->
      if d.code = "signal.undecodable" then
        let name (r : Vcd_types.Reference.t) =
          match List.find_opt (fun p -> components p = Vcd_types.Reference.to_list r) paths with
          | Some p -> p
          | None -> Vcd_types.Reference.to_string r
        in
        Format.eprintf "%s: %s@." (String.concat "," (List.map name d.paths)) d.message)
    (Diag.stream c.net)

(* Only the selected IDs of the full stream are read. Where the file is an FST, the full scan up to
   [from] is skipped when every wanted ID has changed before the block that holds [from]: the frame
   then gives the values the scan would have held. A frame also holds IDs the stream has not assigned
   yet, which the full scan would print at their first change, so otherwise the scan continues. *)
let raw ?path tr paths ~from ~until ~changes f =
  let wanted =
    List.map
      (fun path ->
        match Trace.find tr (components path) with
        | Some s -> (path, s)
        | None -> raise (Missing path))
      paths
  in
  let by_id = Hashtbl.create 16 in
  List.iter
    (fun ((_, (s : Trace.signal)) as w) ->
      let k = Vcd_types.ID.to_string s.id in
      Hashtbl.replace by_id k (w :: Option.value (Hashtbl.find_opt by_id k) ~default:[]))
    (List.rev wanted);
  let last = Hashtbl.create 16 and undecodable = Hashtbl.create 4 in
  let time = ref 0L in
  let decode path (s : Trace.signal) v =
    match Logic.of_value ~width:s.width v with
    | Ok value -> value
    | Error e ->
        if not (Hashtbl.mem undecodable path) then begin
          Hashtbl.replace undecodable path ();
          Format.eprintf "%s: %a; read as unknown@." path Logic.pp_decode_error e
        end;
        Logic.unknown s.width
  in
  let handle = function
    | Vcd_ast.Timestamp t ->
        time := Vcd_types.Timestamp.to_int64 t;
        if Int64.compare !time until > 0 then raise Stop
    | Change (id, v) -> (
        match Hashtbl.find_opt by_id (Vcd_types.ID.to_string id) with
        | None -> ()
        | Some ws ->
            List.iter
              (fun (path, (s : Trace.signal)) ->
                let value = decode path s v in
                let same =
                  match Hashtbl.find_opt last path with Some b -> same b value | None -> false
                in
                Hashtbl.replace last path value;
                if Int64.compare !time from >= 0 && not (changes && same) then
                  f { cycle = None; time = !time; path; width = s.width; value })
              ws)
    | _ -> ()
  in
  (* The stream stands in for the scan only if it starts before [from]: a block can start at a timestamp
     whose changes are in the block before, so those changes are in [state] and not in the stream. *)
  let resume events state resumed =
    match (Vcd.ID_map.is_empty state, resumed ()) with
    | false, Seq.Cons ((Vcd_ast.Timestamp t0 as first), rest) ->
        let t0_ = Vcd_types.Timestamp.to_int64 t0 in
        if Int64.compare t0_ from >= 0 then `Earlier
        else begin
          let unseen = Hashtbl.create 16 in
          Hashtbl.iter (fun k _ -> Hashtbl.replace unseen k ()) by_id;
          let rec prefix seq =
            match seq () with
            | Seq.Nil -> ()
            | Cons (Vcd_ast.Timestamp t, _) as node
              when Int64.compare (Vcd_types.Timestamp.to_int64 t) t0_ >= 0 ->
                Seq.iter handle (fun () -> node)
            | Cons (e, seq) ->
                handle e;
                (match e with
                | Change (id, _) -> Hashtbl.remove unseen (Vcd_types.ID.to_string id)
                | _ -> ());
                if Hashtbl.length unseen = 0 then begin
                  List.iter
                    (fun (path, (s : Trace.signal)) ->
                      match Vcd.Stateful.find state s.id with
                      | Some v -> Hashtbl.replace last path (decode path s v)
                      | None -> ())
                    wanted;
                  Seq.iter handle (Seq.cons first rest)
                end
                else prefix seq
          in
          prefix events;
          `Done
        end
    | _ -> `Full
  in
  try
    let events = Trace.events tr in
    let rec seek time tries =
      match path with
      | Some path when Int64.compare time 0L > 0 && tries > 0 -> (
          match
            Hwfrp_native.with_seek
              ~select:(fun id -> Hashtbl.mem by_id (Vcd_types.ID.to_string id))
              path ~time (resume events)
          with
          | Some `Earlier -> seek (Int64.pred time) (tries - 1)
          | Some `Done -> ()
          | Some `Full | None -> Seq.iter handle events)
      | _ -> Seq.iter handle events
    in
    seek from 8
  with Stop -> ()

let header (p : Platform.t) =
  Printf.printf "# sampled %s on %s at %s\n" (sample_rule_name p.sample) p.clock
    (Vcd_types.Reference.to_string (Platform.root p))

let row (r : record) =
  Printf.printf "%8s %10Ld %4d %s %s\n"
    (match r.cycle with Some c -> string_of_int c | None -> "-")
    r.time r.width r.path (to_string r.value)
