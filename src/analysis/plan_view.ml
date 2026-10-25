[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

type signal = {
  width : int;
  var_type : string;
  origins : string list;
  aliases : string list list;
  provenance : (string * string) list;
}

let of_entry (e : Hwfrp.Capture.entry) =
  {
    width = e.width;
    var_type = Vcd.string_of_var_type e.var_type;
    origins = e.origins;
    aliases = List.map Vcd_types.Reference.to_list e.aliases;
    provenance = e.provenance;
  }

let provenance_jsont =
  Jsont.Object.map ~kind:"provenance" (fun model purpose -> (model, purpose))
  |> Jsont.Object.mem "model" Jsont.string ~enc:fst
  |> Jsont.Object.mem "purpose" Jsont.string ~enc:snd
  |> Jsont.Object.finish

let signal_jsont =
  Codec.record "plan.signal" (fun width var_type origins aliases provenance ->
      { width; var_type; origins; aliases; provenance })
  |> Jsont.Object.mem "width" Jsont.int ~enc:(fun s -> s.width)
  |> Jsont.Object.mem "var_type" Jsont.string ~enc:(fun s -> s.var_type)
  |> Jsont.Object.mem "origins" (Jsont.list Jsont.string) ~enc:(fun s -> s.origins)
  |> Jsont.Object.mem "aliases" (Jsont.list (Jsont.list Jsont.string)) ~enc:(fun s -> s.aliases)
  |> Jsont.Object.mem "provenance" (Jsont.list provenance_jsont) ~enc:(fun s -> s.provenance)
  |> Jsont.Object.finish

type summary = { signals : int; selected : int; origins : string list }

let summary_jsont =
  Codec.record "plan.summary" (fun signals selected origins -> { signals; selected; origins })
  |> Jsont.Object.mem "signals" Jsont.int ~enc:(fun s -> s.signals)
  |> Jsont.Object.mem "selected" Jsont.int ~enc:(fun s -> s.selected)
  |> Jsont.Object.mem "origins" (Jsont.list Jsont.string) ~enc:(fun s -> s.origins)
  |> Jsont.Object.finish
