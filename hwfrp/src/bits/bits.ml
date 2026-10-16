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

let set_byte_bit b k =
  let i = k lsr 3 in
  Bytes.set_uint8 b i (Bytes.get_uint8 b i lor (1 lsl (k land 7)))

(* The low [w <= 62] bits of [b] starting at bit [lo]. *)
let bytes_field b ~lo ~w =
  let r = ref 0 in
  for k = w - 1 downto 0 do
    r := (!r lsl 1) lor if byte_bit b (lo + k) then 1 else 0
  done;
  !r

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

let of_bytes_msb_first ~width src =
  check_width width;
  let b = Bytes.make (nbytes width) '\000' in
  for k = 0 to width - 1 do
    let i = width - 1 - k in
    if i lsr 3 < Bytes.length src && (Bytes.get_uint8 src (i lsr 3) lsr (7 - (i land 7))) land 1 = 1
    then set_byte_bit b k
  done;
  of_le width b

let high_clear b ~from =
  let rec go k = k >= Bytes.length b * 8 || ((not (byte_bit b k)) && go (k + 1)) in
  go from

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
        let r = Bytes.make (nbytes w) '\000' in
        for k = 0 to w - 1 do
          if byte_bit b (lo + k) then set_byte_bit r k
        done;
        Big { width = w; b = r }
      end

let concat ts =
  let total = List.fold_left (fun n t -> n + width t) 0 ts in
  let r = Bytes.make (nbytes total) '\000' in
  let (_ : int) =
    List.fold_left
      (fun lo t ->
        for k = 0 to width t - 1 do
          if bit t k then set_byte_bit r (lo + k)
        done;
        lo + width t)
      0 (List.rev ts)
  in
  of_le total r

let compare a b =
  match Int.compare (width a) (width b) with
  | 0 -> (
      match (a, b) with
      | Small x, Small y -> Int.compare x.v y.v
      | _ ->
          let x = to_bytes_le a and y = to_bytes_le b in
          let rec go i =
            if i < 0 then 0
            else
              match Int.compare (Bytes.get_uint8 x i) (Bytes.get_uint8 y i) with
              | 0 -> go (i - 1)
              | c -> c
          in
          go (Bytes.length x - 1))
  | c -> c

let equal a b = compare a b = 0

let popcount t =
  let n = ref 0 in
  for k = 0 to width t - 1 do
    if bit t k then incr n
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
