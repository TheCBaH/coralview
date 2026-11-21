[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

type spec = Between of int * int | Around of string | Entry of string

type t = {
  flag : string;
  nth : int;
  start_name : string;
  end_name : string;
  open_ended : bool;
  predicates : unit -> (Commits.commit -> bool) * (Commits.commit -> bool);
}

let ret = 0x00008067

let make spec ~nth symbols =
  let flag =
    match spec with
    | Between _ -> "--between-pc"
    | Around _ -> "--around-symbol"
    | Entry _ -> "--entry"
  in
  let make start_name end_name open_ended predicates =
    Ok { flag; nth; start_name; end_name; open_ended; predicates }
  in
  match spec with
  | Between (a, b) ->
      make (Printf.sprintf "pc %08x" a) (Printf.sprintf "pc %08x" b) false (fun () ->
          ((fun (c : Commits.commit) -> c.pc = a), fun (c : Commits.commit) -> c.pc = b))
  | Around name | Entry name -> (
      match symbols with
      | None -> Error (2, flag ^ " needs --elf")
      | Some t -> (
          match Symbols.find t name with
          | [] -> Error (2, Printf.sprintf "%s: no function %s in the ELF" flag name)
          | _ :: _ :: _ ->
              Error (2, Printf.sprintf "%s: %s names several functions; use --between-pc" flag name)
          | [ f ] when match spec with Entry _ -> true | _ -> false ->
              (* The ret that pops the entry's frame: calls (jal/jalr with rd = ra) nest. *)
              make name "" true (fun () ->
                  let depth = ref 0 in
                  ( (fun (c : Commits.commit) -> c.pc = f.address),
                    fun c ->
                      match c.word with
                      | Some w when w land 0xfff = 0x0ef || w land 0xfff = 0x0e7 ->
                          incr depth;
                          false
                      | Some w when w = ret ->
                          if !depth = 0 then true
                          else begin
                            decr depth;
                            false
                          end
                      | _ -> false ))
          | [ f ] ->
              make name ("a ret of " ^ name) false (fun () ->
                  ( (fun (c : Commits.commit) -> c.pc = f.address),
                    fun c ->
                      c.word = Some ret && c.pc >= f.address && c.pc < f.address + max f.size 1 ))))

let find m commits =
  let is_start, is_end = m.predicates () in
  let seen = ref 0 and first = ref None and last = ref None in
  (try
     List.iter
       (fun (c : Commits.commit) ->
         match !first with
         | None ->
             if is_start c then begin
               incr seen;
               if !seen = m.nth then first := Some c.retired
             end
         | Some f ->
             if is_end c && c.retired >= f then begin
               last := Some c.retired;
               raise Exit
             end)
       commits
   with Exit -> ());
  match (!first, !last) with
  | None, _ ->
      Error (3, Printf.sprintf "%s: %s retires fewer than %d times" m.flag m.start_name m.nth)
  | Some f, Some l -> Ok (f, l)
  | Some f, None when m.open_ended -> Ok (f, max_int)
  | Some f, None ->
      Error (3, Printf.sprintf "%s: %s never retires from cycle %d" m.flag m.end_name f)

let narrow (w : Text.window) (first, last) =
  { w with first = max first w.first; last = min last w.last }

let resolve m w commits = Result.map (narrow w) (find m commits)
