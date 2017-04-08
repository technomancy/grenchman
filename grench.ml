open Core.Std
open Printf

(* Entry point module; handles command-line args and dispatching. *)

let help = "Grenchman runs Clojure code quickly.

Commands:

  eval FORM                             Evals given form.
  main NAMESPACE[/FUNCTION] [ARGS...]   Runs existing defn.
  repl [:connect PORT]                  Connects a repl.
  load FILE                             Loads a given file.
  lein [TASK ARGS...]                   Runs a Leiningen task.

Running with no arguments will read code to eval from stdin.

The first four commands connect to a running nREPL project server in order to
avoid JVM startup time. The simplest way to start a project nREPL server is to
run `lein trampoline repl :headless` from the project directory in another
shell. If it can't infer the port correctly you can set $GRENCH_PORT.

The lein command requires a separate Leiningen-specific nREPL process to be
running; you can launch one with this: cd ~/.lein && lein repl :headless
"

let port_err = "Couldn't read port from .nrepl-port or $GRENCH_PORT.\n"

let repl_port port_file err_string =
  let cwd = Sys.getcwd () in
  let root = Client.find_root cwd cwd in
  let filename = String.concat ~sep:Filename.dir_sep [root; port_file] in
  match Sys.getenv "GRENCH_PORT" with
    | Some port -> int_of_string port
    | None -> match Sys.file_exists filename with
        | `Yes -> int_of_string (In_channel.read_all filename)
        | `No | `Unknown -> eprintf "%s%!" err_string; exit 111

let () =
  if ! Sys.interactive then () else
    match Sys.argv |> Array.to_list |> List.tl with
      | Some ["--help"] | Some ["-h"] | Some ["-?"] | Some ["help"] ->
        printf "%s\n%!" help
      | Some ["--version"] | Some ["-v"] | Some ["version"] ->
        printf "Grenchman 0.3.0\n%!"

      | Some ("eval" :: args) ->
        Client.main (repl_port ".nrepl-port" port_err)
          ("clojure.main/main" :: "-e" :: args)

      | Some ("load" :: args) ->
        Client.main (repl_port ".nrepl-port" port_err)
          ("clojure.main/main" :: args)

      | Some ("main" :: args) ->
        Client.main (repl_port ".nrepl-port" port_err) args

      | Some ["repl"] ->
        Repl.main (repl_port ".nrepl-port" port_err)
      | Some ["repl"; ":connect"; port] ->
        Repl.main (int_of_string port)

      | Some ("lein" :: args) ->
        Lein.main args

      | None | Some [] ->
        Client.stdin_eval (repl_port ".nrepl-port" (port_err ^ "\n" ^ help))

      | Some _ -> eprintf "Unknown command.\n\n%s" help; exit 1
