open Core.Std
open Async.Std

let repl_message input session =
  ([("session", session);
    ("op", "eval");
    ("id", "repl-" ^ (Uuid.to_string (Uuid.create ())));
    ("ns", ! Client.ns);
    ("code", sprintf "(try %s (catch Exception e
                        (clojure.stacktrace/print-cause-trace e)))" input)],
   Nrepl.print_all)

let dummy_message session =
  ([("session", session);
    ("op", "eval");
    ("id", "repl-dummy");
    ("ns", "user");
    ("code", "nil")],
   Nrepl.default_actions)

let repl_done = function
  | Some Bencode.String(id) -> (String.sub id 0 5) = "repl-"
  | Some _ | None -> false

let is_complete_form input =
  try let _ = Sexp.of_string input in true with
  | _ -> false

let rec read_form prompt prev_input =
  match Readline.read prompt with
  | Some read_input ->
     let input = prev_input ^ read_input in
     if is_complete_form input then
       Some input
     else
       read_form "  > " input
  | None -> None

let rec loop (r,w,p) resp =
  let prompt = (!Client.ns ^ "=> ") in
  if repl_done (List.Assoc.find resp "id") then
    match read_form prompt "", List.Assoc.find resp "session" with
      | Some input, Some Bencode.String(session) ->
        Nrepl.send w p (repl_message input session)
      | Some _, _ -> Core.Std.Printf.eprintf "Missing session.\n"; Pervasives.exit 1
      | None, _ -> Pervasives.exit 0

let main port =
  let handler = Client.handler loop in
  let _ = Nrepl.new_session "127.0.0.1" port [dummy_message] handler in
  never_returns (Scheduler.go ())
