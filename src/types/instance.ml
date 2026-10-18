[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

type t = {
  pc : int;
  word : int option;
  dispatched : int option;
  issued : int option;
  retired : int option;
}

let jsont =
  Jsont.Object.map ~kind:"instance" (fun pc word dispatched issued retired ->
      { pc; word; dispatched; issued; retired })
  |> Jsont.Object.mem "pc" Jsont.int ~enc:(fun i -> i.pc)
  |> Codec.opt (fun i -> i.word) "word" Jsont.int
  |> Codec.opt (fun i -> i.dispatched) "dispatched" Jsont.int
  |> Codec.opt (fun i -> i.issued) "issued" Jsont.int
  |> Codec.opt (fun i -> i.retired) "retired" Jsont.int
  |> Jsont.Object.finish
