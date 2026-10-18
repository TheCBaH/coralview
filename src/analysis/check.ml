[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Hwfrp

type binding = {
  model : string;
  root : string;
  path : string;
  width : string;
  purpose : string option;
  status : string;
  actual : int option;
  detail : string option;
}

let of_entry model root ((r : Bind.requirement), (s : Bind.status)) =
  let rec strip prefix path =
    match (prefix, path) with
    | p :: ps, q :: qs when p = q -> strip ps qs
    | [], rest -> Some rest
    | _ -> None
  in
  let rel =
    match strip (Vcd_types.Reference.to_list root) (Vcd_types.Reference.to_list r.path) with
    | Some (_ :: _ as rest) -> String.concat "/" rest
    | _ -> Vcd_types.Reference.to_string r.path
  in
  let status, actual, detail =
    match s with
    | Bound s -> ("bound", Some s.width, None)
    | Missing -> ("missing", None, None)
    | Width_mismatch { actual; _ } -> ("width", Some actual, None)
    | Not_a_vector t -> ("type", None, Some (Vcd.string_of_var_type t))
  in
  {
    model;
    root = Vcd_types.Reference.to_string root;
    path = rel;
    width = Format.asprintf "%a" Bind.pp_width_rule r.width;
    purpose = (if r.purpose = "" then None else Some r.purpose);
    status;
    actual;
    detail;
  }

let ok b = b.status = "bound"

let jsont =
  Codec.record "check.binding" (fun model root path width purpose status actual detail ->
      { model; root; path; width; purpose; status; actual; detail })
  |> Jsont.Object.mem "model" Jsont.string ~enc:(fun b -> b.model)
  |> Jsont.Object.mem "root" Jsont.string ~enc:(fun b -> b.root)
  |> Jsont.Object.mem "path" Jsont.string ~enc:(fun b -> b.path)
  |> Jsont.Object.mem "width" Jsont.string ~enc:(fun b -> b.width)
  |> Codec.opt (fun b -> b.purpose) "purpose" Jsont.string
  |> Jsont.Object.mem "status" Jsont.string ~enc:(fun b -> b.status)
  |> Codec.opt (fun b -> b.actual) "actual" Jsont.int
  |> Codec.opt (fun b -> b.detail) "detail" Jsont.string
  |> Jsont.Object.finish

type summary = { bound : int; failed : int }

let summary_jsont =
  Codec.record "check.summary" (fun bound failed -> { bound; failed })
  |> Jsont.Object.mem "bound" Jsont.int ~enc:(fun s -> s.bound)
  |> Jsont.Object.mem "failed" Jsont.int ~enc:(fun s -> s.failed)
  |> Jsont.Object.finish
