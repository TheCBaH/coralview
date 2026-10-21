[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

module type ACCUMULATOR = sig
  type event
  type t
  type snapshot

  val create : unit -> t
  val add : t -> event -> unit
  val snapshot : t -> snapshot
end

let tap (type a e) (module A : ACCUMULATOR with type t = a and type event = e) acc events =
  Seq.once
    (Seq.map
       (fun e ->
         A.add acc e;
         e)
       events)
