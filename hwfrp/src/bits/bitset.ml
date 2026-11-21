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

(* The index of the lowest set bit of [x <> 0]. *)
let ctz x =
  let n = ref 0 and x = ref x in
  if !x land 0xffffffff = 0 then begin
    n := 32;
    x := !x lsr 32
  end;
  if !x land 0xffff = 0 then begin
    n := !n + 16;
    x := !x lsr 16
  end;
  if !x land 0xff = 0 then begin
    n := !n + 8;
    x := !x lsr 8
  end;
  if !x land 0xf = 0 then begin
    n := !n + 4;
    x := !x lsr 4
  end;
  if !x land 0x3 = 0 then begin
    n := !n + 2;
    x := !x lsr 2
  end;
  if !x land 0x1 = 0 then incr n;
  !n

let iter f t =
  if t.count > 0 then
    for w = 0 to Array.length t.words - 1 do
      let x = ref t.words.(w) in
      while !x <> 0 do
        let low = !x land - !x in
        f ((w * bits) + ctz low);
        x := !x lxor low
      done
    done

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
