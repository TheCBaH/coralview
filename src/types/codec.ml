[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Hwfrp

let tag name = Jsont.enum ~kind:"type" [ (name, ()) ]

let record name dec =
  Jsont.Object.map ~kind:name (fun () -> dec)
  |> Jsont.Object.mem "type" (tag name) ~enc:(fun _ -> ())

let case name inj c = Jsont.Object.Case.map ~dec:inj name c

let cases kind enc_case cases =
  Jsont.Object.map ~kind Fun.id
  |> Jsont.Object.case_mem "type" Jsont.string ~enc:Fun.id ~enc_case cases
  |> Jsont.Object.finish

let opt enc name t m = Jsont.Object.opt_mem name t ~enc m

let span =
  Jsont.Object.map ~kind:"span" (fun start stop -> { Span.start; stop })
  |> Jsont.Object.mem "start" Jsont.int ~enc:(fun (s : Span.t) -> s.start)
  |> opt (fun (s : Span.t) -> s.stop) "stop" Jsont.int
  |> Jsont.Object.finish

let transaction =
  Jsont.Object.map ~kind:"transaction"
    (fun id write address bytes beats requested accepted first_data completed status outstanding ->
      {
        Transaction.id;
        write;
        address;
        bytes;
        beats;
        requested;
        accepted;
        first_data;
        completed;
        status;
        outstanding;
      })
  |> Jsont.Object.mem "id" Jsont.int ~enc:(fun (t : Transaction.t) -> t.id)
  |> Jsont.Object.mem "write" Jsont.bool ~enc:(fun (t : Transaction.t) -> t.write)
  |> Jsont.Object.mem "address" Jsont.int ~enc:(fun (t : Transaction.t) -> t.address)
  |> Jsont.Object.mem "bytes" Jsont.int ~enc:(fun (t : Transaction.t) -> t.bytes)
  |> Jsont.Object.mem "beats" Jsont.int ~enc:(fun (t : Transaction.t) -> t.beats)
  |> Jsont.Object.mem "requested" Jsont.int ~enc:(fun (t : Transaction.t) -> t.requested)
  |> Jsont.Object.mem "accepted" Jsont.int ~enc:(fun (t : Transaction.t) -> t.accepted)
  |> opt (fun (t : Transaction.t) -> t.first_data) "first_data" Jsont.int
  |> opt (fun (t : Transaction.t) -> t.completed) "completed" Jsont.int
  |> Jsont.Object.mem "status" Jsont.int ~enc:(fun (t : Transaction.t) -> t.status)
  |> Jsont.Object.mem "outstanding" Jsont.int ~enc:(fun (t : Transaction.t) -> t.outstanding)
  |> Jsont.Object.finish

let severity =
  Jsont.enum ~kind:"severity"
    [ ("error", Diag.Error); ("warning", Diag.Warning); ("info", Diag.Info) ]

let timestamp =
  Jsont.map ~kind:"timestamp" Jsont.int64 ~dec:Vcd_types.Timestamp.of_int64
    ~enc:Vcd_types.Timestamp.to_int64

let reference =
  Jsont.map ~kind:"path" Jsont.string ~dec:Vcd_types.Reference.of_string
    ~enc:Vcd_types.Reference.to_string

let diag =
  record "diag" (fun severity source code cycle time paths message ->
      { Diag.severity; source; code; cycle; time; paths; message })
  |> Jsont.Object.mem "severity" severity ~enc:(fun (d : Diag.t) -> d.severity)
  |> Jsont.Object.mem "source" Jsont.string ~enc:(fun (d : Diag.t) -> d.source)
  |> Jsont.Object.mem "code" Jsont.string ~enc:(fun (d : Diag.t) -> d.code)
  |> opt (fun (d : Diag.t) -> d.cycle) "cycle" Jsont.int
  |> opt (fun (d : Diag.t) -> d.time) "time" timestamp
  |> Jsont.Object.mem "paths" (Jsont.list reference) ~enc:(fun (d : Diag.t) -> d.paths)
  |> Jsont.Object.mem "message" Jsont.string ~enc:(fun (d : Diag.t) -> d.message)
  |> Jsont.Object.finish

let to_line t v =
  match Jsont_bytesrw.encode_string ~format:Jsont.Minify t v with
  | Ok s -> s
  | Error e -> invalid_arg ("Codec.to_line: " ^ e)

let of_line t s = Jsont_bytesrw.decode_string t s

let stats =
  Jsont.Object.map ~kind:"stats" (fun n min max sum ->
      if n = 0 then Reduce.Stats.empty
      else { Reduce.Stats.n; min = Option.get min; max = Option.get max; sum })
  |> Jsont.Object.mem "n" Jsont.int ~enc:(fun (s : Reduce.Stats.t) -> s.n)
  |> opt (fun (s : Reduce.Stats.t) -> if s.n = 0 then None else Some s.min) "min" Jsont.int
  |> opt (fun (s : Reduce.Stats.t) -> if s.n = 0 then None else Some s.max) "max" Jsont.int
  |> Jsont.Object.mem "sum" Jsont.int ~enc:(fun (s : Reduce.Stats.t) -> s.sum)
  |> Jsont.Object.finish

let bits =
  Jsont.map ~kind:"bits" Jsont.string ~enc:Bits.to_hex ~dec:(fun s ->
      let n = String.length s in
      let b = Bytes.make ((n + 1) / 2) '\000' in
      String.iteri
        (fun i c ->
          let d = int_of_string ("0x" ^ String.make 1 c) and k = n - 1 - i in
          Bytes.set b (k / 2)
            (Char.chr (Char.code (Bytes.get b (k / 2)) lor (d lsl (4 * (k mod 2))))))
        s;
      Bits.of_bytes_le ~width:(4 * n) b)
