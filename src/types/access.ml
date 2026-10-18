[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

type t = { address : int; bytes : int; write : bool; region : string option }

let jsont =
  Jsont.Object.map ~kind:"access" (fun address bytes write region ->
      { address; bytes; write; region })
  |> Jsont.Object.mem "address" Jsont.int ~enc:(fun a -> a.address)
  |> Jsont.Object.mem "bytes" Jsont.int ~enc:(fun a -> a.bytes)
  |> Jsont.Object.mem "write" Jsont.bool ~enc:(fun a -> a.write)
  |> Codec.opt (fun a -> a.region) "region" Jsont.string
  |> Jsont.Object.finish
