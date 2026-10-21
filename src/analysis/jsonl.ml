[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

type header = { schema_version : int; model : string; platform : string; trace : string }

let schema_version = 1
let header ~model ~platform ~trace = { schema_version; model; platform; trace }

let header_jsont =
  Codec.record "coralview" (fun schema_version model platform trace ->
      { schema_version; model; platform; trace })
  |> Jsont.Object.mem "schema_version" Jsont.int ~enc:(fun h -> h.schema_version)
  |> Jsont.Object.mem "model" Jsont.string ~enc:(fun h -> h.model)
  |> Jsont.Object.mem "platform" Jsont.string ~enc:(fun h -> h.platform)
  |> Jsont.Object.mem "trace" Jsont.string ~enc:(fun h -> h.trace)
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

let line (type e s) ((module A) : (e, s) Analysis.t) text =
  let ( let* ) = Result.bind in
  let* ty = Codec.of_line type_of text in
  if ty = "coralview" then Result.map (fun h -> Header h) (Codec.of_line header_jsont text)
  else if ty = "diag" then Result.map (fun d -> Diag d) (Codec.of_line Codec.diag text)
  else if ty = A.name ^ ".summary" then
    Result.map (fun s -> Summary s) (Codec.of_line A.Summary.jsont text)
  else Result.map (fun e -> Event e) (Codec.of_line A.Event.jsont text)

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
  let rec next () =
    match next_line () with
    | None -> None
    | Some text -> (
        match Codec.of_line type_of text with
        | Error e -> fail e
        | Ok "coralview" -> (
            match Codec.of_line header_jsont text with
            | Error e -> fail e
            | Ok h ->
                if !header = None then header := Some h;
                next ())
        | Ok "diag" -> (
            match Codec.of_line Codec.diag text with
            | Error e -> fail e
            | Ok d ->
                diags := d :: !diags;
                next ())
        | Ok ty when ty = summary -> next ()
        | Ok _ -> (
            match Output.decode_event (module O) text with Ok e -> Some (Ok e) | Error e -> fail e))
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
