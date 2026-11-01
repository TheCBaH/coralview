[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

type window = { first : int; last : int; pcs : int list }

let everything = { first = 0; last = max_int; pcs = [] }
let windowed w = w <> everything

let describe w =
  Printf.sprintf "window [%d, %s]%s" w.first
    (if w.last = max_int then "end" else string_of_int w.last)
    (if w.pcs = [] then "" else " pc " ^ String.concat "," (List.map (Printf.sprintf "%08x") w.pcs))

let selected w ~cycle ~pc = cycle >= w.first && cycle <= w.last && (w.pcs = [] || List.mem pc w.pcs)

type ctx = {
  root : string;
  disasm : int -> string;
  instruction_class : int -> string;
  by_class : bool;
  region : Region.t;
  window : window;
  limit : int;
  profile : int;
}

let stats (s : Hwfrp.Reduce.Stats.t) =
  if s.n = 0 then "-" else Printf.sprintf "%d/%.1f/%d" s.min (Hwfrp.Reduce.Stats.mean s) s.max
