open Core.Std
open Printf

(* Entry point module; handles command-line args and dispatching. *)

let usage = "Grenchman runs Clojure code quickly.

Commands:

  main NAMESPACE[/FUNCTION] [ARGS...]   Run an existing project function.
  eval FORM                             Eval form inside project.
  repl [:connect PORT]                  Connect a repl.
  lein [TASK ARGS...]                   Run a Leiningen task.\n\n"

let port_err = "Couldn't read port from .nrepl-port or $GRENCH_PORT.\n"

let repl_port port_file =
  let cwd = Sys.getcwd () in
  let root = Client.find_root cwd cwd in
  let filename = String.concat ~sep:Filename.dir_sep [root; port_file] in
  match Sys.getenv "GRENCH_PORT" with
    | Some port -> int_of_string port
    | None -> match Sys.file_exists filename with
        | `Yes -> int_of_string (In_channel.read_all filename)
        | `No | `Unknown -> eprintf "%s%!" port_err; exit 111

let () =
  if ! Sys.interactive then () else
    match Sys.argv |> Array.to_list |> List.tl with
      | None | Some ["--grench-help"] -> printf "%s\n%!" usage
      | Some ["--version"] | Some ["-v"] -> printf "Grenchman 0.1.0\n%!"
      | Some ["--leiningen-version"] | Some ["--lein-version"] ->
        Lein.main ["version"]

      | Some ("main" :: args) -> Client.main (repl_port ".nrepl-port") args
      | Some ("eval" :: args) ->
        Client.main (repl_port ".nrepl-port")
          ("clojure.main/main" :: "-e" :: args)

      | Some ["repl"] -> Repl.main (repl_port ".nrepl-port")
      | Some ["repl"; ":connect"; port] -> Repl.main (int_of_string port)
      | Some ("lein" :: args) -> Lein.main args
      | Some _ -> eprintf "Unknown command.\n\n%s" usage; exit 1

