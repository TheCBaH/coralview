[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** What the text views of the analyses share: the rows asked for, and how to name instructions and
    addresses. *)

type window = { first : int; last : int; pcs : int list }

val everything : window

val windowed : window -> bool
(** Not {!everything}. *)

val describe : window -> string
(** ["window [first, last] pc …"], for the totals of a window; [last] is ["end"] when unbounded. *)

val selected : window -> cycle:int -> pc:int -> bool
(** In the cycle range, and of one of [pcs] unless empty. *)

type profile_by = Pc | Class | Function

type ctx = {
  root : string;  (** The platform root, as the summaries name it. *)
  disasm : int -> string;
  instruction_class : int -> string;
      (** ["alu"], ["vector-mem"], …; ["unknown"] for a word Rivet does not decode. *)
  symbol : int -> (string * int) option;
      (** The function of a PC and the offset in it, with [--elf]. *)
  profile_by : profile_by;
      (** What the rows of a profile are: PCs, instruction classes or functions. *)
  region : Region.t;
  window : window;
  limit : int;  (** Rows at most. *)
  profile : int;  (** Profile rows; 0 for none. *)
}

val stats : Hwfrp.Reduce.Stats.t -> string
(** ["min/mean/max"], the mean with one decimal; ["-"] when empty. *)
