[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(* What the commands share: how a process exits, the options record, opening a trace, and the text
   context of the views. *)

open Coralview

(* Every exit says how the producer ended. *)
let exit code = Stdlib.exit (Driver.finish code)

let fail ?(code = 1) msg =
  flush stdout;
  prerr_endline msg;
  exit code

(* A probe that does not resolve means the platform description is wrong for this trace. *)
let guard (p : Platform.t) f =
  match f () with
  | x -> x
  | exception Hwfrp.Bind.Unbound (r, s) ->
      fail ~code:3
        (Format.asprintf "platform %s does not match the trace (model %s):@\n%a" p.name r.model
           Hwfrp.Bind.pp_entry (r, s))
  | exception Core.No_block (platform, block) ->
      fail ~code:2 (Printf.sprintf "platform %s describes no %s block" platform block)

type elf = { file : string; symbols : Symbols.t }

(* What the options of a command say. The terms of a command return changes to the defaults; they are
   applied once every term is evaluated, and the result is passed down. *)
type options = {
  select : bool;  (** [--no-select] clears it. *)
  plan : (string * Hwfrp.Capture.plan Lazy.t) option;  (** [--plan FILE], read at the first run. *)
  origins : string list option;  (** The models a [run] builds, which the plan must have. *)
  elf : elf option;
      (** [--elf FILE]: the functions of the program, to name PCs and to find a function. *)
  between : (Window_marker.spec * int) option;
      (** The window [--between-pc], [--around-symbol] or [--entry] names. *)
  manifest : string option;  (** [--manifest FILE], for the platform's instruction set. *)
  annotate : string option;  (** [--annotate FILE]: labels for addresses, joined into the rows. *)
  profile_by : Text.profile_by;
  simulator : string option ref;
      (** What the trace's own header says of the simulator; set as a trace is opened, and shared by the
          copies of the options. *)
}

type setting = options -> options

let defaults () =
  {
    select = true;
    plan = None;
    origins = None;
    elf = None;
    between = None;
    manifest = None;
    annotate = None;
    profile_by = Text.Pc;
    simulator = ref None;
  }

(* [--plan FILE]: before the first sample, the signals a run tracks must be the plan's, for the origins it
   builds: the model of the command, or the models of [run]. *)
let gate env =
  match env.plan with
  | None -> None
  | Some (file, plan) ->
      Some
        (fun tr ~model ->
          let plan = Lazy.force plan in
          let origins = Option.value env.origins ~default:[ model ] in
          let planned = Hwfrp.Capture.origins plan in
          (match List.filter (fun o -> not (List.mem o planned)) origins with
          | [] -> ()
          | absent ->
              fail ~code:3
                (Printf.sprintf "the plan %s was made without --model %s (it has %s)" file
                   (String.concat ", --model " absent)
                   (String.concat ", " planned)));
          match Hwfrp.Capture.check plan ~origins tr with
          | Ok () -> ()
          | Error l ->
              fail ~code:3
                (String.concat "\n"
                   (Printf.sprintf "the trace does not match the plan %s:" file
                   :: List.map (fun e -> "  " ^ e) l)))

let load_plan file =
  lazy
    (match Hwfrp.Capture.of_file (In_channel.with_open_bin file In_channel.input_all) with
    | Ok plan -> plan
    | Error e -> fail ~code:2 (Printf.sprintf "%s: %s" file e)
    | exception Sys_error e -> fail ~code:2 e)

let pull env (type k e s)
    (module A : Analysis.S with type Config.t = k and type Event.t = e and type Summary.t = s)
    (cfg : k) p tr =
  Analysis.pull ?gate:(gate env) (module A) cfg p tr

let decoder features =
  match Coral_isa.Rivet_decode.create ?features () with
  | Ok d -> d
  | Error e ->
      prerr_endline ("invalid --features: " ^ e);
      exit 2

let jsonl_window (w : Text.window) =
  if Text.windowed w then
    Some
      {
        Jsonl.first = w.first;
        last = (if w.last = max_int then None else Some w.last);
        pcs = w.pcs;
      }
  else None

(* The simulator is only what the trace's own header says; nothing is assumed. *)
let note_simulator env tr =
  env.simulator :=
    Option.map String.trim (Hwfrp.Trace.header tr).version
    |> Option.map (fun v -> if v = "" then None else Some v)
    |> Option.join

(* A trace read to its end closes itself; a reader that may stop early scopes it with [with_trace]. *)
let open_trace env path =
  let tr = Hwfrp_native.open_input ~select:env.select path in
  note_simulator env tr;
  tr

let with_trace env path f =
  Hwfrp_native.with_input ~select:env.select path (fun tr ->
      note_simulator env tr;
      f tr)

let banner_line ~platform ~simulator =
  Printf.sprintf "platform %s%s\n" platform
    (match simulator with Some v -> ", simulator " ^ v | None -> "")

let banner env (p : Platform.t) =
  print_string (banner_line ~platform:p.name ~simulator:!(env.simulator))

let print_banner env ppf (p : Platform.t) =
  Format.pp_print_string ppf (banner_line ~platform:p.name ~simulator:!(env.simulator))

let jsonl_header env ~model ~platform ~trace =
  { (Jsonl.header ~model ~platform ~trace) with simulator = !(env.simulator) }

(* [--between-pc A,B --nth N] and the other markers: the window is found in the retirements of the run
   that prints it. What is wrong with the markers is known before the run. *)
let marker env =
  Option.map
    (fun (spec, nth) ->
      match Window_marker.make spec ~nth (Option.map (fun e -> e.symbols) env.elf) with
      | Ok m -> m
      | Error (code, msg) -> fail ~code msg)
    env.between

let resolve_window marker (window : Text.window) commits =
  match marker with
  | None -> window
  | Some m -> (
      match Window_marker.resolve m window (Lazy.force commits) with
      | Ok w -> w
      | Error (code, msg) -> fail ~code msg)

(* [k] prints to the standard output for "-", else to the file [path]. *)
let with_ppf path k =
  if path = "-" then begin
    let ppf = Format.formatter_of_out_channel stdout in
    Fun.protect (fun () -> k ppf) ~finally:(fun () -> Format.pp_print_flush ppf ())
  end
  else begin
    let oc = open_out path in
    Fun.protect
      (fun () ->
        let ppf = Format.formatter_of_out_channel oc in
        Fun.protect (fun () -> k ppf) ~finally:(fun () -> Format.pp_print_flush ppf ()))
      ~finally:(fun () -> close_out oc)
  end

let annotation_labels env ~functions =
  match env.annotate with
  | None -> fun _ -> []
  | Some file -> (
      match Annotate.load ~functions file with
      | Ok a -> Annotate.labels a
      | Error e -> fail ~code:2 ("--annotate: " ^ e))

let elf_functions env name =
  match env.elf with
  | None when Annotate.is_hex8 name -> []
  | None -> fail ~code:2 ("--annotate: " ^ name ^ " needs --elf")
  | Some { symbols = t; _ } ->
      List.map (fun (f : Symbols.func) -> (f.address, f.size)) (Symbols.find t name)

let ctx env (p : Platform.t) ?(features = None) ?(region = Region.none) ?(window = Text.everything)
    ?(limit = max_int) ?(profile = 0) ?(legend = false) ?(note = fun ~pc:_ ~cycle:_ -> None) () =
  if env.profile_by = Text.Function && env.elf = None then
    fail ~code:2 "--profile-by function needs --elf";
  (* Without --features, the manifest's configuration of the platform says which instructions exist. *)
  let features, configuration =
    match (features, env.manifest) with
    | Some _, _ | None, None -> (features, None)
    | None, Some file -> (
        let m = match Manifest.load file with Ok m -> m | Error e -> fail ~code:2 e in
        match Manifest.find m p.name with
        | None -> (None, None)
        | Some c ->
            ( Some
                (Coral_isa.Rivet_decode.spec_of_extensions ~extensions:c.extensions
                   ~matrix:(c.tile_registers <> None)),
              Some c ))
  in
  let disasm =
    let d = decoder features in
    fun word ->
      let s = Coral_isa.Rivet_decode.disasm d word in
      match configuration with
      | Some c when String.starts_with ~prefix:".word" s -> (
          match Coral_isa.Rivet_decode.needs d word with
          | [] -> s
          | fs ->
              fail ~code:3
                (Printf.sprintf
                   "word %08x needs %s, which configuration %s of the manifest does not list \
                    (extensions: %s); name them with --features to override"
                   word (String.concat " or " fs) c.name (String.concat ", " c.extensions)))
      | _ -> s
  in
  let note =
    let labels = annotation_labels env ~functions:(elf_functions env) in
    fun ~pc ~cycle ->
      match (note ~pc ~cycle, labels pc) with
      | n, [] -> n
      | None, ls -> Some (String.concat "; " ls)
      | Some n, ls -> Some (String.concat "; " (n :: ls))
  in
  {
    Text.root = Vcd_types.Reference.to_string (Platform.root p);
    disasm;
    instruction_class =
      (let d = decoder features in
       fun word ->
         match Coral_isa.Rivet_decode.instruction d word with
         | Ok i -> Coral_isa.Iclass.(name (of_instruction i))
         | Error _ -> "unknown");
    symbol =
      (match env.elf with
      | None -> fun _ -> None
      | Some { symbols = t; _ } ->
          fun pc ->
            Option.map (fun ((f : Symbols.func), off) -> (f.name, off)) (Symbols.lookup t pc));
    profile_by = env.profile_by;
    region;
    window;
    limit;
    profile;
    legend;
    note;
  }

let opts_ctx env p ?legend ?note (o : Models.opts) =
  ctx env p ~features:o.features ~region:o.region ~window:o.window ~limit:o.limit ~profile:o.profile
    ?legend ?note ()

(* The vsetvli configuration of [disasm --vconfig] for each PC of the --elf, if there is one. *)
let static_vconfig env =
  match env.elf with
  | None -> fun _ -> None
  | Some { file; _ } -> (
      let data =
        try In_channel.with_open_bin file In_channel.input_all with Sys_error e -> fail ~code:2 e
      in
      match Disasm.listing (decoder None) Disasm.everything data with
      | Error _ -> fun _ -> None
      | Ok items ->
          let t = Hashtbl.create 256 in
          List.iter
            (function
              | Disasm.Line { address; vconfig = Some v; _ } -> Hashtbl.replace t address v
              | _ -> ())
            (Disasm.with_vconfig items);
          Hashtbl.find_opt t)

let regions env p =
  match env.manifest with
  | None -> Region.none
  | Some f -> (
      let m = match Manifest.load f with Ok m -> m | Error e -> fail ~code:2 e in
      match Manifest.validate m p with Error e -> fail ~code:3 e | Ok c -> Region.of_manifest c)

(* Every print goes to the standard output, which then is the file. *)
let redirect = function
  | None -> ()
  | Some f ->
      let fd =
        try Unix.openfile f [ O_WRONLY; O_CREAT; O_TRUNC ] 0o644
        with Unix.Unix_error (e, _, _) -> fail ~code:2 (f ^ ": " ^ Unix.error_message e)
      in
      Unix.dup2 fd Unix.stdout;
      Unix.close fd
