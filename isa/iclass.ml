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
let prefix p s = String.length s >= String.length p && String.sub s 0 (String.length p) = p
let one_of ps s = List.exists (fun p -> prefix p s) ps

(* [p] followed by an element width: vle32.v, vsse8.v, but not vsext.vf2 or vsub.vv. *)
let width p s =
  prefix p s
  &&
  let n = String.length p in
  String.length s > n && s.[n] >= '0' && s.[n] <= '9'

let vector_mem s =
  List.exists
    (fun p -> width p s)
    [ "vle"; "vlse"; "vluxei"; "vloxei"; "vlseg"; "vse"; "vsse"; "vsuxei"; "vsoxei"; "vsseg" ]
  || one_of [ "vlm.v"; "vsm.v" ] s
  || (prefix "vl" s && String.contains s 'r' && width "vl" s)
  || (prefix "vs" s && width "vs" s && String.length s > 3 && s.[3] = 'r')

let system s =
  one_of [ "csr"; "fence"; "sfence"; "ecall"; "ebreak"; "mret"; "sret"; "wfi"; "unimp"; "mpause" ] s

let branch s = List.mem s [ "beq"; "bne"; "blt"; "bge"; "bltu"; "bgeu"; "jal"; "jalr" ]

let mem s =
  List.mem s [ "lb"; "lh"; "lw"; "ld"; "lbu"; "lhu"; "lwu"; "sb"; "sh"; "sw"; "sd" ]
  || List.mem s [ "flh"; "flw"; "fld"; "flq"; "fsh"; "fsw"; "fsd"; "fsq" ]
  || one_of [ "lr."; "sc."; "amo" ] s

let of_mnemonic ?feature mnemonic =
  if feature = Some Coral_zvt.feature then Tile
  else if system mnemonic then System
  else if branch mnemonic then Branch
  else if mem mnemonic then Mem
  else if vector_mem mnemonic then Vector_mem
  else if prefix "v" mnemonic then Vector
  else if prefix "f" mnemonic then Fp
  else Alu

let of_instruction (i : Rivet_decode.instruction) = of_mnemonic ?feature:i.feature i.mnemonic
