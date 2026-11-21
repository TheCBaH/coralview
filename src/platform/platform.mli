[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** What coralview knows about a Coral NPU RTL configuration's trace: where the core is, its clock, and
    which blocks can be observed, with their scopes (relative to the root) and sizes. The models read
    lane and port counts from here rather than discovering them, and a block declared here whose signals
    are not in a trace is a hard error: the description, not the trace, is wrong. *)

type dispatch_debug = {
  dd_scope : string list;
  dd_lanes : int;
  dd_fire : string;  (** Whether the lane dispatches an instruction. *)
  dd_addr : string;  (** Its PC. *)
  dd_inst : string;  (** Its word. *)
}
(** The names have [%d] for the lane when there are several, like the other lane and port names. *)

type retirement_debug = {
  rd_scope : string list;
  rd_lanes : int;
  idx_width : int;
  rd_valid : string;  (** Whether the lane retires an instruction. *)
  rd_pc : string;
  rd_idx : string;  (** The unified destination index, [idx_width] bits wide. *)
  rd_trap : string option;  (** The trap bit; [None] for a buffer that does not report one. *)
}

type writeback = {
  wb_scope : string list;
  ports : int;
  wb_valid : string;
  wb_addr : string;  (** The register written, in its file. *)
  wb_data : string;
}
(** Names have [%d] for the port when there are several. *)

type lane = { l_valid : string; l_ready : string; l_addr : string; l_inst : string }
(** The decoded instruction offered to a dispatch lane, with [%d] for the lane. *)

type dispatch = {
  d_scope : string list;
  d_lanes : int;
  lane : lane;
  try_dispatch : string list;  (** Per lane: Dispatch.tryDispatch(i). *)
  comb : string list;  (** Per lane: the scalar scoreboard the lane checks, comb(i). *)
  fcomb : string list option;
      (** Per lane: the float scoreboard, fcomb(i); [None] without float. *)
  rvv_queue : string option;  (** The RVV queue capacity input; [None] without RVV. *)
  halted : string;
  interlock : string;
  scoreboard_regd : string;  (** The scoreboard of registers with a write pending. *)
  rob_space : string;  (** Free entries of the retirement buffer. *)
  rob_empty : string;
  rob_trap_pending : string;
  lsu_capacity : string;  (** Free entries of the LSU queue. *)
}

type tlul = { tl_prefix : string; tl_data_bytes : int; d_ready : bool }
(** A TileLink-UL port: [tl_prefix ^ "{a,d}_{valid,ready}"] and the channel fields
    [a_bits_{opcode,size,source,address,mask,data}], [d_bits_{opcode,size,source,data,error}], with a
    [tl_data_bytes]-wide data bus. Without [d_ready] (a device that does not read it), a response is
    taken when it is valid. *)

type fault = { f_valid : string; f_write : string; f_addr : string; f_epc : string }
(** An access fault the LSU reports: its direction, address and the PC of the instruction. *)

