[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

module C = Hwfrp_sinks.Chrome_trace

type slice = {
  track : string;
  name : string;
  start : int;
  stop : int;
  args : (string * string) list;
}

type counter = { c_track : string; cycle : int; value : int }
type process = { process : string; slices : slice list; counters : counter list }

let to_events p =
  List.map
    (fun s ->
      C.Span
        {
          lane = s.track;
          name = s.name;
          start = s.start;
          stop = s.stop;
          args = List.map (fun (k, v) -> (k, Hwfrp_sinks.Json.Str v)) s.args;
        })
    p.slices
  @ List.map (fun c -> C.Counter { name = c.c_track; at = c.cycle; value = c.value }) p.counters

let write oc processes =
  C.output oc
    (List.map (fun p -> { C.name = p.process; lanes = []; events = to_events p }) processes)

let occupancy ~track intervals ~last =
  List.filter_map
    (function
      | C.Counter { at; value; _ } -> Some { c_track = track; cycle = at; value } | _ -> None)
    (C.occupancy ~name:track intervals ~last)
