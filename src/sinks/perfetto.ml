[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

type slice = {
  track : string;
  name : string;
  start : int;
  stop : int;
  args : (string * string) list;
}

type counter = { c_track : string; cycle : int; value : int }
type process = { process : string; slices : slice list; counters : counter list }

let str s = Jsont.Json.string s
let int n = Jsont.Json.int n
let obj l = Jsont.Json.object' (List.map (fun (k, v) -> Jsont.Json.mem (Jsont.Json.name k) v) l)

let write oc processes =
  let first = ref true in
  let put j =
    output_string oc (if !first then "\n" else ",\n");
    first := false;
    output_string oc (Codec.to_line Jsont.json j)
  in
  output_string oc "{\"displayTimeUnit\":\"ns\",\"traceEvents\":[";
  List.iteri
    (fun i p ->
      let pid = i + 1 in
      put
        (obj
           [
             ("ph", str "M");
             ("pid", int pid);
             ("name", str "process_name");
             ("args", obj [ ("name", str p.process) ]);
           ]);
      let tids = Hashtbl.create 16 and next = ref 0 in
      let tid t =
        match Hashtbl.find_opt tids t with
        | Some n -> n
        | None ->
            incr next;
            Hashtbl.replace tids t !next;
            put
              (obj
                 [
                   ("ph", str "M");
                   ("pid", int pid);
                   ("tid", int !next);
                   ("name", str "thread_name");
                   ("args", obj [ ("name", str t) ]);
                 ]);
            !next
      in
      List.iter
        (fun s ->
          let tid = tid s.track in
          put
            (obj
               [
                 ("ph", str "X");
                 ("pid", int pid);
                 ("tid", int tid);
                 ("name", str s.name);
                 ("ts", int s.start);
                 ("dur", int (s.stop - s.start + 1));
                 ("args", obj (List.map (fun (k, v) -> (k, str v)) s.args));
               ]))
        p.slices;
      List.iter
        (fun c ->
          put
            (obj
               [
                 ("ph", str "C");
                 ("pid", int pid);
                 ("name", str c.c_track);
                 ("ts", int c.cycle);
                 ("args", obj [ ("value", int c.value) ]);
               ]))
        p.counters)
    processes;
  output_string oc "\n]}\n";
  flush oc

let occupancy ~track intervals ~last =
  let deltas =
    List.concat_map
      (fun (start, stop) -> [ (start, 1); (Option.value stop ~default:last + 1, -1) ])
      intervals
    |> List.sort compare
  in
  let rec go level acc = function
    | [] -> List.rev acc
    | (c, d) :: rest ->
        let level = level + d in
        let acc =
          match acc with
          | { cycle; _ } :: tl when cycle = c -> { c_track = track; cycle = c; value = level } :: tl
          | _ -> { c_track = track; cycle = c; value = level } :: acc
        in
        go level acc rest
  in
  go 0 [] deltas
