[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

type dispatch_debug = {
  dd_scope : string list;
  dd_lanes : int;
  dd_fire : string;
  dd_addr : string;
  dd_inst : string;
}

type retirement_debug = {
  rd_scope : string list;
  rd_lanes : int;
  idx_width : int;
  rd_valid : string;
  rd_pc : string;
  rd_idx : string;
  rd_trap : string option;
}

type writeback = {
  wb_scope : string list;
  ports : int;
  wb_valid : string;
  wb_addr : string;
  wb_data : string;
}

type lane = { l_valid : string; l_ready : string; l_addr : string; l_inst : string }

type dispatch = {
  d_scope : string list;
  d_lanes : int;
  lane : lane;
  try_dispatch : string list;
  comb : string list;
  fcomb : string list option;
  rvv_queue : string option;
  halted : string;
  interlock : string;
  scoreboard_regd : string;
  rob_space : string;
  rob_empty : string;
  rob_trap_pending : string;
  lsu_capacity : string;
}

type tlul = { tl_prefix : string; tl_data_bytes : int; d_ready : bool }
type fault = { f_valid : string; f_write : string; f_addr : string; f_epc : string }

type lsu = { lsu_scope : string list; port : tlul; lsu_pc : string; fault : fault }
(** The LSU's TileLink-UL port: its one path to the TCMs and the external bus. *)

type vme_writes = {
  we_en : string;
  we_pe_en : string;
  we_pe_pc : string;
  we_mt_idx : string;
  we_sub_idx : string;
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

type ops = { enqueue : port; issue : port }

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

type dma = {
  dma_scope : string list;
  host : tlul;
  device : tlul;
  csr_base : int;
  requester : origin option;
}

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

type vector_registers = {
  vr_scope : string list;
  vr_base : int;
  vr_count : int;
  vlen : int;
  storage : string;
  writes : vector_writes;
}

and vector_writes = { w_ports : int; w_valid : string; w_data : string; layout : field list }

type vector_dispatch = {
  vd_scope : string list;
  vd_lanes : int;
  vd_valid : string;
  vd_ready : string;
  vd_uop : string;
  vd_layout : field list;
  units : string list;
}

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

type configuration = { config : string; top_level : string; trace_root : string list }
type reset = { reset_signal : string; reset_active : bool }

type family = {
  family : string;
  configurations : configuration list;
  clock : string;
  reset : reset option;
  sample : Hwfrp.Trace.sample_rule;
  blocks : blocks;
}

type t = {
  name : string;
  family_name : string;
  top_level : string;
  trace_root : string list;
  clock : string;
  reset : reset option;
  sample : Hwfrp.Trace.sample_rule;
  blocks : blocks;
}

let has_lane pattern =
  match String.index_opt pattern '%' with
  | Some i -> i + 1 < String.length pattern && pattern.[i + 1] = 'd'
  | None -> false

let obj kind f = Jsont.Object.map ~kind f
let obj_at kind f = Jsont.Object.map' ~kind f
let finish m = Jsont.Object.(finish (error_unknown m))
let scope = Jsont.(list string)

let lanes_pattern at kind lanes pattern =
  if lanes > 1 && not (has_lane pattern) then
    Jsont.Error.msgf at "%s: %S has no %%d for its %d lanes" kind pattern lanes

let dispatch_debug =
  obj_at "dispatch_debug" (fun at dd_scope dd_lanes dd_fire dd_addr dd_inst ->
      List.iter (lanes_pattern at "dispatch_debug" dd_lanes) [ dd_fire; dd_addr; dd_inst ];
      { dd_scope; dd_lanes; dd_fire; dd_addr; dd_inst })
  |> Jsont.Object.mem "scope" scope ~enc:(fun b -> b.dd_scope)
  |> Jsont.Object.mem "lanes" Jsont.int ~enc:(fun b -> b.dd_lanes)
  |> Jsont.Object.mem "fire" Jsont.string ~enc:(fun b -> b.dd_fire)
  |> Jsont.Object.mem "addr" Jsont.string ~enc:(fun b -> b.dd_addr)
  |> Jsont.Object.mem "inst" Jsont.string ~enc:(fun b -> b.dd_inst)
  |> finish

let retirement_debug =
  obj_at "retirement_debug" (fun at rd_scope rd_lanes idx_width rd_valid rd_pc rd_idx rd_trap ->
      List.iter
        (lanes_pattern at "retirement_debug" rd_lanes)
        ([ rd_valid; rd_pc; rd_idx ] @ Option.to_list rd_trap);
      { rd_scope; rd_lanes; idx_width; rd_valid; rd_pc; rd_idx; rd_trap })
  |> Jsont.Object.mem "scope" scope ~enc:(fun b -> b.rd_scope)
  |> Jsont.Object.mem "lanes" Jsont.int ~enc:(fun b -> b.rd_lanes)
  |> Jsont.Object.mem "idx_width" Jsont.int ~enc:(fun b -> b.idx_width)
  |> Jsont.Object.mem "valid" Jsont.string ~enc:(fun b -> b.rd_valid)
  |> Jsont.Object.mem "pc" Jsont.string ~enc:(fun b -> b.rd_pc)
  |> Jsont.Object.mem "idx" Jsont.string ~enc:(fun b -> b.rd_idx)
  |> Jsont.Object.opt_mem "trap" Jsont.string ~enc:(fun b -> b.rd_trap)
  |> finish

let writeback =
  obj_at "writeback" (fun at wb_scope ports wb_valid wb_addr wb_data ->
      List.iter (lanes_pattern at "writeback" ports) [ wb_valid; wb_addr; wb_data ];
      { wb_scope; ports; wb_valid; wb_addr; wb_data })
  |> Jsont.Object.mem "scope" scope ~enc:(fun b -> b.wb_scope)
  |> Jsont.Object.mem "ports" Jsont.int ~enc:(fun b -> b.ports)
  |> Jsont.Object.mem "valid" Jsont.string ~enc:(fun b -> b.wb_valid)
  |> Jsont.Object.mem "addr" Jsont.string ~enc:(fun b -> b.wb_addr)
  |> Jsont.Object.mem "data" Jsont.string ~enc:(fun b -> b.wb_data)
  |> finish

let lane =
  obj "dispatch lane" (fun l_valid l_ready l_addr l_inst -> { l_valid; l_ready; l_addr; l_inst })
  |> Jsont.Object.mem "valid" Jsont.string ~enc:(fun l -> l.l_valid)
  |> Jsont.Object.mem "ready" Jsont.string ~enc:(fun l -> l.l_ready)
  |> Jsont.Object.mem "addr" Jsont.string ~enc:(fun l -> l.l_addr)
  |> Jsont.Object.mem "inst" Jsont.string ~enc:(fun l -> l.l_inst)
  |> finish

let per_lane at name lanes l =
  if List.length l <> lanes then
    Jsont.Error.msgf at "dispatch.%s: %d names for %d lanes" name (List.length l) lanes

let dispatch =
  obj_at "dispatch"
    (fun
      at
      d_scope
      d_lanes
      lane
      try_dispatch
      comb
      fcomb
      rvv_queue
      halted
      interlock
      scoreboard_regd
      rob_space
      rob_empty
      rob_trap_pending
      lsu_capacity
    ->
      per_lane at "try_dispatch" d_lanes try_dispatch;
      per_lane at "comb" d_lanes comb;
      Option.iter (per_lane at "fcomb" d_lanes) fcomb;
      List.iter
        (lanes_pattern at "dispatch.lane" d_lanes)
        [ lane.l_valid; lane.l_ready; lane.l_addr; lane.l_inst ];
      {
        d_scope;
        d_lanes;
        lane;
        try_dispatch;
        comb;
        fcomb;
        rvv_queue;
        halted;
        interlock;
        scoreboard_regd;
        rob_space;
        rob_empty;
        rob_trap_pending;
        lsu_capacity;
      })
  |> Jsont.Object.mem "scope" scope ~enc:(fun b -> b.d_scope)
  |> Jsont.Object.mem "lanes" Jsont.int ~enc:(fun b -> b.d_lanes)
  |> Jsont.Object.mem "lane" lane ~enc:(fun b -> b.lane)
  |> Jsont.Object.mem "try_dispatch" Jsont.(list string) ~enc:(fun b -> b.try_dispatch)
  |> Jsont.Object.mem "comb" Jsont.(list string) ~enc:(fun b -> b.comb)
  |> Jsont.Object.opt_mem "fcomb" Jsont.(list string) ~enc:(fun b -> b.fcomb)
  |> Jsont.Object.opt_mem "rvv_queue" Jsont.string ~enc:(fun b -> b.rvv_queue)
  |> Jsont.Object.mem "halted" Jsont.string ~enc:(fun b -> b.halted)
  |> Jsont.Object.mem "interlock" Jsont.string ~enc:(fun b -> b.interlock)
  |> Jsont.Object.mem "scoreboard_regd" Jsont.string ~enc:(fun b -> b.scoreboard_regd)
  |> Jsont.Object.mem "rob_space" Jsont.string ~enc:(fun b -> b.rob_space)
  |> Jsont.Object.mem "rob_empty" Jsont.string ~enc:(fun b -> b.rob_empty)
  |> Jsont.Object.mem "rob_trap_pending" Jsont.string ~enc:(fun b -> b.rob_trap_pending)
  |> Jsont.Object.mem "lsu_capacity" Jsont.string ~enc:(fun b -> b.lsu_capacity)
  |> finish

let tlul =
  obj_at "tlul port" (fun at tl_prefix tl_data_bytes d_ready ->
      if tl_data_bytes <= 0 || tl_data_bytes land (tl_data_bytes - 1) <> 0 then
        Jsont.Error.msgf at "tlul: data_bytes %d is not a power of two" tl_data_bytes;
      { tl_prefix; tl_data_bytes; d_ready })
  |> Jsont.Object.mem "prefix" Jsont.string ~enc:(fun t -> t.tl_prefix)
  |> Jsont.Object.mem "data_bytes" Jsont.int ~enc:(fun t -> t.tl_data_bytes)
  |> Jsont.Object.mem "d_ready" Jsont.bool ~enc:(fun t -> t.d_ready)
  |> finish

let fault =
  obj "fault" (fun f_valid f_write f_addr f_epc -> { f_valid; f_write; f_addr; f_epc })
  |> Jsont.Object.mem "valid" Jsont.string ~enc:(fun f -> f.f_valid)
  |> Jsont.Object.mem "write" Jsont.string ~enc:(fun f -> f.f_write)
  |> Jsont.Object.mem "addr" Jsont.string ~enc:(fun f -> f.f_addr)
  |> Jsont.Object.mem "epc" Jsont.string ~enc:(fun f -> f.f_epc)
  |> finish

let lsu =
  obj "lsu" (fun lsu_scope port lsu_pc fault -> { lsu_scope; port; lsu_pc; fault })
  |> Jsont.Object.mem "scope" scope ~enc:(fun b -> b.lsu_scope)
  |> Jsont.Object.mem "port" tlul ~enc:(fun b -> b.port)
  |> Jsont.Object.mem "pc" Jsont.string ~enc:(fun b -> b.lsu_pc)
  |> Jsont.Object.mem "fault" fault ~enc:(fun b -> b.fault)
  |> finish

let vme_writes =
  obj "vme writes" (fun we_en we_pe_en we_pe_pc we_mt_idx we_sub_idx we_data ->
      { we_en; we_pe_en; we_pe_pc; we_mt_idx; we_sub_idx; we_data })
  |> Jsont.Object.mem "en" Jsont.string ~enc:(fun w -> w.we_en)
  |> Jsont.Object.mem "pe_en" Jsont.string ~enc:(fun w -> w.we_pe_en)
  |> Jsont.Object.mem "pe_pc" Jsont.string ~enc:(fun w -> w.we_pe_pc)
  |> Jsont.Object.mem "mt_idx" Jsont.string ~enc:(fun w -> w.we_mt_idx)
  |> Jsont.Object.mem "sub_idx" Jsont.string ~enc:(fun w -> w.we_sub_idx)
  |> Jsont.Object.mem "data" Jsont.string ~enc:(fun w -> w.we_data)
  |> finish

let vme =
  obj "vme" (fun vme_scope blocks ports_per_block tiles subtiles subtile_bytes vme_writes ->
      { vme_scope; blocks; ports_per_block; tiles; subtiles; subtile_bytes; vme_writes })
  |> Jsont.Object.mem "scope" scope ~enc:(fun b -> b.vme_scope)
  |> Jsont.Object.mem "blocks" Jsont.int ~enc:(fun (b : vme) -> b.blocks)
  |> Jsont.Object.mem "ports_per_block" Jsont.int ~enc:(fun b -> b.ports_per_block)
  |> Jsont.Object.mem "tiles" Jsont.int ~enc:(fun b -> b.tiles)
  |> Jsont.Object.mem "subtiles" Jsont.int ~enc:(fun b -> b.subtiles)
  |> Jsont.Object.mem "subtile_bytes" Jsont.int ~enc:(fun b -> b.subtile_bytes)
  |> Jsont.Object.mem "writes" vme_writes ~enc:(fun b -> b.vme_writes)
  |> finish

let port =
  obj "port" (fun port_scope port_lanes port_valid port_ready port_pc ->
      { port_scope; port_lanes; port_valid; port_ready; port_pc })
  |> Jsont.Object.mem "scope" scope ~enc:(fun p -> p.port_scope)
  |> Jsont.Object.mem "lanes" Jsont.int ~enc:(fun p -> p.port_lanes)
  |> Jsont.Object.mem "valid" Jsont.string ~enc:(fun p -> p.port_valid)
  |> Jsont.Object.mem "ready" Jsont.string ~enc:(fun p -> p.port_ready)
  |> Jsont.Object.mem "pc" Jsont.string ~enc:(fun p -> p.port_pc)
  |> finish

let ops =
  obj "ops" (fun enqueue issue -> { enqueue; issue })
  |> Jsont.Object.mem "enqueue" port ~enc:(fun o -> o.enqueue)
  |> Jsont.Object.mem "issue" port ~enc:(fun o -> o.issue)
  |> finish

let tracking =
  obj "tracking" (fun t_source t_response t_response_source t_opcode ->
      { t_source; t_response; t_response_source; t_opcode })
  |> Jsont.Object.mem "source" Jsont.string ~enc:(fun t -> t.t_source)
  |> Jsont.Object.mem "d_valid" Jsont.string ~enc:(fun t -> t.t_response)
  |> Jsont.Object.mem "d_source" Jsont.string ~enc:(fun t -> t.t_response_source)
  |> Jsont.Object.opt_mem "opcode" Jsont.string ~enc:(fun t -> t.t_opcode)
  |> finish

let origin =
  obj_at "origin" (fun at o_scope o_valid o_ready o_addr align o_write o_pc track ops ->
      if align <= 0 || align land (align - 1) <> 0 then
        Jsont.Error.msgf at "origin: align %d is not a power of two" align;
      if ops <> None && o_pc = None then Jsont.Error.msgf at "origin: ops without a pc";
      { o_scope; o_valid; o_ready; o_addr; align; o_write; o_pc; track; ops })
  |> Jsont.Object.mem "scope" scope ~enc:(fun o -> o.o_scope)
  |> Jsont.Object.mem "valid" Jsont.string ~enc:(fun o -> o.o_valid)
  |> Jsont.Object.mem "ready" Jsont.string ~enc:(fun o -> o.o_ready)
  |> Jsont.Object.mem "addr" Jsont.string ~enc:(fun o -> o.o_addr)
  |> Jsont.Object.mem "align" Jsont.int ~enc:(fun o -> o.align)
  |> Jsont.Object.opt_mem "write" Jsont.string ~enc:(fun o -> o.o_write)
  |> Jsont.Object.opt_mem "pc" Jsont.string ~enc:(fun o -> o.o_pc)
  |> Jsont.Object.opt_mem "track" tracking ~enc:(fun o -> o.track)
  |> Jsont.Object.opt_mem "ops" ops ~enc:(fun o -> o.ops)
  |> finish

let axi_source =
  obj "axi source" (fun source_id id_mask source origin ->
      { source_id; id_mask = Option.value id_mask ~default:(-1); source; origin })
  |> Jsont.Object.mem "id" Jsont.int ~enc:(fun s -> s.source_id)
  |> Jsont.Object.opt_mem "id_mask" Jsont.int ~enc:(fun s ->
      if s.id_mask = -1 then None else Some s.id_mask)
  |> Jsont.Object.mem "name" Jsont.string ~enc:(fun s -> s.source)
  |> Jsont.Object.opt_mem "origin" origin ~enc:(fun s -> s.origin)
  |> finish

let axi =
  obj_at "axi_master" (fun at axi_scope axi_prefix data_bytes sources ->
      if data_bytes <= 0 || data_bytes land (data_bytes - 1) <> 0 then
        Jsont.Error.msgf at "axi_master: data_bytes %d is not a power of two" data_bytes;
      let ids = List.map (fun s -> s.source_id) sources in
      if List.length (List.sort_uniq compare ids) <> List.length ids then
        Jsont.Error.msgf at "axi_master: a source id is given twice";
      { axi_scope; axi_prefix; data_bytes; sources })
  |> Jsont.Object.mem "scope" scope ~enc:(fun a -> a.axi_scope)
  |> Jsont.Object.mem "prefix" Jsont.string ~enc:(fun a -> a.axi_prefix)
  |> Jsont.Object.mem "data_bytes" Jsont.int ~enc:(fun a -> a.data_bytes)
  |> Jsont.Object.mem "sources" Jsont.(list axi_source) ~enc:(fun a -> a.sources)
  |> finish

let dma =
  obj_at "dma" (fun at dma_scope host device csr_base requester ->
      if host.tl_data_bytes < 16 then
        Jsont.Error.msgf at "dma: the host port carries 16-byte descriptor halves";
      { dma_scope; host; device; csr_base; requester })
  |> Jsont.Object.mem "scope" scope ~enc:(fun d -> d.dma_scope)
  |> Jsont.Object.mem "host" tlul ~enc:(fun d -> d.host)
  |> Jsont.Object.mem "device" tlul ~enc:(fun d -> d.device)
  |> Jsont.Object.mem "csr_base" Jsont.int ~enc:(fun d -> d.csr_base)
  |> Jsont.Object.opt_mem "requester" origin ~enc:(fun d -> d.requester)
  |> finish

let field =
  obj "field" (fun field field_width -> { field; field_width })
  |> Jsont.Object.mem "name" Jsont.string ~enc:(fun f -> f.field)
  |> Jsont.Object.mem "width" Jsont.int ~enc:(fun f -> f.field_width)
  |> finish

let marks =
  obj "marks" (fun m_scope m_valid m_addr m_ports -> { m_scope; m_valid; m_addr; m_ports })
  |> Jsont.Object.mem "scope" scope ~enc:(fun m -> m.m_scope)
  |> Jsont.Object.mem "valid" Jsont.string ~enc:(fun m -> m.m_valid)
  |> Jsont.Object.mem "addr" Jsont.string ~enc:(fun m -> m.m_addr)
  |> Jsont.Object.mem "ports" Jsont.int ~enc:(fun m -> m.m_ports)
  |> finish

let register_file =
  obj_at "register file"
    (fun
      at
      rf_scope
      base
      first
      count
      scoreboard_entries
      fields
      scoreboard
      flushed_scoreboard
      flush
      marks
    ->
      if scoreboard_entries < first + count then
        Jsont.Error.msgf at "register file: %d scoreboard entries for registers up to %d"
          scoreboard_entries
          (first + count - 1);
      {
        rf_scope;
        base;
        first;
        count;
        scoreboard_entries;
        fields;
        scoreboard;
        flushed_scoreboard;
        flush;
        marks;
      })
  |> Jsont.Object.mem "scope" scope ~enc:(fun r -> r.rf_scope)
  |> Jsont.Object.mem "base" Jsont.int ~enc:(fun r -> r.base)
  |> Jsont.Object.mem "first" Jsont.int ~enc:(fun r -> r.first)
  |> Jsont.Object.mem "count" Jsont.int ~enc:(fun r -> r.count)
  |> Jsont.Object.mem "scoreboard_entries" Jsont.int ~enc:(fun r -> r.scoreboard_entries)
  |> Jsont.Object.mem "fields" Jsont.(list field) ~enc:(fun r -> r.fields)
  |> Jsont.Object.mem "scoreboard" Jsont.string ~enc:(fun r -> r.scoreboard)
  |> Jsont.Object.mem "flushed_scoreboard" Jsont.string ~enc:(fun r -> r.flushed_scoreboard)
  |> Jsont.Object.mem "flush" Jsont.string ~enc:(fun r -> r.flush)
  |> Jsont.Object.mem "marks" marks ~enc:(fun r -> r.marks)
  |> finish

let vector_writes =
  obj "vector writes" (fun w_ports w_valid w_data layout -> { w_ports; w_valid; w_data; layout })
  |> Jsont.Object.mem "ports" Jsont.int ~enc:(fun w -> w.w_ports)
  |> Jsont.Object.mem "valid" Jsont.string ~enc:(fun w -> w.w_valid)
  |> Jsont.Object.mem "data" Jsont.string ~enc:(fun w -> w.w_data)
  |> Jsont.Object.mem "layout" Jsont.(list field) ~enc:(fun w -> w.layout)
  |> finish

let vector_registers =
  obj_at "vector registers" (fun at vr_scope vr_base vr_count vlen storage writes ->
      let has name width =
        match List.find_opt (fun f -> f.field = name) writes.layout with
        | Some f when f.field_width = width -> ()
        | Some f ->
            Jsont.Error.msgf at "v_registers.writes.layout: %s is %d bits, not %d" name
              f.field_width width
        | None -> Jsont.Error.msgf at "v_registers.writes.layout: no %s" name
      in
      if vlen mod 8 <> 0 then Jsont.Error.msgf at "v_registers: vlen %d is not a multiple of 8" vlen;
      has "rt_data" vlen;
      has "rt_strobe" (vlen / 8);
      let rec log2 k = if 1 lsl k >= vr_count then k else log2 (k + 1) in
      has "rt_index" (log2 0);
      { vr_scope; vr_base; vr_count; vlen; storage; writes })
  |> Jsont.Object.mem "scope" scope ~enc:(fun r -> r.vr_scope)
  |> Jsont.Object.mem "base" Jsont.int ~enc:(fun r -> r.vr_base)
  |> Jsont.Object.mem "count" Jsont.int ~enc:(fun r -> r.vr_count)
  |> Jsont.Object.mem "vlen" Jsont.int ~enc:(fun r -> r.vlen)
  |> Jsont.Object.mem "storage" Jsont.string ~enc:(fun r -> r.storage)
  |> Jsont.Object.mem "writes" vector_writes ~enc:(fun r -> r.writes)
  |> finish

let vector_dispatch =
  obj_at "vector dispatch" (fun at vd_scope vd_lanes vd_valid vd_ready vd_uop vd_layout units ->
      let need name =
        if not (List.exists (fun f -> f.field = name) vd_layout) then
          Jsont.Error.msgf at "v_dispatch.layout: no %s" name
      in
      List.iter need
        [
          "uop_pc"; "uop_exe_unit"; "csr_vl"; "csr_vstart"; "csr_sew"; "csr_lmul"; "first_uop_valid";
        ];
      { vd_scope; vd_lanes; vd_valid; vd_ready; vd_uop; vd_layout; units })
  |> Jsont.Object.mem "scope" scope ~enc:(fun d -> d.vd_scope)
  |> Jsont.Object.mem "lanes" Jsont.int ~enc:(fun d -> d.vd_lanes)
  |> Jsont.Object.mem "valid" Jsont.string ~enc:(fun d -> d.vd_valid)
  |> Jsont.Object.mem "ready" Jsont.string ~enc:(fun d -> d.vd_ready)
  |> Jsont.Object.mem "uop" Jsont.string ~enc:(fun d -> d.vd_uop)
  |> Jsont.Object.mem "layout" Jsont.(list field) ~enc:(fun d -> d.vd_layout)
  |> Jsont.Object.mem "units" Jsont.(list string) ~enc:(fun d -> d.units)
  |> finish

let csr =
  obj "csr" (fun csr_scope csr_mcause csr_mepc csr_mtval csr_mtvec ->
      { csr_scope; csr_mcause; csr_mepc; csr_mtval; csr_mtvec })
  |> Jsont.Object.mem "scope" scope ~enc:(fun c -> c.csr_scope)
  |> Jsont.Object.mem "mcause" Jsont.string ~enc:(fun c -> c.csr_mcause)
  |> Jsont.Object.mem "mepc" Jsont.string ~enc:(fun c -> c.csr_mepc)
  |> Jsont.Object.mem "mtval" Jsont.string ~enc:(fun c -> c.csr_mtval)
  |> Jsont.Object.mem "mtvec" Jsont.string ~enc:(fun c -> c.csr_mtvec)
  |> finish

let traps =
  obj "traps" (fun t_scope valid mcause mepc mtval decode memory memory_write fetch rvv csr ->
      { t_scope; valid; mcause; mepc; mtval; decode; memory; memory_write; fetch; rvv; csr })
  |> Jsont.Object.mem "scope" scope ~enc:(fun t -> t.t_scope)
  |> Jsont.Object.mem "valid" Jsont.string ~enc:(fun t -> t.valid)
  |> Jsont.Object.mem "mcause" Jsont.string ~enc:(fun t -> t.mcause)
  |> Jsont.Object.mem "mepc" Jsont.string ~enc:(fun t -> t.mepc)
  |> Jsont.Object.mem "mtval" Jsont.string ~enc:(fun t -> t.mtval)
  |> Jsont.Object.mem "decode" Jsont.string ~enc:(fun t -> t.decode)
  |> Jsont.Object.mem "memory" Jsont.string ~enc:(fun t -> t.memory)
  |> Jsont.Object.mem "memory_write" Jsont.string ~enc:(fun t -> t.memory_write)
  |> Jsont.Object.mem "fetch" Jsont.string ~enc:(fun t -> t.fetch)
  |> Jsont.Object.opt_mem "rvv" Jsont.string ~enc:(fun t -> t.rvv)
  |> Jsont.Object.mem "csr" csr ~enc:(fun t -> t.csr)
  |> finish

type registered =
  | Block : {
      name : string;
      codec : 'a Jsont.t;
      get : blocks -> 'a option;
      set : 'a -> blocks -> blocks;
      needs : string list;
    }
      -> registered

let no_blocks =
  {
    dispatch_debug = None;
    retirement_debug = None;
    regfile_writeback = None;
    float_writeback = None;
    dispatch = None;
    lsu = None;
    vme = None;
    axi_master = None;
    dma = None;
    x_registers = None;
    f_registers = None;
    v_registers = None;
    v_dispatch = None;
    traps = None;
  }

let commits_blocks = [ "dispatch_debug"; "retirement_debug"; "regfile_writeback" ]

(* A block is added with its record field, its [no_blocks] entry and one entry here: its name, codec,
   accessors and the blocks that must be described with it. *)
let registry =
  [
    Block
      {
        name = "dispatch_debug";
        codec = dispatch_debug;
        get = (fun b -> b.dispatch_debug);
        set = (fun v b -> { b with dispatch_debug = Some v });
        needs = [];
      };
    Block
      {
        name = "retirement_debug";
        codec = retirement_debug;
        get = (fun b -> b.retirement_debug);
        set = (fun v b -> { b with retirement_debug = Some v });
        needs = [];
      };
    Block
      {
        name = "regfile_writeback";
        codec = writeback;
        get = (fun b -> b.regfile_writeback);
        set = (fun v b -> { b with regfile_writeback = Some v });
        needs = [];
      };
    Block
      {
        name = "float_writeback";
        codec = writeback;
        get = (fun b -> b.float_writeback);
        set = (fun v b -> { b with float_writeback = Some v });
        needs = [];
      };
    Block
      {
        name = "dispatch";
        codec = dispatch;
        get = (fun b -> b.dispatch);
        set = (fun v b -> { b with dispatch = Some v });
        needs = [];
      };
    Block
      {
        name = "lsu";
        codec = lsu;
        get = (fun b -> b.lsu);
        set = (fun v b -> { b with lsu = Some v });
        needs = [];
      };
    Block
      {
        name = "vme";
        codec = vme;
        get = (fun b -> b.vme);
        set = (fun v b -> { b with vme = Some v });
        needs = [];
      };
    Block
      {
        name = "axi_master";
        codec = axi;
        get = (fun b -> b.axi_master);
        set = (fun v b -> { b with axi_master = Some v });
        needs = commits_blocks;
      };
    Block
      {
        name = "dma";
        codec = dma;
        get = (fun b -> b.dma);
        set = (fun v b -> { b with dma = Some v });
        needs = [];
      };
    Block
      {
        name = "x_registers";
        codec = register_file;
        get = (fun b -> b.x_registers);
        set = (fun v b -> { b with x_registers = Some v });
        needs = commits_blocks;
      };
    Block
      {
        name = "f_registers";
        codec = register_file;
        get = (fun b -> b.f_registers);
        set = (fun v b -> { b with f_registers = Some v });
        needs = commits_blocks;
      };
    Block
      {
        name = "v_registers";
        codec = vector_registers;
        get = (fun b -> b.v_registers);
        set = (fun v b -> { b with v_registers = Some v });
        needs = commits_blocks;
      };
    Block
      {
        name = "v_dispatch";
        codec = vector_dispatch;
        get = (fun b -> b.v_dispatch);
        set = (fun v b -> { b with v_dispatch = Some v });
        needs = [ "dispatch_debug" ];
      };
    Block
      {
        name = "traps";
        codec = traps;
        get = (fun b -> b.traps);
        set = (fun v b -> { b with traps = Some v });
        needs = [ "dispatch_debug"; "retirement_debug" ];
      };
  ]

let () =
  let names = List.map (fun (Block b) -> b.name) registry in
  List.iter
    (fun (Block b) ->
      List.iter
        (fun n ->
          if not (List.mem n names) then invalid_arg ("Platform: " ^ b.name ^ " needs " ^ n))
        b.needs)
    registry

let known_blocks = List.map (fun (Block b) -> (b.name, b.needs)) registry
let present blocks n = List.exists (fun (Block b) -> b.name = n && b.get blocks <> None) registry

(* The blocks object is read as generic JSON so that each member can be decoded by name, and a
   failure reported at the member's own location. *)
let blocks_codec =
  let decode json =
    match json with
    | Jsont.Object (mems, at) ->
        let in_member name e = Jsont.Error.push_object ("blocks object", at) name e in
        let fail (name, name_meta) v fmt =
          Format.kasprintf
            (fun m ->
              in_member (name, name_meta)
                (Jsont.Error.make_msg Jsont.Error.Context.empty (Jsont.Json.meta v) m))
            fmt
        in
        let decode blocks ((name, name_meta), v) =
          match List.find_opt (fun (Block b) -> b.name = name) registry with
          | None ->
              Jsont.Error.msgf name_meta "Unexpected member %s for blocks object. Known blocks: %s"
                name
                (String.concat ", " (List.map fst known_blocks))
          | Some (Block b) -> (
              if b.get blocks <> None then fail (name, name_meta) v "%s: given twice" name;
              match Jsont.Json.decode' b.codec v with
              | Ok x -> b.set x blocks
              | Error e -> in_member (name, name_meta) e)
        in
        let blocks = List.fold_left decode no_blocks mems in
        List.iter
          (fun (Block b) ->
            if b.get blocks <> None then
              match List.filter (fun n -> not (present blocks n)) b.needs with
              | [] -> ()
              | missing ->
                  let name, v = List.find (fun ((n, _), _) -> n = b.name) mems in
                  fail name v "%s: needs %s, which the description does not give" b.name
                    (String.concat ", " missing))
          registry;
        blocks
    | _ -> Jsont.Json.error_sort ~exp:Jsont.Sort.Object json
  in
  let encode blocks =
    Jsont.Json.object'
      (List.filter_map
         (fun (Block b) ->
           Option.map
             (fun x -> (Jsont.Json.name b.name, Result.get_ok (Jsont.Json.encode' b.codec x)))
             (b.get blocks))
         registry)
  in
  Jsont.map ~kind:"blocks" ~dec:decode ~enc:encode Jsont.json

let configuration =
  obj "configuration" (fun config top_level trace_root -> { config; top_level; trace_root })
  |> Jsont.Object.mem "name" Jsont.string ~enc:(fun (c : configuration) -> c.config)
  |> Jsont.Object.mem "top_level" Jsont.string ~enc:(fun (c : configuration) -> c.top_level)
  |> Jsont.Object.mem "trace_root" scope ~enc:(fun (c : configuration) -> c.trace_root)
  |> finish

let sample =
  Jsont.enum ~kind:"sample rule"
    [
      ("after_falling", Hwfrp.Trace.After_falling);
      ("before_rising", Before_rising);
      ("after_rising", After_rising);
    ]

let reset =
  obj_at "reset" (fun at reset_signal reset_active ->
      if reset_signal = "" then Jsont.Error.msgf at "reset: the signal has no name";
      { reset_signal; reset_active })
  |> Jsont.Object.mem "signal" Jsont.string ~enc:(fun r -> r.reset_signal)
  |> Jsont.Object.mem "active"
       (Jsont.enum ~kind:"reset level" [ ("low", false); ("high", true) ])
       ~enc:(fun r -> r.reset_active)
  |> finish

let schema_version = Jsont.enum ~kind:"schema_version" [ ("1.0", ()) ]

let jsont =
  obj "platform" (fun () family configurations clock reset sample blocks ->
      { family; configurations; clock; reset; sample; blocks })
  |> Jsont.Object.mem "schema_version" schema_version ~enc:(fun _ -> ())
  |> Jsont.Object.mem "name" Jsont.string ~enc:(fun f -> f.family)
  |> Jsont.Object.mem "configurations"
       Jsont.(list configuration)
       ~enc:(fun (f : family) -> f.configurations)
  |> Jsont.Object.mem "clock" Jsont.string ~enc:(fun (f : family) -> f.clock)
  |> Jsont.Object.opt_mem "reset" reset ~enc:(fun (f : family) -> f.reset)
  |> Jsont.Object.mem "sample" sample ~enc:(fun (f : family) -> f.sample)
  |> Jsont.Object.mem "blocks" blocks_codec ~enc:(fun (f : family) -> f.blocks)
  |> finish

let of_string ?file s = Jsont_bytesrw.decode_string ~locs:true ?file jsont s

let configurations f =
  List.map
    (fun c ->
      {
        name = c.config;
        family_name = f.family;
        top_level = c.top_level;
        trace_root = c.trace_root;
        clock = f.clock;
        reset = f.reset;
        sample = f.sample;
        blocks = f.blocks;
      })
    f.configurations

let builtin =
  lazy
    (List.concat_map
       (fun (name, text) ->
         match of_string ~file:(name ^ ".json") text with
         | Ok f -> configurations f
         | Error e -> failwith e)
       Builtin_platforms.all)

let find name =
  match List.find_opt (fun p -> p.name = name) (Lazy.force builtin) with
  | Some p -> Ok p
  | None -> (
      let file, config =
        match String.rindex_opt name ':' with
        | Some i ->
            (String.sub name 0 i, Some (String.sub name (i + 1) (String.length name - i - 1)))
        | None -> (name, None)
      in
      match In_channel.with_open_bin file In_channel.input_all with
      | exception Sys_error _ ->
          Error
            (Printf.sprintf
               "no platform %s: give a configuration (coralview platforms) or a JSON file" name)
      | text -> (
          match of_string ~file text with
          | Error e -> Error e
          | Ok f -> (
              match (configurations f, config) with
              | [ p ], None -> Ok p
              | ps, Some c -> (
                  match List.find_opt (fun p -> p.name = c) ps with
                  | Some p -> Ok p
                  | None -> Error (Printf.sprintf "%s has no configuration %s" file c))
              | _, None -> Error (Printf.sprintf "%s has several configurations: add :CONFIG" file))
          ))

let root p = Vcd_types.Reference.of_list p.trace_root
let scope p rel = Vcd_types.Reference.of_list (p.trace_root @ rel)

let blocks p =
  List.filter_map (fun (Block b) -> if b.get p.blocks <> None then Some b.name else None) registry

let name_of pattern n =
  match String.index_opt pattern '%' with
  | Some i when i + 1 < String.length pattern && pattern.[i + 1] = 'd' ->
      String.sub pattern 0 i ^ string_of_int n
      ^ String.sub pattern (i + 2) (String.length pattern - i - 2)
  | _ -> pattern
