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

let rec loop (r,w,p) resp =
  let prompt = (!Client.ns ^ "=> ") in
  if repl_done (List.Assoc.find resp "id") then
    match Readline.read prompt, List.Assoc.find resp "session" with
      | Some input, Some Bencode.String(session) ->
        Nrepl.send w p (repl_message input session)
      | Some _, _ -> Printf.eprintf "Missing session.\n"; Pervasives.exit 1
      | None, _ -> Pervasives.exit 0

let main port =
  let handler = Client.handler loop in
  let _ = Nrepl.new_session "127.0.0.1" port [dummy_message] handler in
  never_returns (Scheduler.go ())
