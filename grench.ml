open Async.Std
open Core.Std
open Printf

let splice_args args =
  String.concat ~sep:"\" \"" (List.map args String.escaped)

let main_form = sprintf "(binding [leiningen.core.main/*cwd* \"%s\"
                                   leiningen.core.main/*exit-process?* false]
                           (System/setProperty \"leiningen.original.pwd\" \"%s\")

                           (defmethod leiningen.core.eval/eval-in :trampoline
                           [& _] (throw (Exception. \"trampoline disabled\")))

                           (try (leiningen.core.main/-main \"%s\")
                             (catch clojure.lang.ExceptionInfo e
                               (let [c (:exit-code (ex-data e))]
                                 (when-not (and (number? c) (zero? c))
                                   (throw e))))))"

let message_for root cwd args =
  match Uuid.sexp_of_t (Uuid.create ()) with
      Sexp.Atom uuid -> [("op", Bencode.String("eval"));
                         ("id", Bencode.String(uuid));
                         ("ns", Bencode.String("user"));
                         ("code", Bencode.String(main_form root cwd
                                                   (splice_args args)))]
    | Sexp.List _ -> [] (* no. *)

let rec print_status = function
  | Bencode.String(status) :: tl -> printf "Status: %s\n%!" status;
    print_status tl
  | x :: tl -> printf "  Unknown status: %s\n%!" (Bencode.marshal x)
  | [] -> ()

let handler raw resp =
  (* TODO: got to be a better way to do this over alists *)
  match List.Assoc.find resp "out" with
    | Some Bencode.String(out) -> printf "%s%!" out
    | Some _ | None -> match List.Assoc.find resp "err" with
        | Some Bencode.String(out) -> eprintf "%s%!" out
        | Some _ | None -> match List.Assoc.find resp "value" with
            | Some Bencode.String(value) -> ()
            | Some _ | None -> match List.Assoc.find resp "status" with
                (* TODO: Async exit isn't unit; huh? *)
                | Some Bencode.List([Bencode.String("done")]) -> exit 0; ()
                | Some Bencode.List([Bencode.String("eval-error")]) -> exit 1; ()
                | Some Bencode.List(status) -> print_status status
                | Some _ | None -> printf "unknown response: %s\n%!" raw

let main cwd root args =
  match Sys.getenv "LEIN_REPL_PORT" with
    | Some port -> Nrepl.send_and_receive "127.0.0.1" (Int.of_string port)
      (message_for cwd root args) handler
    | None -> Printf.printf "%s\n%!" "Must set LEIN_REPL_PORT."; exit 1; ()

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
  let cwd = Sys.getcwd () in
  let root = find_root cwd cwd in
  match Sys.argv |> Array.to_list |> List.tl with
    | None | Some ["--grench-help"] -> printf "%s\n%!" usage
    | Some args -> main root cwd args;
  never_returns (Scheduler.go ())
