open Ctypes
open Foreign

let libreadline = Dl.(dlopen ~filename:"libreadline.so" ~flags:[RTLD_NOW])

let readline = foreign "readline" (string @-> returning (ptr_opt char))
  ~from:libreadline

let add_history = foreign "add_history" (string @-> returning void)
  ~from:libreadline

let read prompt =
  let rec strlen p n =
    match !@(p +@ n) with
      | '\000' -> n
      | _ -> strlen p (n + 1) in

  (* Ctypes needs help for some reason to convert char ptr to string *)
  let string_of_char_ptr charp =
    let length = strlen charp 0 in
    let s = String.create length in
    for i = 0 to length - 1 do
      s.[i] <- !@ (charp +@ i)
    done;
    s in

  match readline prompt with
    | Some s -> let input = string_of_char_ptr s in
                add_history input; Some input
    | None -> None

let _ = (foreign_value ~from:libreadline "rl_readline_name" string) <-@ "grench"
