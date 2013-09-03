open Async.Std
open Core.Std
open Printf

let lein_port_err =
  "Couldn't read port from ~/.lein/repl-port or LEIN_REPL_PORT.\n
If Leiningen is not running, launch `lein repl :headless' from outside a
project directory and try again."

let lein_repl_port () =
  let filename = String.concat
                   ~sep:Filename.dir_sep [(Sys.getenv_exn "HOME");
                                          ".lein"; "repl-port"] in
  match Client.repl_port "LEIN_REPL_PORT" filename with
  | Some port -> port
  | None -> Printf.eprintf "%s\n%!" lein_port_err;
            Pervasives.exit 1

let lein_ns = "leiningen.core.main"

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

let lein_main args =
  let cwd = Sys.getcwd () in
  let root = Client.find_root cwd cwd in
  let port = lein_repl_port () in
  Client.main lein_ns (main_form root cwd (Client.splice_args args)) port

let usage = "usage: grench TASK [ARGS]...

A replacement launcher for running Leiningen tasks.
See `grench help' to list tasks."

let () =
  if ! Sys.interactive then () else
    match Sys.argv |> Array.to_list |> List.tl with
      | None | Some ["--grench-help"] -> printf "%s\n%!" usage
      | Some ["--version"] | Some ["-v"] -> printf "Grenchman 0.1.0\n%!"
      | Some ["--leiningen-version"] | Some ["--lein-version"] ->
        lein_main ["version"]
      | Some ["repl"] -> lein_main ["run"; "-m"; "clojure.main/main"; "-r"]
      | Some ("main" :: tl) -> Cljmain.cljmain tl
      | Some args -> lein_main args
