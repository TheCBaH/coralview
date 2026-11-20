[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

open Hwfrp

let relation =
  Jsont.Object.map ~kind:"relation" (fun code comparisons failures -> (code, comparisons, failures))
  |> Jsont.Object.mem "code" Jsont.string ~enc:(fun (c, _, _) -> c)
  |> Jsont.Object.mem "comparisons" Jsont.int ~enc:(fun (_, n, _) -> n)
  |> Jsont.Object.mem "failures" Jsont.int ~enc:(fun (_, _, f) -> f)
  |> Jsont.Object.finish

let reg value =
  Jsont.Object.map ~kind:"register" (fun reg value -> (reg, value))
  |> Jsont.Object.mem "reg" Jsont.int ~enc:fst
  |> Jsont.Object.mem "value" value ~enc:snd
  |> Jsont.Object.finish

let at value =
  Jsont.Object.map ~kind:"storage_at" (fun cycle storage -> (cycle, storage))
  |> Jsont.Object.mem "cycle" Jsont.int ~enc:fst
  |> Jsont.Object.mem "storage" (Jsont.list (reg value)) ~enc:snd
  |> Jsont.Object.finish

let relations (c : _ Core.t) ~model comparisons =
  List.map (fun (code, n) -> (code, n, Diag.count c.net ~source:model ~code)) comparisons

let failures (c : _ Core.t) ~model ~codes =
  Diag.stream c.net
  |> Seq.filter (fun (d : Diag.t) -> d.source = model && List.mem d.code codes)
  |> Seq.take 20 |> List.of_seq

let status relations = if List.exists (fun (_, _, n) -> n > 0) relations then 1 else 0

(* Snapshots are persistent, so keeping one is cheap, and one per change would keep every past state. *)
let storage_at ~at (c : _ Core.t) changes snapshot =
  let latest = ref None in
  Option.iter
    (fun at ->
      List.iter
        (fun changes ->
          Ev.subscribe
            (Ev.tag (Sig.cycle c.clk) changes)
            (fun (_, cycle) -> if cycle <= at then latest := Some (cycle, snapshot ())))
        changes)
    at;
  fun () -> !latest
