open Async.Std
open Core.Std
open Printf

let exit = Pervasives.exit

let rdr = Reader.create (Async_unix.Fd.stdin ())

let eval_message code session =
  [("session", session);
   ("op", "eval");
   ("id", "eval-" ^ (Uuid.to_string (Uuid.create ())));
   ("ns", "user");
   ("code", code ^ "\n")]

let stdin_message input session =
  let uuid = Uuid.to_string (Uuid.create ()) in
  [("op", "stdin");
   ("id", uuid);
   ("stdin", input ^ "\n");
   ("session", session)]

let send_input resp (r,w,p) result =
  match List.Assoc.find resp "session" with
    | Some Bencode.String(session) -> (match result with
        | `Ok input -> Nrepl.send w p (stdin_message input session)
        (* TODO: only exit on EOF in a top-level input request *)
        | `Eof -> exit 0)
    | None | Some _ -> eprintf "  No session in need-input."

let rec handler (r,w,p) raw resp =
  let handle k v = match (k, v) with
    | ("out", out) -> printf "%s%!" out
    | ("err", out) -> eprintf "%s%!" out
    | ("ex", out) | ("root-ex", out) -> eprintf "%s\n%!" out
    | ("value", value) -> printf "%s\n%!" value
    | ("session", _) | ("id", _) | ("ns", _) -> ()
    | (k, v) -> printf "  Unknown response: %s %s\n%!" k v in

  let remove_pending pending id =
    Nrepl.debug ("-p " ^ String.concat ~sep:" " (! pending));
    match id with
      | Some Bencode.String(id) -> if List.mem (! pending) id then
          pending := List.filter (! pending) ((<>) id)
      | None | Some _ -> eprintf "  Unknown message id.\n%!" in

  let handle_done resp pending =
    remove_pending pending (List.Assoc.find resp "id");
    if ! pending = ["init"] then exit 0 in

  let rec handle_status resp status =
    match status with
      (* TODO: handle messages with multiple status fields by recuring on tl *)
      | Bencode.String("done") :: tl -> handle_done resp p
      | Bencode.String("eval-error") :: tl -> exit 1
      | Bencode.String("unknown-session") :: tl -> eprintf "Unknown session.\n"; exit 1
      | Bencode.String("need-input") :: tl -> Reader.read_line rdr >>|
          send_input resp (r,w,p); ()
      | x -> printf "  Unknown status: %s\n%!" (Bencode.marshal (Bencode.List(x))) in

  (* currently if it's a status message we ignore every other field *)
  match List.Assoc.find resp "status" with
    | Some Bencode.List(status) -> handle_status resp status
    | Some _ -> eprintf "  Unexpected status type: %s\n%!" raw
    | None -> match resp with
        | (k, Bencode.String(v)) :: tl -> handle k v; handler (r,w,p) raw tl
        | _ :: tl -> printf "  Unknown response: %s\n%!" raw; handler (r,w,p) raw tl
        | [] -> ()

let port_err () =
  eprintf "Couldn't read port from .nrepl-port or LEIN_REPL_PORT.\n
If Leiningen is not running, launch `lein trampoline repl :headless' from
outside a project directory and try again.\n";
  Pervasives.exit 1

let repl_port root =
  match Sys.getenv "LEIN_REPL_PORT" with
    | Some port -> port
    | None -> let filename = String.concat
                ~sep:Filename.dir_sep [root; ".nrepl-port"] in
              match Sys.file_exists filename with
                | `Yes -> In_channel.read_all filename
                | `No | `Unknown -> port_err ()

let initiate port result =
  match result with
    | `Ok input -> Nrepl.new_session "127.0.0.1" port
      (eval_message input) handler
    | `Eof -> exit 0

let main root =
  let port = Int.of_string (repl_port root) in
  printf "> %!";
  Reader.read_line rdr >>| initiate port
