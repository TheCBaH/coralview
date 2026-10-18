[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** Coral NPU's Zvt matrix instructions as a Rivet vendor extension, built from [zvt.jsonl]: the
    encodings devcontainer.coralnpu exports from the patched MPACT decoder ([isa/zvt.jsonl] in its
    emulator archive). Coral's [mset*] differ from the riscv-opcodes draft, so the rows come from
    MPACT, not from Rivet's standard tables. *)

val feature : string
(** The vendor feature, off by default: [xcoralzvt]. *)

val definition : unit -> (Riscv_family_encode.Extensions.Validated.t, string) result
(** The standard RV32 extensions with the Zvt rows, validated by Rivet. *)