type lsu = { lsu_scope : string list; port : tlul; lsu_pc : string; fault : fault }
(** The LSU's TileLink-UL port: its one path to the TCMs and the external bus. [lsu_pc] is the PC of the
    instruction whose request is on the port; a name of the form [a/n] is signal [n] in the sub-scope [a]
    of [lsu_scope], as in {!origin}'s [o_pc]. *)

type vme_writes = {
  we_en : string;  (** Byte enables of every port's write into a sub-tile. *)
  we_pe_en : string;  (** The byte enables the PE array drives. *)
  we_pe_pc : string;  (** The PC of each block's PE write. *)
  we_mt_idx : string;  (** The tile written. *)
  we_sub_idx : string;  (** The sub-tile written. *)
  we_data : string;
}

type vme = {
  vme_scope : string list;
  blocks : int;
  ports_per_block : int;
  tiles : int;
  subtiles : int;
  subtile_bytes : int;
  vme_writes : vme_writes;
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

type tracking = {
  t_source : string;  (** The request's TileLink-UL source, on channel A. *)
  t_response : string;  (** Channel D valid. *)
  t_response_source : string;
  t_opcode : string option;  (** Channel A opcode: a Get (4) is a read, any other a write. *)
}
(** A TileLink-UL request interface whose requests are matched to transactions by source rather than by
    being visible at the address handshake: the master keeps a request's source in the low bits of its
    transaction ID, and a request is outstanding from its acceptance on channel A to its response on D. *)

type origin = {
  o_scope : string list;
  o_valid : string;
  o_ready : string;
  o_addr : string;
  align : int;
  o_write : string option;
  o_pc : string option;
  track : tracking option;
  ops : ops option;
}

type axi_source = { source_id : int; id_mask : int; source : string; origin : origin option }

type axi = {
  axi_scope : string list;
  axi_prefix : string;
  data_bytes : int;
  sources : axi_source list;
}
(** The core's AXI4 master port, through which all external traffic leaves the core: wires
    [axi_prefix ^ "{read,write}_addr_{valid,ready,bits_*}"], [read_data_*], [write_data_*] and
    [write_resp_*], with a [data_bytes]-wide data bus. [sources] name the masters behind it by AXI ID: the
    IDs [id_mask] selects (all bits by default) are [source_id].
    A source's [origin] is the request interface the master serves ([o_scope] relative to the root),
    which a transaction is pinned to when its address is accepted: [o_valid] must be high then and
    [o_addr], rounded down to [align] bytes, equal the AXI address. The request began at the start of
    that run of [o_valid] (it ends at [o_valid && o_ready]); [o_write], if given, is its direction and
    [o_pc] the instruction that made it, whose operation [ops] follows from dispatch to issue.
    With [track], the master is behind a bridge and its request comes first: the transaction is pinned
    to the request outstanding (accepted, not yet answered) on the [t_source] equal to the low bits of
    its ID, those [id_mask] does not select, whenever it was made. *)

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
  scoreboard_entries : int;
  fields : field list;
  scoreboard : string;
  flushed_scoreboard : string;
  flush : string;
  marks : marks;
}
(** A register file: [count] registers from [first], each the concatenation (most significant first) of
    [fields], whose names have [%d] for the register number; unified keys are [base + number]. The
    [scoreboard] has a bit per register number, [scoreboard_entries] of them from 0, [flushed_scoreboard] the bits a pipeline [flush] set aside. [marks] are the dispatch-time ports that announce a write,
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

type vector_dispatch = {
  vd_scope : string list;
  vd_lanes : int;
  vd_valid : string;
  vd_ready : string;
  vd_uop : string;
  vd_layout : field list;
  units : string list;
}
(** The RVV backend's uop dispatch ([rvv_backend_dispatch.sv]): [vd_lanes] uops a cycle, each taken when
    its bit of [vd_valid] and of [vd_ready] are set. [vd_uop] is the packed array of the uops, each laid
    out as [vd_layout], most significant field first, which must have [uop_pc], [uop_exe_unit],
    [csr_vl], [csr_vstart], [csr_sew], [csr_lmul] and [first_uop_valid]. [units] names the values of
    [uop_exe_unit], in order. *)

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
  v_dispatch : vector_dispatch option;
  traps : traps option;
}
(** A new block is a field here, its [no_blocks] entry and one entry of [registry] in [platform.ml], which
    gives its name, codec, accessors and {!known_blocks} needs. *)

type configuration = {
  config : string;  (** As named in the archive's [hardware-configurations.json]. *)
  top_level : string;  (** Its [simulation.top_level]. *)
  trace_root : string list;  (** Scope components of the core in its traces. *)
}

type reset = {
  reset_signal : string;  (** A 1-bit signal of the core's scope, like the clock. *)
  reset_active : bool;
      (** The level that holds the core in reset: [true] for [high], [false] for [low]. *)
}

type family = {
  family : string;
  configurations : configuration list;
  clock : string;
  reset : reset option;
      (** Absent when the description does not say where the reset is: every sample is then out of reset. *)
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
  reset : reset option;
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

val known_blocks : (string * string list) list
(** Every block a description can have, in the order {!blocks} lists them, with the blocks that must be
    described with it: a description that gives a block without them is an error at the block. *)

val name_of : string -> int -> string
(** A wire name pattern with [%d] replaced by the number; a name without [%d] as is. *)
