[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

type t = Alu | Fp | Mem | Branch | Vector | Vector_mem | Tile | System

let all = [ Alu; Fp; Mem; Branch; Vector; Vector_mem; Tile; System ]

let name = function
  | Alu -> "alu"
  | Fp -> "fp"
  | Mem -> "mem"
  | Branch -> "branch"
  | Vector -> "vector"
  | Vector_mem -> "vector-mem"
  | Tile -> "tile"
  | System -> "system"

let of_name s = List.find_opt (fun c -> name c = s) all

(* Rivet reads the class off the word; a Zvt row is a tile op whatever its major opcode. *)
let of_cls ?feature (cls : Rivet_decode.Cls.t) =
  if feature = Some Coral_zvt.feature then Tile
  else
    match cls with
    | Load | Store | Atomic -> Mem
    | Branch | Jump -> Branch
    | Vector_load | Vector_store -> Vector_mem
    | Csr | System -> System
    | Vector -> Vector
    | Fp -> Fp
    | Alu | Custom -> Alu

let of_instruction (i : Rivet_decode.instruction) = of_cls ?feature:i.feature i.cls
