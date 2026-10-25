[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(* select-trace MANIFEST TRACE: TRACE (VCD or FST) as a VCD with only the declarations the manifest of
   [coralview plan] selects, as the Verilator patch would write it: a variable is selected when its scopes'
   names and its own, joined by single spaces, are a [select] line; the scopes are kept and the changes of
   unselected signals are dropped. A name no declaration matches is an error, as for the producer. *)

open Vcd_types

let die fmt =
  Printf.ksprintf
    (fun s ->
      prerr_endline ("select-trace: " ^ s);
      exit 1)
    fmt

let names path =
  let lines = String.split_on_char '\n' (In_channel.with_open_bin path In_channel.input_all) in
  let lines = match List.rev lines with "" :: rest -> List.rev rest | _ -> lines in
  match lines with
  | "hwfrp-verilator-select 1" :: rest ->
      let names =
        List.filter_map
          (fun l ->
            if String.starts_with ~prefix:"producer " l then None
            else if String.starts_with ~prefix:"select " l then
              Some (String.sub l 7 (String.length l - 7))
            else die "%s: unknown line %S" path l)
          rest
      in
      if names = [] then die "%s: empty selection" path;
      names
  | _ -> die "%s: not a version 1 manifest" path

let () =
  match Sys.argv with
  | [| _; manifest; trace |] ->
      let wanted = Hashtbl.create 64 and matched = Hashtbl.create 64 and kept = Hashtbl.create 64 in
      List.iter (fun n -> Hashtbl.replace wanted n ()) (names manifest);
      let { Vcd.header; simulation } = Vcd_fst.open_file trace in
      let b = Buffer.create 4096 in
      Option.iter (Printf.bprintf b "$timescale %s $end\n") header.timescale;
      let rec scope prefix (s : Vcd_ast.scope_node) =
        let prefix = prefix @ [ s.s_name ] in
        Printf.bprintf b "$scope %s %s $end\n" (Vcd.string_of_scope_type s.s_type) s.s_name;
        List.iter
          (fun (v : Vcd_ast.var_decl) ->
            let native = String.concat " " (prefix @ [ v.ref ]) in
            if Hashtbl.mem wanted native then begin
              Hashtbl.replace matched native ();
              Hashtbl.replace kept (ID.to_string v.id) ();
              Printf.bprintf b "$var %s %d %s %s%s $end\n" (Vcd.string_of_var_type v.v_type) v.size
                (ID.to_string v.id) v.ref
                (match v.index with Some i -> " " ^ i | None -> "")
            end)
          s.vars;
        List.iter (scope prefix) s.children;
        Buffer.add_string b "$upscope $end\n"
      in
      List.iter (scope []) header.scopes;
      Hashtbl.iter (fun n () -> if not (Hashtbl.mem matched n) then die "no declaration named %S" n) wanted;
      Buffer.add_string b "$enddefinitions $end\n";
      print_string (Buffer.contents b);
      Seq.iter
        (function
          | Vcd_ast.Timestamp t -> Printf.printf "#%Ld\n" (Timestamp.to_int64 t)
          | Change (id, v) when Hashtbl.mem kept (ID.to_string id) -> (
              let id = ID.to_string id in
              match v with
              | Value.Scalar l -> Printf.printf "%c%s\n" (Value.char_of_logic l) id
              | Real f -> Printf.printf "r%.17g %s\n" f id
              | v -> Printf.printf "%s %s\n" (Value.to_string v) id)
          | Change _ | DumpStart _ | DumpEnd | SimComment _ -> ())
        simulation
  | _ ->
      prerr_endline "usage: select-trace MANIFEST TRACE";
      exit 2
