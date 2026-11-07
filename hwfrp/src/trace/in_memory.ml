[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

let var ?(typ = Vcd_ast.Wire) ~id ~width ref : Vcd_ast.var_decl =
  { v_type = typ; size = width; id = Vcd_types.ID.of_string id; ref; index = None }

let scope ?(typ = Vcd_ast.Module) ?(children = []) name vars : Vcd_ast.scope_node =
  { s_type = typ; s_name = name; children; vars }

let header scopes : Vcd_ast.header =
  { version = None; date = None; timescale = None; timezero = None; comment = None; scopes }

let at t = Vcd_ast.Timestamp (Vcd_types.Timestamp.of_int64 t)
let change ~id v = Vcd_ast.Change (Vcd_types.ID.of_string id, v)

let trace header events =
  Trace.of_parse ~format:`Vcd (fun _select -> { Vcd.header; simulation = events })

module Live = struct
  type t = { header : Vcd_ast.header; queue : Vcd_ast.event Queue.t; mutable finished : bool }

  let create header = { header; queue = Queue.create (); finished = false }

  let trace t =
    Trace.of_pull ~format:`Vcd t.header (fun () ->
        match Queue.take_opt t.queue with
        | Some e -> Trace.Event e
        | None -> if t.finished then Trace.Ended else Trace.Starved)

  let push t e =
    if t.finished then invalid_arg "In_memory.Live.push: the source is finished";
    Queue.push e t.queue

  let finish t = t.finished <- true
  let queued t = Queue.length t.queue
end
