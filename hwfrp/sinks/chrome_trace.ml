[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

type event =
  | Span of { lane : string; name : string; start : int; stop : int; args : (string * Json.t) list }
  | Instant of { lane : string; name : string; at : int; args : (string * Json.t) list }
  | Counter of { name : string; at : int; value : int }

type process = { name : string; lanes : string list; events : event list }

let obj l = Json.Obj l

let render processes =
  let out = ref [] in
  let put j = out := Json.to_string j :: !out in
  List.iteri
    (fun i p ->
      let pid = i + 1 in
      put
        (obj
           [
             ("ph", Str "M");
             ("pid", Int pid);
             ("name", Str "process_name");
             ("args", obj [ ("name", Str p.name) ]);
           ]);
      let tids = Hashtbl.create 16 and next = ref 0 in
      let tid lane =
        match Hashtbl.find_opt tids lane with
        | Some n -> n
        | None ->
            incr next;
            Hashtbl.replace tids lane !next;
            put
              (obj
                 [
                   ("ph", Str "M");
                   ("pid", Int pid);
                   ("tid", Int !next);
                   ("name", Str "thread_name");
                   ("args", obj [ ("name", Str lane) ]);
                 ]);
            !next
      in
      List.iter (fun l -> ignore (tid l)) p.lanes;
      List.iter
        (function
          | Span { lane; name; start; stop; args } ->
              let tid = tid lane in
              put
                (obj
                   [
                     ("ph", Str "X");
                     ("pid", Int pid);
                     ("tid", Int tid);
                     ("name", Str name);
                     ("ts", Int start);
                     ("dur", Int (max 1 (stop - start + 1)));
                     ("args", obj args);
                   ])
          | Instant { lane; name; at; args } ->
              let tid = tid lane in
              put
                (obj
                   [
                     ("ph", Str "i");
                     ("s", Str "t");
                     ("pid", Int pid);
                     ("tid", Int tid);
                     ("name", Str name);
                     ("ts", Int at);
                     ("args", obj args);
                   ])
          | Counter { name; at; value } ->
              put
                (obj
                   [
                     ("ph", Str "C");
                     ("pid", Int pid);
                     ("name", Str name);
                     ("ts", Int at);
                     ("args", obj [ ("value", Int value) ]);
                   ]))
        p.events)
    processes;
  List.rev !out

let to_string ?(time_unit = "ns") processes =
  Printf.sprintf "{\"displayTimeUnit\":%s,\"traceEvents\":[\n%s\n]}\n"
    (Json.to_string (Str time_unit))
    (String.concat ",\n" (render processes))

let output oc ?time_unit processes =
  output_string oc (to_string ?time_unit processes);
  flush oc

let occupancy ~name intervals ~last =
  let deltas =
    List.concat_map
      (fun (start, stop) -> [ (start, 1); (Option.value stop ~default:last + 1, -1) ])
      intervals
    |> List.sort compare
  in
  let rec go level acc = function
    | [] -> List.rev acc
    | (t, d) :: rest ->
        let level = level + d in
        let acc =
          match acc with
          | Counter { at; _ } :: tl when at = t -> Counter { name; at = t; value = level } :: tl
          | _ -> Counter { name; at = t; value = level } :: acc
        in
        go level acc rest
  in
  go 0 [] deltas
