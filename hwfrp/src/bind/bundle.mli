[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** Chisel bundles flattened into ports: [<prefix>_<field>], with [_valid], [_ready] and [_bits_*] for
    [Valid] and [Decoupled]. *)

type 'c t

val discover : 'c Bind.scope -> string -> 'c t
(** The variables of the scope named [<prefix>_<field>]. *)

val fields : 'c t -> (string * int) list
(** Field names without the prefix, with their widths, in declaration order. *)

val get :
  ?need:Bind.need -> ?purpose:string -> 'c t -> string -> 'a Bind.decoder -> ('a, 'c) Frp.Sig.t

val lanes : 'c Bind.scope -> string -> int list
(** The values of [%d] for which a variable of the scope matches the pattern, ascending:
    ["io_debug_rb_inst_%d_valid"] gives [[0; …; 7]] on the VME core. *)

type 'c valid = { v_valid : (bool, 'c) Frp.Sig.t; v_bits : 'c t }

type 'c decoupled = {
  d_valid : (bool, 'c) Frp.Sig.t;
  d_ready : (bool, 'c) Frp.Sig.t;
  d_bits : 'c t;
}

val valid : ?purpose:string -> 'c Bind.scope -> string -> 'c valid
(** [purpose] describes the valid signal. *)

val decoupled : ?purpose:string -> 'c Bind.scope -> string -> 'c decoupled
