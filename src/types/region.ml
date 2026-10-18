[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

type t = Manifest.configuration option

let none = None
let of_manifest c = Some c

let find t addr =
  Option.bind t (fun c ->
      Option.map (fun (r : Manifest.region) -> r.region) (Manifest.region_of c addr))

let suffix t addr =
  match t with
  | None -> ""
  | Some _ -> ( match find t addr with Some r -> " (" ^ r ^ ")" | None -> " (unmapped)")
