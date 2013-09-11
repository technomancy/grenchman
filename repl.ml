open Core.Std

let repl_message input session =
  ([("session", session);
    ("op", "eval");
    ("id", "repl-init");
    ("ns", "user");
    ("code", input)],
   Nrepl.print_all)

let rec main port =
  match Readline.read "> " with
    | Some input -> let _ = Client.eval port [repl_message input] in main port
    | None -> exit 0


