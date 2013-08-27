open Async.Std
open Core.Std
open Printf

let splice_args args =
  String.concat ~sep:"\" \"" (List.map args String.escaped)

let main_form = sprintf "(binding [*cwd* \"%s\", *exit-process?* false]
                           (System/setProperty \"leiningen.original.pwd\" \"%s\")

                           (defmethod leiningen.core.eval/eval-in :default
                             [project form]
                             (leiningen.core.eval/eval-in
                               (assoc project :eval-in :nrepl) form))
                           (defmethod leiningen.core.eval/eval-in :trampoline
                             [& _] (throw (Exception. \"trampoline disabled\")))

                           (try (-main \"%s\")
                             (catch clojure.lang.ExceptionInfo e
                               (let [c (:exit-code (ex-data e))]
                                 (when-not (and (number? c) (zero? c))
                                   (throw e))))))"

let main_message root cwd args session =
  [("session", session);
   ("op", "eval");
   ("id", Uuid.to_string (Uuid.create ()));
   ("ns", "leiningen.core.main");
   ("code", main_form root cwd (splice_args args))]

let port_err () =
  eprintf "Couldn't read port from ~/.lein/repl-port or LEIN_REPL_PORT.\n
If Leiningen is not running, launch `lein repl :headless' from outside a
project directory and try again.\n";
  Pervasives.exit 1

let repl_port () =
  match Sys.getenv "LEIN_REPL_PORT" with
    | Some port -> port
    | None -> let filename = String.concat
                ~sep:Filename.dir_sep [(Sys.getenv_exn "HOME");
                                       ".lein"; "repl-port"] in
              match Sys.file_exists filename with
                | `Yes -> In_channel.read_all filename
                | `No | `Unknown -> port_err ()

let main cwd root args =
  let port = Int.of_string (repl_port ()) in
  let message = main_message cwd root args in
  Nrepl.new_session "127.0.0.1" port message Repl.handler

let rec find_root cwd original =
  match Sys.file_exists (String.concat ~sep:Filename.dir_sep
                           [cwd; "project.clj"]) with
    | `Yes -> cwd
    | `No | `Unknown -> if (Filename.dirname cwd) = cwd then
        original
      else
        find_root (Filename.dirname cwd) original

let usage = "usage: grench TASK [ARGS]...

A replacement launcher for running Leiningen tasks.
See `grench help' to list tasks."

let () =
  if ! Sys.interactive then () else
    let cwd = Sys.getcwd () in
    let root = find_root cwd cwd in
    match Sys.argv |> Array.to_list |> List.tl with
      | None | Some ["--grench-help"] -> printf "%s\n%!" usage
      | Some ["repl"] -> let _ = Repl.main root in
                         never_returns (Scheduler.go ())
      | Some args -> let _ = main root cwd args in
                     never_returns (Scheduler.go ())
