[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** Round trips of Coral NPU's Zvt instructions through Rivet's decoder and assembler. *)

val run : unit -> int * string list
(** The number of words checked and the failures. Every Zvt instruction, with its operand fields
    zero, all ones and alternating ({!Coral_zvt.samples}), decodes under its own mnemonic and
    assembles back to the same word; so do the spellings of Coral's reference words; and the forms
    the RTL does not decode, or a configuration without [xcoralzvt], are refused. *)
