[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

type window = { first : int; last : int option; pcs : int list }

type header = {
  schema_version : int;
  model : string;
  platform : string;
  trace : string;
  simulator : string option;
  window : window option;
}

let schema_version = 3

let header ~model ~platform ~trace =
  { schema_version; model; platform; trace; simulator = None; window = None }

let window_jsont =
  Jsont.Object.map ~kind:"window" (fun first last pcs -> { first; last; pcs })
  |> Jsont.Object.mem "first" Jsont.int ~enc:(fun w -> w.first)
  |> Codec.opt (fun w -> w.last) "last" Jsont.int
  |> Jsont.Object.mem "pcs" Jsont.(list int) ~enc:(fun w -> w.pcs)
  |> Jsont.Object.finish

let header_jsont =
  Codec.record "coralview" (fun schema_version model platform trace simulator window ->
      { schema_version; model; platform; trace; simulator; window })
  |> Jsont.Object.mem "schema_version" Jsont.int ~enc:(fun h -> h.schema_version)
  |> Jsont.Object.mem "model" Jsont.string ~enc:(fun h -> h.model)
  |> Jsont.Object.mem "platform" Jsont.string ~enc:(fun h -> h.platform)
  |> Jsont.Object.mem "trace" Jsont.string ~enc:(fun h -> h.trace)
  |> Codec.opt (fun h -> h.simulator) "simulator" Jsont.string
  |> Codec.opt (fun h -> h.window) "window" window_jsont
  |> Jsont.Object.finish

let write (type e s) oc h ((module A) : (e, s) Analysis.t) events ~diags summary =
  let put t v =
    output_string oc (Codec.to_line t v);
    output_char oc '\n'
  in
  put header_jsont h;
  Seq.iter (put A.Event.jsont) events;
  List.iter (put Codec.diag) (diags ());
  put A.Summary.jsont (summary ());
  flush oc

type ('e, 's) line = Header of header | Event of 'e | Diag of Hwfrp.Diag.t | Summary of 's

let type_of =
  Jsont.Object.map ~kind:"line" Fun.id
  |> Jsont.Object.mem "type" Jsont.string ~enc:Fun.id
  |> Jsont.Object.skip_unknown |> Jsont.Object.finish

(* An event line is decoded once, as an event. Only a line that is not one is looked at again, for
   its [type]: the header, a diagnostic, the summary. *)
let classify (type e) (module O : Output.OUTPUT with type Event.t = e) text ~special =
  match Output.decode_event (module O) text with
  | Ok e -> `Event e
  | Error event_error -> (
      match Codec.of_line type_of text with
      | Error e -> `Error e
      | Ok ty -> ( match special ty text with Some r -> r | None -> `Error event_error))

let line (type e s) ((module A) : (e, s) Analysis.t) text =
  let special ty text =
    let decode t f =
      Some (match Codec.of_line t text with Ok v -> `Other (f v) | Error e -> `Error e)
    in
    if ty = "coralview" then decode header_jsont (fun h -> Header h)
    else if ty = "diag" then decode Codec.diag (fun d -> Diag d)
    else if ty = A.name ^ ".summary" then decode A.Summary.jsont (fun s -> Summary s)
    else None
  in
  match classify (module A) text ~special with
  | `Event e -> Ok (Event e)
  | `Other l -> Ok l
  | `Error e -> Error e

let read a ic = Seq.of_dispenser (fun () -> Option.map (line a) (In_channel.input_line ic))

type 'e reader = {
  events : ('e, string) result Seq.t;
  header : unit -> header option;
  diags : unit -> Hwfrp.Diag.t list;
  errors : unit -> string list;
  finish : unit -> unit;
}

let reader (type e) (module O : Output.OUTPUT with type Event.t = e) lines =
  let header = ref None and diags = ref [] and errors = ref [] in
  let next_line = Seq.to_dispenser lines in
  let summary = O.name ^ ".summary" in
  let fail e =
    errors := e :: !errors;
    Some (Error e)
  in
  let special ty text =
    let decode t f =
      Some (match Codec.of_line t text with Ok v -> `Other (f v) | Error e -> `Error e)
    in
    if ty = "coralview" then decode header_jsont (fun h -> if !header = None then header := Some h)
    else if ty = "diag" then decode Codec.diag (fun d -> diags := d :: !diags)
    else if ty = summary then Some (`Other ())
    else None
  in
  let rec next () =
    match next_line () with
    | None -> None
    | Some text -> (
        match classify (module O) text ~special with
        | `Event e -> Some (Ok e)
        | `Other () -> next ()
        | `Error e -> fail e)
  in
  let finished = ref false in
  let events = Seq.of_dispenser (fun () -> if !finished then None else next ()) in
  let finish () =
    while (not !finished) && Option.is_some (next ()) do
      ()
    done;
    finished := true
  in
  {
    events;
    header = (fun () -> !header);
    diags = (fun () -> List.rev !diags);
    errors = (fun () -> List.rev !errors);
    finish;
  }

let channel_lines ic = Seq.of_dispenser (fun () -> In_channel.input_line ic)
