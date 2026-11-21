[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

type opts = {
  region : Region.t;
  features : string option;
  window : Text.window;
  limit : int;
  profile : int;
  at : int option;
  beats : int;
  ops : Ops.Config.t;
}

let default =
  {
    region = Region.none;
    features = None;
    window = Text.everything;
    limit = max_int;
    profile = 0;
    at = None;
    beats = 0;
    ops = Ops.Config.default;
  }

type t =
  | M : {
      a : (module Analysis.S with type Config.t = 'k and type Event.t = 'e and type Summary.t = 's);
      cfg : opts -> 'k;
      text : opts -> Text.ctx -> Format.formatter -> (unit -> 's) -> 'e Text.sink;
      status : 's -> int;
      profile : (Text.ctx -> Format.formatter -> (unit -> 's) -> 'e Text.sink) option;
      perfetto : (Text.ctx -> 'e Seq.t -> 's -> Perfetto.process) option;
      commit : ('e -> Commits.commit option) option;
    }
      -> t

let plain text _ = text
let ok _ = 0

let all =
  [
    M
      {
        a = (module Commits);
        cfg = (fun _ -> ());
        text = plain Commits.text;
        status = ok;
        profile = Some Commits.profile;
        perfetto = None;
        commit = Some (function Commits.Event.Commit c -> Some c | In_flight _ -> None);
      };
    M
      {
        a = (module Stalls);
        cfg = (fun _ -> ());
        text = plain Stalls.text;
        status = ok;
        profile = Some Stalls.profile;
        perfetto = Some Stalls.perfetto;
        commit = None;
      };
    M
      {
        a = (module Memory);
        cfg = (fun o -> { region = o.region });
        text = plain Memory.text;
        status = ok;
        profile = None;
        perfetto = None;
        commit = None;
      };
    M
      {
        a = (module Axi);
        cfg = (fun o -> { region = o.region });
        text = plain Axi.text;
        status = ok;
        profile = Some Axi.profile;
        perfetto = Some Axi.perfetto;
        commit = None;
      };
    M
      {
        a = (module Dma);
        cfg = (fun o -> { region = o.region });
        text = (fun o -> Dma.text ~beats:o.beats);
        status = ok;
        profile = None;
        perfetto = Some Dma.perfetto;
        commit = None;
      };
    M
      {
        a = (module Registers);
        cfg = (fun o -> { at = o.at });
        text = plain Registers.text;
        status = Registers.status;
        profile = None;
        perfetto = None;
        commit = None;
      };
    M
      {
        a = (module Tiles);
        cfg = (fun _ -> ());
        text = plain Tiles.text;
        status = ok;
        profile = None;
        perfetto = None;
        commit = None;
      };
    M
      {
        a = (module Ops);
        cfg = (fun o -> o.ops);
        text = plain Ops.text;
        status = ok;
        profile = Some Ops.profile;
        perfetto = Some Ops.perfetto;
        commit = None;
      };
    M
      {
        a = (module Traps);
        cfg = (fun _ -> ());
        text = plain Traps.text;
        status = ok;
        profile = None;
        perfetto = None;
        commit = None;
      };
    M
      {
        a = (module Vectors);
        cfg = (fun o -> { at = o.at });
        text = plain Vectors.text;
        status = Vectors.status;
        profile = None;
        perfetto = None;
        commit = None;
      };
  ]

let name (M { a = (module A); _ }) = A.name
let needs (M { a = (module A); _ }) = A.needs
let find n = List.find_opt (fun m -> name m = n) all

let available p =
  List.filter (fun m -> List.for_all (fun b -> List.mem b (Platform.blocks p)) (needs m)) all

let subscribe (M { a = (module A); _ }) c =
  ignore (Analysis.subscribe (module A) A.Config.default c ignore : Hwfrp.Sched.run_stats -> _)
