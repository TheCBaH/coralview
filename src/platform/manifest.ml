[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

type region = { region : string; base : int; size : int }

type configuration = {
  name : string;
  top_level : string option;
  extensions : string list;
  tile_registers : int option;
  regions : region list;
}

type t = { configurations : configuration list }

let obj kind f = Jsont.Object.map ~kind f
let finish m = Jsont.Object.(finish (skip_unknown m))

let region =
  obj "memory region" (fun region base size -> { region; base; size })
  |> Jsont.Object.mem "name" Jsont.string ~enc:(fun r -> r.region)
  |> Jsont.Object.mem "base_address" Jsont.int ~enc:(fun r -> r.base)
  |> Jsont.Object.mem "size_bytes" Jsont.int ~enc:(fun r -> r.size)
  |> finish

let simulation =
  obj "simulation" Fun.id
  |> Jsont.Object.mem "top_level" (Jsont.option Jsont.string) ~dec_absent:None ~enc:Fun.id
  |> finish

let matrix =
  obj "matrix" Fun.id
  |> Jsont.Object.mem "tile_registers" (Jsont.option Jsont.int) ~dec_absent:None ~enc:Fun.id
  |> finish

let isa =
  obj "isa" (fun extensions matrix -> (extensions, Option.join matrix))
  |> Jsont.Object.mem "extensions" Jsont.(list string) ~enc:fst
  |> Jsont.Object.opt_mem "matrix" matrix ~enc:(fun (_, m) -> Some m)
  |> finish

let configuration =
  obj "configuration" (fun name top_level (extensions, tile_registers) regions ->
      { name; top_level; extensions; tile_registers; regions })
  |> Jsont.Object.mem "name" Jsont.string ~enc:(fun c -> c.name)
  |> Jsont.Object.mem "simulation" simulation ~enc:(fun c -> c.top_level)
  |> Jsont.Object.mem "isa" isa ~enc:(fun c -> (c.extensions, c.tile_registers))
  |> Jsont.Object.mem "memory_regions" Jsont.(list region) ~enc:(fun c -> c.regions)
  |> finish

let schema_version = Jsont.enum ~kind:"schema_version" [ ("1.0", ()) ]

let jsont =
  obj "hardware configurations" (fun () configurations -> { configurations })
  |> Jsont.Object.mem "schema_version" schema_version ~enc:(fun _ -> ())
  |> Jsont.Object.mem "configurations" Jsont.(list configuration) ~enc:(fun t -> t.configurations)
  |> finish

let load file =
  match In_channel.with_open_bin file In_channel.input_all with
  | text -> Jsont_bytesrw.decode_string ~file jsont text
  | exception Sys_error e -> Error e

let find t name = List.find_opt (fun c -> c.name = name) t.configurations
let region_of c addr = List.find_opt (fun r -> addr >= r.base && addr - r.base < r.size) c.regions

let validate t (p : Platform.t) =
  let name = p.name in
  match find t name with
  | None -> Error (Printf.sprintf "platform %s: no configuration %s in the manifest" p.name name)
  | Some c when c.top_level <> Some p.top_level ->
      Error
        (Printf.sprintf "platform %s: configuration %s has top level %s, not %s" p.name name
           (Option.value c.top_level ~default:"none")
           p.top_level)
  | Some c -> (
      match (p.blocks.vme, c.tile_registers) with
      | Some v, Some n when v.tiles <> n ->
          Error
            (Printf.sprintf "platform %s: %d tiles, configuration %s has %d tile registers" p.name
               v.tiles name n)
      | Some _, None ->
          Error
            (Printf.sprintf "platform %s: a VME block, but configuration %s has no matrix" p.name
               name)
      | _ -> Ok c)
