[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Hwfrp

type write = {
  cycle : int;
  block : int;
  port : int;
  pc : int option;
  tile : int;
  sub : int;
  mask : int;
  data : Bits.t;
}

let name = "tiles"
let doc = "VME tile register writes, by PC."
let needs = [ "vme" ]

module TM = Map.Make (struct
  type t = int * int

  let compare = compare
end)

module Config = struct
  type t = unit

  let default = ()
end

module Event = struct
  type t = Tile_write of write

  let write =
    Codec.case "tiles.write"
      (fun w -> Tile_write w)
      (Jsont.Object.map (fun cycle block port pc tile sub mask data ->
           { cycle; block; port; pc; tile; sub; mask; data })
      |> Jsont.Object.mem "cycle" Jsont.int ~enc:(fun w -> w.cycle)
      |> Jsont.Object.mem "block" Jsont.int ~enc:(fun w -> w.block)
      |> Jsont.Object.mem "port" Jsont.int ~enc:(fun w -> w.port)
      |> Codec.opt (fun w -> w.pc) "pc" Jsont.int
      |> Jsont.Object.mem "tile" Jsont.int ~enc:(fun w -> w.tile)
      |> Jsont.Object.mem "sub" Jsont.int ~enc:(fun w -> w.sub)
      |> Jsont.Object.mem "mask" Jsont.int ~enc:(fun w -> w.mask)
      |> Jsont.Object.mem "data" Codec.bits ~enc:(fun w -> w.data)
      |> Jsont.Object.finish)

  let jsont =
    Codec.cases "tiles.event"
      (fun (Tile_write w) -> Jsont.Object.Case.value write w)
      Jsont.Object.Case.[ make write ]

  let cycle (Tile_write w) = w.cycle
  let pc (Tile_write w) = w.pc
end

module Summary = struct
  type t = { writes : int; file : ((int * int) * Bits.t) list  (** By tile and sub-tile. *) }

  let entry =
    Jsont.Object.map ~kind:"subtile" (fun tile sub data -> ((tile, sub), data))
    |> Jsont.Object.mem "tile" Jsont.int ~enc:(fun ((t, _), _) -> t)
    |> Jsont.Object.mem "sub" Jsont.int ~enc:(fun ((_, s), _) -> s)
    |> Jsont.Object.mem "data" Codec.bits ~enc:snd
    |> Jsont.Object.finish

  let jsont =
    Codec.record "tiles.summary" (fun writes file -> { writes; file })
    |> Jsont.Object.mem "writes" Jsont.int ~enc:(fun s -> s.writes)
    |> Jsont.Object.mem "file" (Jsont.list entry) ~enc:(fun s -> s.file)
    |> Jsont.Object.finish
end

let log2 n =
  let rec go k = if 1 lsl k >= n then k else go (k + 1) in
  go 0

(* Merge [data] into [old] under the byte enables. *)
let merge old mask data =
  let n = Bits.width old / 8 in
  Bits.concat
    (List.init n (fun k ->
         let b = n - 1 - k in
         Bits.field (if (mask lsr b) land 1 = 1 then data else old) ~lo:(8 * b) ~width:8))

let build () (c : _ Core.t) =
  let v = Core.block c "vme" c.platform.blocks.vme in
  let sc = Core.scope c v.vme_scope in
  let lanes = v.blocks * v.ports_per_block in
  let vec name width purpose =
    Bind.signal sc name { Bind.bits with dwidth = Exact width } ~purpose
  in
  let bytes = v.subtile_bytes and wt = log2 v.tiles and ws = log2 v.subtiles in
  (* [logic [B-1:0][P-1:0][W-1:0] x]: element [b][p] at bits (b*P + p)*W. *)
  let elt x ~w b p = Bits.field x ~lo:(((b * v.ports_per_block) + p) * w) ~width:w in
  let elt_int x ~w b p = Bits.to_int_exn (elt x ~w b p) in
  let writes =
    let open Sig in
    let+ en = vec "writeEn" (lanes * bytes) "tile write byte enables"
    and+ pe_en = vec "peWriteEn" (lanes * bytes) "PE array write byte enables"
    and+ pcs = vec "peWritePc" (v.blocks * 32) "PC of each block's PE write"
    and+ mt = vec "writeMtIdx" (lanes * wt) "written tile"
    and+ sub = vec "writeSubIdx" (lanes * ws) "written sub-tile"
    and+ data = vec "writeData" (lanes * bytes * 8) "written data"
    and+ cycle = cycle c.clk in
    List.concat_map
      (fun block ->
        List.filter_map
          (fun port ->
            let mask = elt_int en ~w:bytes block port in
            if mask = 0 then None
            else
              Some
                {
                  cycle;
                  block;
                  port;
                  pc =
                    (if elt_int pe_en ~w:bytes block port = mask then
                       Some (Bits.to_int_exn (Bits.field pcs ~lo:(32 * block) ~width:32))
                     else None);
                  tile = elt_int mt ~w:wt block port;
                  sub = elt_int sub ~w:ws block port;
                  mask;
                  data = elt data ~w:(bytes * 8) block port;
                })
          (List.init v.ports_per_block Fun.id))
      (List.init v.blocks Fun.id)
  in
  let step (file, n) ws =
    ( ( List.fold_left
          (fun file w ->
            let old =
              Option.value (TM.find_opt (w.tile, w.sub) file) ~default:(Bits.zero (bytes * 8))
            in
            TM.add (w.tile, w.sub) (merge old w.mask w.data) file)
          file ws,
        n + List.length ws ),
      List.map (fun w -> Event.Tile_write w) ws )
  in
  let out, st =
    Machine.run
      {
        name;
        init = (TM.empty, 0);
        step = (fun ~tick:_ s ws -> if ws = [] then (s, []) else step s ws);
        finish = (fun _ -> []);
        every_tick = true;
      }
      writes
  in
  ( out,
    fun _ ->
      let file, writes = Sig.peek st in
      { Summary.writes; file = TM.bindings file } )

let text (ctx : Text.ctx) events (s : Summary.t) =
  let shown = ref 0 in
  let by_pc =
    List.fold_left
      (fun m (Event.Tile_write w) ->
        if !shown < ctx.limit then begin
          incr shown;
          Printf.printf "%8d blk%d port%d %s tile %2d sub %2d mask %04x %s\n" w.cycle w.block w.port
            (match w.pc with Some pc -> Printf.sprintf "pc %08x" pc | None -> "load       ")
            w.tile w.sub w.mask (Bits.to_hex w.data)
        end;
        let c, first, _ = Option.value (List.assoc_opt w.pc m) ~default:(0, w.cycle, w.cycle) in
        (w.pc, (c + 1, first, w.cycle)) :: List.remove_assoc w.pc m)
      [] events
  in
  Printf.printf "root %s: %d sub-tile writes; %d of 256 sub-tiles written\n" ctx.root s.writes
    (List.length s.file);
  List.sort compare by_pc
  |> List.iter (fun (pc, (c, first, last)) ->
      Printf.printf "  %s: %d writes, cycles %d-%d\n"
        (match pc with Some pc -> Printf.sprintf "pc %08x" pc | None -> "tile loads ")
        c first last)
