[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(* Closes when the events end or a pull raises, as the FST reader does; [close] covers a reader that
   stops early. *)
let closing close seq =
  let rec go seq () =
    match seq () with
    | Seq.Nil ->
        close ();
        Seq.Nil
    | Seq.Cons (e, rest) -> Seq.Cons (e, go rest)
    | exception ex ->
        close ();
        raise ex
  in
  go seq

(* A channel names itself "<channel>"; a file is named by its path. *)
let named path (e : Ovcd.Vcd.Error.error) : Ovcd.Vcd.Error.error =
  match e with
  | `Syntax (p, m) -> `Syntax ({ p with Ovcd.Vcd.Error.file = path }, m)
  | `Incomplete (p, m) -> `Incomplete ({ p with Ovcd.Vcd.Error.file = path }, m)
  | e -> e

let rename path f = try f () with Ovcd.Vcd.Error.E e -> raise (Ovcd.Vcd.Error.E (named path e))

let rec rename_seq path seq () =
  match rename path seq with
  | Seq.Nil -> Seq.Nil
  | Seq.Cons (e, rest) -> Seq.Cons (e, rename_seq path rest)

(* A VCD file is read through a channel opened here, so that it is parsed strictly, as standard input
   is. *)
let parse ?select path =
  match Ovcd_fst.detect_file path with
  | `Fst -> (
      match Ovcd_fst.File.open_ path with
      | Error e -> raise (Ovcd.Vcd.Error.E e)
      | Ok f -> (
          let close () = Ovcd_fst.File.close f in
          match
            let header = Ovcd_fst.File.header f in
            let _, simulation = Ovcd_fst.File.stream ?select f in
            { Ovcd.Vcd.header; simulation = closing close simulation }
          with
          | r -> (r, close)
          | exception ex ->
              close ();
              raise ex))
  | `Vcd -> (
      let ic = try open_in_bin path with Sys_error m -> raise (Ovcd.Vcd.Error.E (`Io m)) in
      let close () = close_in_noerr ic in
      match rename path (fun () -> Ovcd.Vcd.parse_channel ?select ~strict:true ic) with
      | r -> ({ r with simulation = closing close (rename_seq path r.simulation) }, close)
      | exception ex ->
          close ();
          raise ex)

let parse_file ?select path = fst (parse ?select path)

let with_parse_file ?select path f =
  let r, close = parse ?select path in
  Fun.protect ~finally:close (fun () -> f r)

let with_seek ?select path ~time f =
  match Ovcd_fst.detect_file path with
  | `Vcd -> None
  | `Fst -> (
      match Ovcd_fst.File.open_ path with
      | Error e -> raise (Ovcd.Vcd.Error.E e)
      | Ok file ->
          Fun.protect
            ~finally:(fun () -> Ovcd_fst.File.close file)
            (fun () ->
              let at = Ovcd_types.Timestamp.of_int64 time in
              match Ovcd_fst.File.blocks file with
              | Ok blocks
                when Array.length blocks > 1 && Ovcd_types.Timestamp.compare (snd blocks.(0)) at < 0
                ->
                  let state, simulation = Ovcd_fst.File.stream ?select ~at file in
                  Some (f state simulation)
              | Ok _ | Error _ -> None))

let open_file ?select path =
  let format = Ovcd_fst.detect_file path in
  let close = ref ignore in
  let t =
    Hwfrp.Trace.of_parse ?select ~format (fun select ->
        let r, c = parse ?select path in
        close := c;
        r)
  in
  Hwfrp.Trace.on_close t !close;
  t

let open_file_result ?select path = Ovcd.Vcd.Error.catch (fun () -> open_file ?select path)
let close = Hwfrp.Trace.close

let with_file ?select path f =
  let t = open_file ?select path in
  Fun.protect ~finally:(fun () -> close t) (fun () -> f t)

let open_string ?select s =
  Hwfrp.Trace.of_parse ?select ~format:(Ovcd_fst.detect_string s) (fun select ->
      Ovcd_fst.open_string ?select s)

let open_input ?select path =
  if path = "-" then begin
    set_binary_mode_in stdin true;
    Hwfrp_vcd.of_channel ?select stdin
  end
  else open_file ?select path

let with_input ?select path f =
  let t = open_input ?select path in
  Fun.protect ~finally:(fun () -> close t) (fun () -> f t)

let wall_clock = Unix.gettimeofday
