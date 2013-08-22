open Async.Std
open Core.Std
open Printf

let args_vector args =
  String.concat ~sep:"\" \"" (List.map args String.escaped)

let main_form = sprintf "(binding [leiningen.core.main/*cwd* \"%s\"
                                   leiningen.core.main/*exit-process?* false]
                           (try (leiningen.core.main/-main \"%s\")
                             (catch clojure.lang.ExceptionInfo e
                               (when-not (and (number? (:exit-code e))
                                              (zero? (:exit-code e)))
                                 (throw e)))))"

let message_for cwd args =
  match Uuid.sexp_of_t (Uuid.create ()) with
      Sexp.Atom uuid -> [("op", Bencode.String("eval"));
                         ("id", Bencode.String(uuid));
                         ("ns", Bencode.String("user"));
                         ("code", Bencode.String(main_form cwd
                                                   (args_vector args)))]
    | Sexp.List _ -> [] (* no. *)

let println = printf "%s\n%!"

let handler resp =
  match List.Assoc.find resp "out" with
    | None -> println "no output"
    | Some Bencode.String(out) -> println out
    | Some _ -> ()

let main cwd args =
  Nrepl.send_and_receive "127.0.0.1" 50454
    (message_for cwd args) handler

let rec find_root cwd original =
  match Sys.file_exists (String.concat ~sep:Filename.dir_sep
                           [cwd; "project.clj"]) with
    | `Yes -> cwd
    | `No | `Unknown -> if (Filename.dirname cwd) = cwd then
        original
      else
        find_root (Filename.dirname cwd) original

(* TODO: this uses single-dash args; uuuugh *)
let command =
  Command.basic
    ~summary:"Send commands to a running Leiningen instance"
    Command.Spec.(
      empty
      +> anon (sequence ("args" %: string)))
    (fun args () -> main (find_root (Sys.getcwd ()) (Sys.getcwd ())) args)

let () =
  Command.run ~version:"0.0.1" command;
  never_returns (Scheduler.go ())
