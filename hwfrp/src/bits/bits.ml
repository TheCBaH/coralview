[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(* Big holds (width+7)/8 little-endian bytes with every bit at or above width clear. *)
type t = Small of { width : int; v : int } | Big of { width : int; b : Bytes.t }

let small_max = 62
let mask w = (1 lsl w) - 1
let nbytes w = (w + 7) / 8
let width = function Small s -> s.width | Big b -> b.width
let check_width w = if w < 0 then invalid_arg "Bits: negative width"

let trim width b =
  let r = width land 7 in
  if r <> 0 then begin
    let i = nbytes width - 1 in
    Bytes.set_uint8 b i (Bytes.get_uint8 b i land mask r)
  end;
  b

let byte_bit b k = (Bytes.get_uint8 b (k lsr 3) lsr (k land 7)) land 1 = 1

(* The little-endian bytes [i, i + n) of [b], [n <= 7]. *)
let le_bytes b i n =
  let r = ref 0 in
  for j = n - 1 downto 0 do
    r := (!r lsl 8) lor Bytes.get_uint8 b (i + j)
  done;
  !r

(* The low [w <= 62] bits of [b] starting at bit [lo]. *)
let bytes_field b ~lo ~w =
  if w = 0 then 0
  else begin
    let i = lo lsr 3 and s = lo land 7 in
    let n = (s + w + 7) lsr 3 in
    if n <= 7 then (le_bytes b i n lsr s) land mask w
    else
      let low = le_bytes b i 7 and high = le_bytes b (i + 7) (n - 7) in
      (low lsr s) lor (high lsl (56 - s)) land mask w
  end

(* Or the 8 bits of [byte] into [r] at bit [pos]; bits past the end of [r] must be clear. *)
let or_byte r pos byte =
  let i = pos lsr 3 and s = pos land 7 in
  Bytes.set_uint8 r i (Bytes.get_uint8 r i lor ((byte lsl s) land 0xff));
  if s > 0 && i + 1 < Bytes.length r then
    Bytes.set_uint8 r (i + 1) (Bytes.get_uint8 r (i + 1) lor (byte lsr (8 - s)))

let of_le width b =
  if width <= small_max then Small { width; v = bytes_field b ~lo:0 ~w:width } else Big { width; b }

let zero width =
  check_width width;
  if width <= small_max then Small { width; v = 0 }
  else Big { width; b = Bytes.make (nbytes width) '\000' }

let of_int ~width v =
  check_width width;
  if width <= small_max then Small { width; v = v land mask width }
  else if v < 0 then invalid_arg "Bits.of_int: negative value wider than 62 bits"
  else begin
    let b = Bytes.make (nbytes width) '\000' in
    for i = 0 to min 7 (nbytes width - 1) do
      Bytes.set_uint8 b i ((v lsr (8 * i)) land 0xff)
    done;
    Big { width; b }
  end

let of_int64 ~width v =
  check_width width;
  if width <= small_max then Small { width; v = Int64.to_int v land mask width }
  else begin
    let b = Bytes.make (nbytes width) '\000' in
    for i = 0 to min 7 (nbytes width - 1) do
      Bytes.set_uint8 b i (Int64.to_int (Int64.logand (Int64.shift_right_logical v (8 * i)) 0xffL))
    done;
    Big { width; b = trim width b }
  end

let of_bytes_le ~width src =
  check_width width;
  let b = Bytes.make (nbytes width) '\000' in
  Bytes.blit src 0 b 0 (min (Bytes.length src) (Bytes.length b));
  of_le width (trim width b)

let of_bytes_be ~width src =
  check_width width;
  let n = Bytes.length src in
  let fits j =
    let byte = Bytes.get_uint8 src (n - 1 - j) and lo = 8 * j in
    if lo >= width then byte = 0 else lo + 8 <= width || byte lsr (width - lo) = 0
  in
  let rec all j = j >= n || (fits j && all (j + 1)) in
  if not (all 0) then None
  else begin
    let b = Bytes.make (nbytes width) '\000' in
    for j = 0 to min n (nbytes width) - 1 do
      Bytes.set_uint8 b j (Bytes.get_uint8 src (n - 1 - j))
    done;
    Some (of_le width b)
  end

let high_clear b ~from =
  let n = Bytes.length b and i = from lsr 3 in
  i >= n
  || Bytes.get_uint8 b i lsr (from land 7) = 0
     &&
     let rec go j =
       if j + 8 <= n then Bytes.get_int64_ne b j = 0L && go (j + 8)
       else j >= n || (Bytes.get_uint8 b j = 0 && go (j + 1))
     in
     go (i + 1)

let to_int = function
  | Small s -> Some s.v
  | Big { b; _ } ->
      if high_clear b ~from:small_max then Some (bytes_field b ~lo:0 ~w:small_max) else None

let to_int_exn t =
  match to_int t with Some v -> v | None -> invalid_arg "Bits.to_int_exn: too wide"

let to_int64 = function
  | Small s -> Some (Int64.of_int s.v)
  | Big { b; _ } ->
      if high_clear b ~from:64 then begin
        let r = ref 0L in
        for i = min 7 (Bytes.length b - 1) downto 0 do
          r := Int64.logor (Int64.shift_left !r 8) (Int64.of_int (Bytes.get_uint8 b i))
        done;
        Some !r
      end
      else None

let to_bytes_le = function
  | Small { width; v } ->
      let b = Bytes.make (nbytes width) '\000' in
      for i = 0 to Bytes.length b - 1 do
        Bytes.set_uint8 b i ((v lsr (8 * i)) land 0xff)
      done;
      b
  | Big { b; _ } -> Bytes.copy b

let is_zero = function Small s -> s.v = 0 | Big { b; _ } -> high_clear b ~from:0

let bit t k =
  if k < 0 || k >= width t then invalid_arg "Bits.bit";
  match t with Small s -> (s.v lsr k) land 1 = 1 | Big { b; _ } -> byte_bit b k

let check_field t ~lo ~width:w =
  if lo < 0 || w < 0 || lo + w > width t then invalid_arg "Bits.field: out of range"

let field_int t ~lo ~width:w =
  check_field t ~lo ~width:w;
  if w > small_max then invalid_arg "Bits.field_int: wider than 62 bits";
  match t with Small s -> (s.v lsr lo) land mask w | Big { b; _ } -> bytes_field b ~lo ~w

let field t ~lo ~width:w =
  check_field t ~lo ~width:w;
  match t with
  | Small s -> Small { width = w; v = (s.v lsr lo) land mask w }
  | Big { b; _ } ->
      if w <= small_max then Small { width = w; v = bytes_field b ~lo ~w }
      else begin
        let r = Bytes.create (nbytes w) and i = lo lsr 3 and s = lo land 7 in
        let last = Bytes.length b - 1 in
        for j = 0 to Bytes.length r - 1 do
          let x = Bytes.get_uint8 b (i + j) lsr s in
          let y =
            if s > 0 && i + j + 1 <= last then Bytes.get_uint8 b (i + j + 1) lsl (8 - s) else 0
          in
          Bytes.set_uint8 r j (x lor y land 0xff)
        done;
        Big { width = w; b = trim w r }
      end

let concat ts =
  let total = List.fold_left (fun n t -> n + width t) 0 ts in
  let r = Bytes.make (nbytes total) '\000' in
  let (_ : int) =
    List.fold_left
      (fun lo t ->
        let w = width t in
        (match t with
        | Small { v; _ } ->
            for j = 0 to nbytes w - 1 do
              or_byte r (lo + (8 * j)) ((v lsr (8 * j)) land 0xff)
            done
        | Big { b; _ } ->
            for j = 0 to Bytes.length b - 1 do
              or_byte r (lo + (8 * j)) (Bytes.get_uint8 b j)
            done);
        lo + w)
      0 (List.rev ts)
  in
  of_le total r

let compare_bytes x y =
  let rec go i =
    if i < 0 then 0
    else
      match Int.compare (Bytes.get_uint8 x i) (Bytes.get_uint8 y i) with 0 -> go (i - 1) | c -> c
  in
  go (Bytes.length x - 1)

let compare a b =
  match Int.compare (width a) (width b) with
  | 0 -> (
      match (a, b) with
      | Small x, Small y -> Int.compare x.v y.v
      | Big x, Big y -> compare_bytes x.b y.b
      | _ -> compare_bytes (to_bytes_le a) (to_bytes_le b))
  | c -> c

let equal a b =
  match (a, b) with
  | Small x, Small y -> x.width = y.width && x.v = y.v
  | Big x, Big y -> x.width = y.width && Bytes.equal x.b y.b
  | _ -> false

let pop_byte =
  let t = Bytes.make 256 '\000' in
  for i = 1 to 255 do
    Bytes.set_uint8 t i ((i land 1) + Bytes.get_uint8 t (i lsr 1))
  done;
  t

let popcount = function
  | Small { v; width } ->
      let n = ref 0 in
      for j = 0 to nbytes width - 1 do
        n := !n + Bytes.get_uint8 pop_byte ((v lsr (8 * j)) land 0xff)
      done;
      !n
  | Big { b; _ } ->
      let n = ref 0 in
      for j = 0 to Bytes.length b - 1 do
        n := !n + Bytes.get_uint8 pop_byte (Bytes.get_uint8 b j)
      done;
      !n

let to_hex t =
  let w = width t in
  let digits = (w + 3) / 4 in
  String.init digits (fun i ->
      let lo = 4 * (digits - 1 - i) in
      let n = field_int t ~lo ~width:(min 4 (w - lo)) in
      "0123456789abcdef".[n])

let pp ppf t = Format.fprintf ppf "%d'h%s" (width t) (to_hex t)
