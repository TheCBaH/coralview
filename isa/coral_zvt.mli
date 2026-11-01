[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** Coral NPU's Zvt matrix instructions as a Rivet vendor extension, built from [zvt.jsonl]: the
    encodings devcontainer.coralnpu exports from the patched MPACT decoder ([isa/zvt.jsonl] in its
    emulator archive). Coral's [mset*] differ from the riscv-opcodes draft, so the rows come from
    MPACT, not from Rivet's standard tables. *)

val feature : string
(** The vendor feature, off by default: [xcoralzvt]. *)

val system_feature : string
(** The vendor feature of Coral's words outside Zvt, off by default: [xcoralsys] ([mpause]). *)

val supported_zvt_version : string
(** The only Zvt specification version coralview supports: [v0.4]. *)

val zvt_version : string
(** The [zvt_version] in [zvt.jsonl]'s provenance record: the version the table follows. *)

val revision : string
(** The [coralnpu_revision] in the same record. *)

val definition : unit -> (Riscv_family_encode.Extensions.Validated.t, string) result
(** The standard RV32 extensions with the Zvt rows, validated by Rivet. *)

val samples : unit -> ((string * int) list, string) result
(** For each instruction, its mnemonic and four words of it: the fixed bits with every operand field
    zero, all ones, and two alternating patterns. Words as 32-bit integers, for round-trip tests. *)
