[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** What coralview knows about a Coral NPU RTL configuration's trace: where the core is, its clock, and
    which blocks can be observed, with their scopes (relative to the root) and sizes. The models read
    lane and port counts from here rather than discovering them, and a block declared here whose signals
    are not in a trace is a hard error: the description, not the trace, is wrong. *)

type dispatch_debug = { dd_scope : string list; dd_lanes : int }
type retirement_debug = { rd_scope : string list; rd_lanes : int; idx_width : int; trap : bool }
type writeback = { wb_scope : string list; ports : int }

type dispatch = {
  d_scope : string list;
  d_lanes : int;
  try_dispatch : string list;  (** Per lane: Dispatch.tryDispatch(i). *)
  comb : string list;  (** Per lane: the scalar scoreboard the lane checks, comb(i). *)
  fcomb : string list option;
      (** Per lane: the float scoreboard, fcomb(i); [None] without float. *)
  rvv_queue : string option;  (** The RVV queue capacity input; [None] without RVV. *)
}

type lsu = { lsu_scope : string list; tcm_ready : bool }

type vme = {
  vme_scope : string list;
  blocks : int;
  ports_per_block : int;
  tiles : int;
  subtiles : int;
  subtile_bytes : int;
}

type port = {
  port_scope : string list;
  port_lanes : int;
  port_valid : string;
  port_ready : string;
  port_pc : string;
}
(** [port_lanes] handshakes [port_valid]/[port_ready] carrying an instruction's [port_pc]; names have
    [%d] for the lane when there are several. *)

type ops = { enqueue : port; issue : port }
(** An in-order queue of the originator's operations, one per instruction: entered at [enqueue], when
    the instruction is dispatched to it, in lane order; left at [issue], when the operation starts
    making requests, all with its PC, until the next leaves. *)

type origin = {
  o_scope : string list;
  o_valid : string;
  o_ready : string;
  o_addr : string;
  align : int;
  o_write : string option;
  o_pc : string option;
  ops : ops option;
}

type axi_source = { source_id : int; source : string; origin : origin option }

type axi = {
  axi_scope : string list;
  axi_prefix : string;
  data_bytes : int;
  sources : axi_source list;
}
(** The core's AXI4 master port, through which all external traffic leaves the core: wires
    [axi_prefix ^ "{read,write}_addr_{valid,ready,bits_*}"], [read_data_*], [write_data_*] and
    [write_resp_*], with a [data_bytes]-wide data bus. [sources] name the masters behind it by AXI ID.
    A source's [origin] is the request interface the master serves ([o_scope] relative to the root),
    which a transaction is pinned to when its address is accepted: [o_valid] must be high then and
    [o_addr], rounded down to [align] bytes, equal the AXI address. The request began at the start of
    that run of [o_valid] (it ends at [o_valid && o_ready]); [o_write], if given, is its direction and
    [o_pc] the instruction that made it, whose operation [ops] follows from dispatch to issue. *)

type tlul = { tl_prefix : string; tl_data_bytes : int; d_ready : bool }
(** A TileLink-UL port: [tl_prefix ^ "{a,d}_{valid,ready}"] and the channel fields
    [a_bits_{opcode,size,source,address,mask,data}], [d_bits_{opcode,size,source,data,error}], with a
    [tl_data_bytes]-wide data bus. Without [d_ready] (a device that does not read it), a response is
    taken when it is valid. *)

