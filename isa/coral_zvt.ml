[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

module Row = Riscv_family_encode.Riscv_table_row
module Ext = Riscv_family_encode.Extensions

let feature = "xcoralzvt"

(* RTL decodes nf 0..2 only; MPACT M4 also decodes the 64-bit forms. *)
let excluded = [ "vtle64"; "vtse64" ]

type instruction = Zvt_rows.instruction = {
  mnemonic : string;
  mask : string;
  match_ : string;
  fields : (string * int list) list;
  disasm : string;
  operands : string list;
}

let ( let* ) = Result.bind

(* A field's least significant bit; MPACT lists its bits most significant first. *)
let lsb i name =
  match List.assoc_opt name i.fields with
  | Some (_ :: _ as bits) ->
      let low = List.nth bits (List.length bits - 1) in
      if List.mapi (fun k b -> b - (List.length bits - 1 - k)) bits |> List.for_all (( = ) low) then
        Ok low
      else Error (Printf.sprintf "%s: field %s is not contiguous" i.mnemonic name)
  | _ -> Error (Printf.sprintf "%s: no field %s in its format" i.mnemonic name)

(* MPACT's operand names, which its getters map to fields, as Rivet operands. *)
let operand i ~memory name =
  match name with
  | "rd" | "rs2" ->
      let* lsb = lsb i name in
      Ok (Row.Gpr { lsb; nonzero = false })
  | "rs1" ->
      let* lsb = lsb i "rs1" in
      Ok (if memory then Row.Mem_zero { base = lsb } else Row.Gpr { lsb; nonzero = false })
  | "matA" | "matB" | "matVd" ->
      let* lsb = lsb i (match name with "matA" -> "vs2" | "matB" -> "vs1" | _ -> "vd") in
      Ok (Row.Vreg { lsb })
  | "mtd" -> Ok (Row.Indexed { prefix = "mt"; lsb = 8; width = 4; scale = 1 })
  | _ -> Error (Printf.sprintf "%s: no Rivet operand for %s" i.mnemonic name)

(* MPACT spells msetmtype without rd, which the RTL writes as for vsetvl, and msetmtypei with no
   operands at all: its immediates are mtwiden in the rs1 field and the SEW in bits 24:23. *)
let operands i =
  let all l =
    List.fold_right
      (fun o acc ->
        let* o = o in
        let* acc = acc in
        Ok (o :: acc))
      l (Ok [])
  in
  match i.mnemonic with
  | "msetmtype" -> all (List.map (operand i ~memory:false) [ "rd"; "rs1"; "rs2" ])
  | "msetmtypei" ->
      let* rd = operand i ~memory:false "rd" in
      let* uimm = lsb i "uimm5" in
      Ok [ rd; Row.Uimm { lsb = uimm; width = 5 }; Row.Uimm { lsb = 23; width = 2 } ]
  | _ ->
      let memory name = String.contains i.disasm '(' && name = "rs1" in
      all (List.map (fun name -> operand i ~memory:(memory name) name) i.operands)

let field_mask lsb width = Int64.shift_left (Int64.pred (Int64.shift_left 1L width)) lsb

let operand_mask = function
  | Row.Gpr { lsb; _ } | Row.Vreg { lsb } | Row.Mem_zero { base = lsb } -> field_mask lsb 5
  | Row.Uimm { lsb; width } | Row.Indexed { lsb; width; _ } -> field_mask lsb width
  | _ -> 0L

let row i =
  let* operands = operands i in
  match (Int64.of_string_opt i.mask, Int64.of_string_opt i.match_) with
  | Some mask, _ when List.exists (fun o -> Int64.logand mask (operand_mask o) <> 0L) operands ->
      Error (i.mnemonic ^ ": an operand overlaps the encoding's fixed bits")
  | Some mask, Some match_ ->
      Ok
        {
          Row.mnemonic = i.mnemonic;
          mask;
          match_;
          operands;
          xlen = 0;
          feature;
          source = "mpact-riscv/" ^ i.mnemonic;
        }
  | _ -> Error (i.mnemonic ^ ": bad mask or match")

let component mnemonics : Target_component.t =
  {
    id = "coralnpu." ^ feature;
    feature;
    requires = [ "zve32x" ];
    conflicts = [];
    implies = [];
    default_on = false;
    xlens = [];
    not_applicable = None;
    summary = "Coral NPU Zvt matrix instructions, as its MPACT M4 model decodes them";
    forms =
      List.map
        (fun m ->
          {
            Target_component.label = m;
            mnemonics = [ m ];
            sources = [ { upstream = "mpact-riscv"; name = m } ];
            legal = None;
          })
        mnemonics;
  }

let instructions = List.filter (fun i -> not (List.mem i.mnemonic excluded)) Zvt_rows.instructions

let definition =
  lazy
    (let* rows =
       List.fold_right
         (fun i acc ->
           let* r = row i in
           let* acc = acc in
           Ok (r :: acc))
         instructions (Ok [])
     in
     let def : Ext.definition =
       {
         components = [ component (List.map (fun (r : Row.row) -> r.mnemonic) rows) ];
         rows = Array.of_list rows;
       }
     in
     Result.map_error (String.concat "; ") (Ext.make ~xlen:32 def))

let definition () = Lazy.force definition
let patterns = [ 0L; -1L; 0x5555_5555L; 0xaaaa_aaaaL ]

let samples () =
  let* (_ : Ext.Validated.t) = definition () in
  List.fold_right
    (fun i acc ->
      let* r = row i in
      let* acc = acc in
      let free = List.fold_left (fun m o -> Int64.logor m (operand_mask o)) 0L r.Row.operands in
      let word p = Int64.to_int (Int64.logor r.Row.match_ (Int64.logand p free)) in
      Ok (List.map (fun p -> (r.Row.mnemonic, word p)) patterns @ acc))
    instructions (Ok [])
