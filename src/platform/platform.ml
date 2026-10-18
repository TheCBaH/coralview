[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

type dispatch_debug = { dd_scope : string list; dd_lanes : int }
type retirement_debug = { rd_scope : string list; rd_lanes : int; idx_width : int; trap : bool }
type writeback = { wb_scope : string list; ports : int }

type dispatch = {
  d_scope : string list;
  d_lanes : int;
  try_dispatch : string list;
  comb : string list;
  fcomb : string list option;
  rvv_queue : string option;
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

type ops = { enqueue : port; issue : port }

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

type tlul = { tl_prefix : string; tl_data_bytes : int; d_ready : bool }

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
  traps : traps option;
}

type configuration = { config : string; top_level : string; trace_root : string list }

type family = {
  family : string;
  configurations : configuration list;
  clock : string;
  sample : Hwfrp.Trace.sample_rule;
  blocks : blocks;
}

type t = {
  name : string;
  family_name : string;
  top_level : string;
  trace_root : string list;
  clock : string;
  sample : Hwfrp.Trace.sample_rule;
  blocks : blocks;
}

let obj kind f = Jsont.Object.map ~kind f
let finish m = Jsont.Object.(finish (error_unknown m))
let scope = Jsont.(list string)

let dispatch_debug =
  obj "dispatch_debug" (fun dd_scope dd_lanes -> { dd_scope; dd_lanes })
  |> Jsont.Object.mem "scope" scope ~enc:(fun b -> b.dd_scope)
  |> Jsont.Object.mem "lanes" Jsont.int ~enc:(fun b -> b.dd_lanes)
  |> finish

let retirement_debug =
  obj "retirement_debug" (fun rd_scope rd_lanes idx_width trap ->
      { rd_scope; rd_lanes; idx_width; trap })
  |> Jsont.Object.mem "scope" scope ~enc:(fun b -> b.rd_scope)
  |> Jsont.Object.mem "lanes" Jsont.int ~enc:(fun b -> b.rd_lanes)
  |> Jsont.Object.mem "idx_width" Jsont.int ~enc:(fun b -> b.idx_width)
  |> Jsont.Object.mem "trap" Jsont.bool ~enc:(fun b -> b.trap)
  |> finish

let writeback =
  obj "writeback" (fun wb_scope ports -> { wb_scope; ports })
  |> Jsont.Object.mem "scope" scope ~enc:(fun b -> b.wb_scope)
  |> Jsont.Object.mem "ports" Jsont.int ~enc:(fun b -> b.ports)
  |> finish

let per_lane name lanes l =
  if List.length l <> lanes then
    Jsont.Error.msgf Jsont.Meta.none "dispatch.%s: %d names for %d lanes" name (List.length l) lanes

let dispatch =
  obj "dispatch" (fun d_scope d_lanes try_dispatch comb fcomb rvv_queue ->
      per_lane "try_dispatch" d_lanes try_dispatch;
      per_lane "comb" d_lanes comb;
      Option.iter (per_lane "fcomb" d_lanes) fcomb;
      { d_scope; d_lanes; try_dispatch; comb; fcomb; rvv_queue })
  |> Jsont.Object.mem "scope" scope ~enc:(fun b -> b.d_scope)
  |> Jsont.Object.mem "lanes" Jsont.int ~enc:(fun b -> b.d_lanes)
  |> Jsont.Object.mem "try_dispatch" Jsont.(list string) ~enc:(fun b -> b.try_dispatch)
  |> Jsont.Object.mem "comb" Jsont.(list string) ~enc:(fun b -> b.comb)
  |> Jsont.Object.opt_mem "fcomb" Jsont.(list string) ~enc:(fun b -> b.fcomb)
  |> Jsont.Object.opt_mem "rvv_queue" Jsont.string ~enc:(fun b -> b.rvv_queue)
  |> finish

let lsu =
  obj "lsu" (fun lsu_scope tcm_ready -> { lsu_scope; tcm_ready })
  |> Jsont.Object.mem "scope" scope ~enc:(fun b -> b.lsu_scope)
  |> Jsont.Object.mem "tcm_ready" Jsont.bool ~enc:(fun b -> b.tcm_ready)
  |> finish

let vme =
  obj "vme" (fun vme_scope blocks ports_per_block tiles subtiles subtile_bytes ->
      { vme_scope; blocks; ports_per_block; tiles; subtiles; subtile_bytes })
  |> Jsont.Object.mem "scope" scope ~enc:(fun b -> b.vme_scope)
  |> Jsont.Object.mem "blocks" Jsont.int ~enc:(fun (b : vme) -> b.blocks)
  |> Jsont.Object.mem "ports_per_block" Jsont.int ~enc:(fun b -> b.ports_per_block)
  |> Jsont.Object.mem "tiles" Jsont.int ~enc:(fun b -> b.tiles)
  |> Jsont.Object.mem "subtiles" Jsont.int ~enc:(fun b -> b.subtiles)
  |> Jsont.Object.mem "subtile_bytes" Jsont.int ~enc:(fun b -> b.subtile_bytes)
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

let origin =
  obj "origin" (fun o_scope o_valid o_ready o_addr align o_write o_pc ops ->
      if align <= 0 || align land (align - 1) <> 0 then
        Jsont.Error.msgf Jsont.Meta.none "origin: align %d is not a power of two" align;
      if ops <> None && o_pc = None then Jsont.Error.msgf Jsont.Meta.none "origin: ops without a pc";
      { o_scope; o_valid; o_ready; o_addr; align; o_write; o_pc; ops })
  |> Jsont.Object.mem "scope" scope ~enc:(fun o -> o.o_scope)
  |> Jsont.Object.mem "valid" Jsont.string ~enc:(fun o -> o.o_valid)
  |> Jsont.Object.mem "ready" Jsont.string ~enc:(fun o -> o.o_ready)
  |> Jsont.Object.mem "addr" Jsont.string ~enc:(fun o -> o.o_addr)
  |> Jsont.Object.mem "align" Jsont.int ~enc:(fun o -> o.align)
  |> Jsont.Object.opt_mem "write" Jsont.string ~enc:(fun o -> o.o_write)
  |> Jsont.Object.opt_mem "pc" Jsont.string ~enc:(fun o -> o.o_pc)
  |> Jsont.Object.opt_mem "ops" ops ~enc:(fun o -> o.ops)
  |> finish

let axi_source =
  obj "axi source" (fun source_id source origin -> { source_id; source; origin })
  |> Jsont.Object.mem "id" Jsont.int ~enc:(fun s -> s.source_id)
  |> Jsont.Object.mem "name" Jsont.string ~enc:(fun s -> s.source)
  |> Jsont.Object.opt_mem "origin" origin ~enc:(fun s -> s.origin)
  |> finish

let axi =
  obj "axi_master" (fun axi_scope axi_prefix data_bytes sources ->
      if data_bytes <= 0 || data_bytes land (data_bytes - 1) <> 0 then
        Jsont.Error.msgf Jsont.Meta.none "axi_master: data_bytes %d is not a power of two"
          data_bytes;
      let ids = List.map (fun s -> s.source_id) sources in
      if List.length (List.sort_uniq compare ids) <> List.length ids then
        Jsont.Error.msgf Jsont.Meta.none "axi_master: a source id is given twice";
      { axi_scope; axi_prefix; data_bytes; sources })
  |> Jsont.Object.mem "scope" scope ~enc:(fun a -> a.axi_scope)
  |> Jsont.Object.mem "prefix" Jsont.string ~enc:(fun a -> a.axi_prefix)
  |> Jsont.Object.mem "data_bytes" Jsont.int ~enc:(fun a -> a.data_bytes)
  |> Jsont.Object.mem "sources" Jsont.(list axi_source) ~enc:(fun a -> a.sources)
  |> finish

let tlul =
  obj "tlul port" (fun tl_prefix tl_data_bytes d_ready ->
      if tl_data_bytes <= 0 || tl_data_bytes land (tl_data_bytes - 1) <> 0 then
        Jsont.Error.msgf Jsont.Meta.none "tlul: data_bytes %d is not a power of two" tl_data_bytes;
      { tl_prefix; tl_data_bytes; d_ready })
  |> Jsont.Object.mem "prefix" Jsont.string ~enc:(fun t -> t.tl_prefix)
  |> Jsont.Object.mem "data_bytes" Jsont.int ~enc:(fun t -> t.tl_data_bytes)
  |> Jsont.Object.mem "d_ready" Jsont.bool ~enc:(fun t -> t.d_ready)
  |> finish

let dma =
  obj "dma" (fun dma_scope host device csr_base requester ->
      if host.tl_data_bytes < 16 then
        Jsont.Error.msgf Jsont.Meta.none "dma: the host port carries 16-byte descriptor halves";
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
  obj "register file"
    (fun rf_scope base first count fields scoreboard flushed_scoreboard flush marks ->
      { rf_scope; base; first; count; fields; scoreboard; flushed_scoreboard; flush; marks })
  |> Jsont.Object.mem "scope" scope ~enc:(fun r -> r.rf_scope)
  |> Jsont.Object.mem "base" Jsont.int ~enc:(fun r -> r.base)
  |> Jsont.Object.mem "first" Jsont.int ~enc:(fun r -> r.first)
  |> Jsont.Object.mem "count" Jsont.int ~enc:(fun r -> r.count)
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
  obj "vector registers" (fun vr_scope vr_base vr_count vlen storage writes ->
      let has name width =
        match List.find_opt (fun f -> f.field = name) writes.layout with
        | Some f when f.field_width = width -> ()
        | Some f ->
            Jsont.Error.msgf Jsont.Meta.none "v_registers.writes.layout: %s is %d bits, not %d" name
              f.field_width width
        | None -> Jsont.Error.msgf Jsont.Meta.none "v_registers.writes.layout: no %s" name
      in
      if vlen mod 8 <> 0 then Jsont.Error.msgf Jsont.Meta.none "v_registers: vlen %d" vlen;
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

let blocks =
  obj "blocks"
    (fun
      dispatch_debug
      retirement_debug
      regfile_writeback
      float_writeback
      dispatch
      lsu
      vme
      axi_master
      dma
      x_registers
      f_registers
      v_registers
      traps
    ->
      {
        dispatch_debug;
        retirement_debug;
        regfile_writeback;
        float_writeback;
        dispatch;
        lsu;
        vme;
        axi_master;
        dma;
        x_registers;
        f_registers;
        v_registers;
        traps;
      })
  |> Jsont.Object.opt_mem "dispatch_debug" dispatch_debug ~enc:(fun b -> b.dispatch_debug)
  |> Jsont.Object.opt_mem "retirement_debug" retirement_debug ~enc:(fun b -> b.retirement_debug)
  |> Jsont.Object.opt_mem "regfile_writeback" writeback ~enc:(fun b -> b.regfile_writeback)
  |> Jsont.Object.opt_mem "float_writeback" writeback ~enc:(fun b -> b.float_writeback)
  |> Jsont.Object.opt_mem "dispatch" dispatch ~enc:(fun b -> b.dispatch)
  |> Jsont.Object.opt_mem "lsu" lsu ~enc:(fun b -> b.lsu)
  |> Jsont.Object.opt_mem "vme" vme ~enc:(fun b -> b.vme)
  |> Jsont.Object.opt_mem "axi_master" axi ~enc:(fun b -> b.axi_master)
  |> Jsont.Object.opt_mem "dma" dma ~enc:(fun b -> b.dma)
  |> Jsont.Object.opt_mem "x_registers" register_file ~enc:(fun b -> b.x_registers)
  |> Jsont.Object.opt_mem "f_registers" register_file ~enc:(fun b -> b.f_registers)
  |> Jsont.Object.opt_mem "v_registers" vector_registers ~enc:(fun b -> b.v_registers)
  |> Jsont.Object.opt_mem "traps" traps ~enc:(fun b -> b.traps)
  |> finish

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

let schema_version = Jsont.enum ~kind:"schema_version" [ ("1.0", ()) ]

let jsont =
  obj "platform" (fun () family configurations clock sample blocks ->
      { family; configurations; clock; sample; blocks })
  |> Jsont.Object.mem "schema_version" schema_version ~enc:(fun _ -> ())
  |> Jsont.Object.mem "name" Jsont.string ~enc:(fun f -> f.family)
  |> Jsont.Object.mem "configurations"
       Jsont.(list configuration)
       ~enc:(fun (f : family) -> f.configurations)
  |> Jsont.Object.mem "clock" Jsont.string ~enc:(fun (f : family) -> f.clock)
  |> Jsont.Object.mem "sample" sample ~enc:(fun (f : family) -> f.sample)
  |> Jsont.Object.mem "blocks" blocks ~enc:(fun (f : family) -> f.blocks)
  |> finish

let of_string ?file s = Jsont_bytesrw.decode_string ?file jsont s

let configurations f =
  List.map
    (fun c ->
      {
        name = c.config;
        family_name = f.family;
        top_level = c.top_level;
        trace_root = c.trace_root;
        clock = f.clock;
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
  let b = p.blocks in
  List.filter_map
    (fun (name, present) -> if present then Some name else None)
    [
      ("dispatch_debug", b.dispatch_debug <> None);
      ("retirement_debug", b.retirement_debug <> None);
      ("regfile_writeback", b.regfile_writeback <> None);
      ("float_writeback", b.float_writeback <> None);
      ("dispatch", b.dispatch <> None);
      ("lsu", b.lsu <> None);
      ("vme", b.vme <> None);
      ("axi_master", b.axi_master <> None);
      ("dma", b.dma <> None);
      ("x_registers", b.x_registers <> None);
      ("f_registers", b.f_registers <> None);
      ("v_registers", b.v_registers <> None);
      ("traps", b.traps <> None);
    ]

let name_of pattern n =
  match String.index_opt pattern '%' with
  | Some i when i + 1 < String.length pattern && pattern.[i + 1] = 'd' ->
      String.sub pattern 0 i ^ string_of_int n
      ^ String.sub pattern (i + 2) (String.length pattern - i - 2)
  | _ -> pattern
