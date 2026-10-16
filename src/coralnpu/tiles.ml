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

let model = "tiles"
let needs = [ "vme" ]

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

let graph (c : _ Core.t) f =
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
  let file = Hashtbl.create 256 in
  Ev.subscribe
    (Ev.filter (fun l -> l <> []) (Ev.when_ (Sig.const c.clk true) writes))
    (List.iter (fun w ->
         let old =
           Option.value (Hashtbl.find_opt file (w.tile, w.sub)) ~default:(Bits.zero (bytes * 8))
         in
         Hashtbl.replace file (w.tile, w.sub) (merge old w.mask w.data);
         f w));
  fun _ -> file

let run p tr f =
  let (Core.Any c) = Core.bind p tr ~model in
  let finish = graph c f in
  finish (Core.run c)
