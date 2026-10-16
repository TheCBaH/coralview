[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Hwfrp

type record = { cycle : int option; time : int64; path : string; width : int; value : Logic.t }

exception Missing of string
exception Stop

let model = "signals"

let sample_rule_name : Trace.sample_rule -> string = function
  | After_falling -> "after_falling"
  | Before_rising -> "before_rising"
  | After_rising -> "after_rising"

let components path = List.filter (( <> ) "") (String.split_on_char '/' path)
let same (a : Logic.t) (b : Logic.t) = Bits.equal a.bits b.bits && Bits.equal a.unknown b.unknown

let to_string (v : Logic.t) =
  if Logic.is_known v then "0x" ^ Bits.to_hex v.bits else "0b" ^ Logic.to_string v

let require tr paths =
  List.iter
    (fun path ->
      if
        components path = []
        || Trace.lookup tr (Vcd_types.Reference.of_list (components path)) = None
      then raise (Missing path))
    paths

let sampled (p : Platform.t) tr paths ~from ~until ~changes f =
  require tr paths;
  let (Core.Any c) = Core.bind p tr ~model in
  let values =
    List.map
      (fun path ->
        match List.rev (components path) with
        | [] -> raise (Missing path)
        | name :: up ->
            let sc = Bind.root c.net tr c.clk ~model (Vcd_types.Reference.of_list (List.rev up)) in
            Bind.signal sc name Bind.logic ~purpose:"requested signal")
      paths
  in
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
        let before = if cycle = from then [] else !previous in
        List.iteri
          (fun i (path, (v : Logic.t)) ->
            let same = match List.nth_opt before i with Some b -> same b v | None -> false in
            if not (changes && same) then
              f { cycle = Some cycle; time; path; width = Logic.width v; value = v })
          (List.combine paths vs)
      end;
      previous := vs);
  try ignore (Core.run c : Sched.run_stats) with Stop -> ()

let raw tr paths ~from ~until ~changes f =
  let wanted =
    List.map
      (fun path ->
        match Trace.find tr (components path) with
        | Some s -> (path, s)
        | None -> raise (Missing path))
      paths
  in
  let last = Hashtbl.create 16 in
  let time = ref 0L in
  try
    Seq.iter
      (function
        | Vcd_ast.Timestamp t ->
            time := Vcd_types.Timestamp.to_int64 t;
            if Int64.compare !time until > 0 then raise Stop
        | Change (id, v) ->
            List.iter
              (fun (path, (s : Trace.signal)) ->
                if Vcd_types.ID.equal s.id id then
                  match Logic.of_value ~width:s.width v with
                  | Error e -> failwith (Format.asprintf "%s: %a" path Logic.pp_decode_error e)
                  | Ok value ->
                      let same =
                        match Hashtbl.find_opt last path with
                        | Some b -> same b value
                        | None -> false
                      in
                      Hashtbl.replace last path value;
                      if Int64.compare !time from >= 0 && not (changes && same) then
                        f { cycle = None; time = !time; path; width = s.width; value })
              wanted
        | _ -> ())
      (Trace.events tr)
  with Stop -> ()
