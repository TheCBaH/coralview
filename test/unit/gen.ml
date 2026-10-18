(* QCheck generators of the shared types, for the codec round-trips of every analysis. *)
open Coralview
module G = QCheck2.Gen

let nat = G.int_bound 1_000_000
let addr = G.map (fun x -> x land 0xffff_ffff) G.int

let span =
  G.map2
    (fun start len -> { Hwfrp.Span.start; stop = Option.map (( + ) start) len })
    nat (G.option nat)

let transaction =
  G.(
    map
      (fun ( id,
             write,
             address,
             bytes,
             beats,
             (requested, accepted, first_data, completed, status, outstanding) ) ->
        {
          Hwfrp.Transaction.id;
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
      (tup6 (int_bound 15) bool addr (int_bound 256) (int_range 1 16)
         (tup6 nat nat (G.option nat) (G.option nat) (int_bound 3) (int_range 1 8))))

let instance =
  G.map
    (fun (pc, word, dispatched, issued, retired) ->
      { Instance.pc; word; dispatched; issued; retired })
    G.(tup5 addr (G.option addr) (G.option nat) (G.option nat) (G.option nat))

let region = G.(G.option (oneof_list [ "itcm"; "dtcm"; "extmem" ]))

let access =
  G.map
    (fun (address, bytes, write, region) -> { Access.address; bytes; write; region })
    G.(tup4 addr (int_range 1 64) bool region)

let path =
  G.map
    (fun l -> Vcd_types.Reference.of_list l)
    G.(list_size (int_range 1 4) (oneof_list [ "TOP"; "core"; "io_x"; "a_b" ]))

let diag =
  G.map
    (fun (severity, code, cycle, time, paths, message) ->
      {
        Hwfrp.Diag.severity;
        source = "test";
        code;
        cycle;
        time = Option.map (fun t -> Vcd_types.Timestamp.of_int64 (Int64.of_int t)) time;
        paths;
        message;
      })
    G.(
      tup6
        (oneof_list [ Hwfrp.Diag.Error; Warning; Info ])
        (oneof_list [ "bind.unknown-bits"; "x.y" ])
        (G.option nat) (G.option nat)
        (list_size (int_bound 2) path)
        (string_size ~gen:printable (int_bound 20)))

(* [jsont] encodes, decodes back to an equal value, and the line has no newline. *)
let roundtrip ?(eq = ( = )) name t gen =
  QCheck2.Test.make ~name ~count:300 gen (fun v ->
      let line = Codec.to_line t v in
      if String.contains line '\n' then QCheck2.Test.fail_reportf "newline in %s" line;
      match Codec.of_line t line with
      | Ok v' -> eq v v' || QCheck2.Test.fail_reportf "differs after %s" line
      | Error e -> QCheck2.Test.fail_reportf "%s: %s" line e)

(* Widths of whole hex digits: the codec's width. *)
let bits =
  G.map2
    (fun n bytes ->
      let width = 4 * n in
      Hwfrp.Bits.of_bytes_le ~width
        (Bytes.of_string (String.init ((n + 1) / 2) (fun i -> Char.chr bytes.(i mod 16)))))
    (G.int_range 1 40)
    (G.array_size (G.return 16) (G.int_bound 255))
