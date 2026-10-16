[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

let bits = 62

type t = { words : int array; capacity : int; mutable count : int }

let create n = { words = Array.make ((n + bits - 1) / bits) 0; capacity = n; count = 0 }
let capacity t = t.capacity
let mem t i = (t.words.(i / bits) lsr (i mod bits)) land 1 = 1

let add t i =
  if i < 0 || i >= t.capacity then invalid_arg "Bitset.add";
  let w = i / bits in
  let m = 1 lsl (i mod bits) in
  if t.words.(w) land m = 0 then begin
    t.words.(w) <- t.words.(w) lor m;
    t.count <- t.count + 1
  end

let clear t =
  if t.count > 0 then begin
    Array.fill t.words 0 (Array.length t.words) 0;
    t.count <- 0
  end

let is_empty t = t.count = 0

let iter f t =
  if t.count > 0 then
    Array.iteri
      (fun w x ->
        if x <> 0 then
          for b = 0 to bits - 1 do
            if (x lsr b) land 1 = 1 then f ((w * bits) + b)
          done)
      t.words

let elements t =
  let l = ref [] in
  iter (fun i -> l := i :: !l) t;
  List.rev !l

let remove t i =
  let w = i / bits in
  let m = 1 lsl (i mod bits) in
  if t.words.(w) land m <> 0 then begin
    t.words.(w) <- t.words.(w) land lnot m;
    t.count <- t.count - 1
  end