type dma = {
  dma_scope : string list;
  host : tlul;  (** The engine's master port: descriptor fetches, polls and data beats. *)
  device : tlul;  (** Its CSR port. *)
  csr_base : int;
  requester : origin option;
      (** The core's request interface, which a CSR access is pinned to, by address, to name the
          instruction that made it. *)
}
(** A descriptor DMA engine ([bus.DmaEngine]). *)

type field = { field : string; field_width : int }
type marks = { m_scope : string list; m_valid : string; m_addr : string; m_ports : int }

type register_file = {
  rf_scope : string list;
  base : int;
  first : int;
  count : int;
  fields : field list;
  scoreboard : string;
  flushed_scoreboard : string;
  flush : string;
  marks : marks;
}
(** A register file: [count] registers from [first], each the concatenation (most significant first) of
    [fields], whose names have [%d] for the register number; unified keys are [base + number]. The
    [scoreboard] has a bit per register, [flushed_scoreboard] the bits a pipeline [flush] set aside. [marks] are the dispatch-time ports that announce a write,
    named with [%d] for the port. *)

type vector_registers = {
  vr_scope : string list;
  vr_base : int;
  vr_count : int;
  vlen : int;
  storage : string;
  writes : vector_writes;
}

and vector_writes = { w_ports : int; w_valid : string; w_data : string; layout : field list }
(** A vector register file: [storage] is the packed array [logic [vr_count-1:0][vlen-1:0]], keyed from
    [vr_base]. Its write ports are the [w_ports]-bit [w_valid] and the packed array [w_data] of structs laid
    out as [layout], most significant field first, which must have [rt_index], [rt_data] ([vlen] bits) and
    [rt_strobe] (a byte enable per byte) and may have the writing instruction's [uop_pc]. *)

type traps = {
  t_scope : string list;
  valid : string;
  mcause : string;
  mepc : string;
  mtval : string;
  decode : string;
  memory : string;
  memory_write : string;
  fetch : string;
  rvv : string option;
  csr : csr;
}

and csr = {
  csr_scope : string list;
  csr_mcause : string;
  csr_mepc : string;
  csr_mtval : string;
  csr_mtvec : string;
}
(** The fault manager ([t_scope]): its output [valid] with the [mcause], [mepc] and [mtval] it sends to
    the CSRs, and the inputs that say where a fault came from: [decode] (an output bit), the LSU's
    [memory] fault and whether it was a [memory_write], an instruction [fetch] fault and, with RVV, the
    vector core's [rvv] fault. [csr] names the CSR registers. *)

type blocks = {
  dispatch_debug : dispatch_debug option;
  retirement_debug : retirement_debug option;
  regfile_writeback : writeback option;
  float_writeback : writeback option;
  dispatch : dispatch option;
  lsu : lsu option;
  vme : vme option;
  axi_master : axi option;
  dma : dma option;
  x_registers : register_file option;
  f_registers : register_file option;
  v_registers : vector_registers option;
  traps : traps option;
}

type configuration = {
  config : string;  (** As named in the archive's [hardware-configurations.json]. *)
  top_level : string;  (** Its [simulation.top_level]. *)
  trace_root : string list;  (** Scope components of the core in its traces. *)
}

type family = {
  family : string;
  configurations : configuration list;
  clock : string;
  sample : Hwfrp.Trace.sample_rule;
  blocks : blocks;
}
(** One description file: configurations of the same RTL structure. *)

type t = {
  name : string;  (** The configuration. *)
  family_name : string;
  top_level : string;
  trace_root : string list;
  clock : string;
  sample : Hwfrp.Trace.sample_rule;
  blocks : blocks;
}

val jsont : family Jsont.t
(** Unknown members are errors, and per-lane wire lists must have one name per lane. *)

val of_string : ?file:string -> string -> (family, string) result
val configurations : family -> t list
val builtin : t list Lazy.t

val find : string -> (t, string) result
(** A built-in configuration by name, or a description file by path, which must have one configuration
    or be followed by [:CONFIG]. *)

val root : t -> Vcd_types.Reference.t

val scope : t -> string list -> Vcd_types.Reference.t
(** A block scope as an absolute path. *)

val blocks : t -> string list
(** The names of the blocks it describes. *)

val name_of : string -> int -> string
(** A wire name pattern with [%d] replaced by the number; a name without [%d] as is. *)
