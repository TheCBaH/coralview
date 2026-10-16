[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

type 'c t = { scope : 'c Bind.scope; prefix : string; fields : (string * int) list }

let discover scope prefix =
  let p = prefix ^ "_" in
  let n = String.length p in
  let fields =
    List.filter_map
      (fun (name, w) ->
        if String.length name > n && String.sub name 0 n = p then
          Some (String.sub name n (String.length name - n), w)
        else None)
      (Bind.vars scope)
  in
  { scope; prefix; fields }

let fields b = b.fields
let get ?purpose b field d = Bind.signal ?purpose b.scope (b.prefix ^ "_" ^ field) d

let lanes scope pattern =
  let rec split i =
    if i + 2 > String.length pattern then invalid_arg ("Bundle.lanes: no %d in " ^ pattern)
    else if String.sub pattern i 2 = "%d" then
      (String.sub pattern 0 i, String.sub pattern (i + 2) (String.length pattern - i - 2))
    else split (i + 1)
  in
  let pre, post = split 0 in
  let lp = String.length pre and lq = String.length post in
  List.filter_map
    (fun (name, _) ->
      let n = String.length name in
      if n > lp + lq && String.sub name 0 lp = pre && String.sub name (n - lq) lq = post then
        let digits = String.sub name lp (n - lp - lq) in
        if String.for_all (function '0' .. '9' -> true | _ -> false) digits then
          int_of_string_opt digits
        else None
      else None)
    (Bind.vars scope)
  |> List.sort_uniq Int.compare

type 'c valid = { v_valid : (bool, 'c) Frp.Sig.t; v_bits : 'c t }

type 'c decoupled = {
  d_valid : (bool, 'c) Frp.Sig.t;
  d_ready : (bool, 'c) Frp.Sig.t;
  d_bits : 'c t;
}

let valid ?purpose scope p =
  {
    v_valid = Bind.signal ?purpose scope (p ^ "_valid") Bind.bool;
    v_bits = discover scope (p ^ "_bits");
  }

let decoupled ?purpose scope p =
  {
    d_valid = Bind.signal ?purpose scope (p ^ "_valid") Bind.bool;
    d_ready = Bind.signal scope (p ^ "_ready") Bind.bool;
    d_bits = discover scope (p ^ "_bits");
  }
