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

let rec handle_status = function
  | Bencode.String("done") :: tl -> exit 0; ()
  | Bencode.String("eval-error") :: tl -> exit 0; ()
  | Bencode.String(status) :: tl -> printf "Status: %s\n%!" status;
    handle_status tl
  | x :: tl -> printf "  Unknown status: %s\n%!" (Bencode.marshal x)
  | [] -> ()

let rec handler raw resp =
  let handle k v = match (k, v) with
    | ("out", out) -> printf "%s%!" out
    | ("err", out) -> eprintf "%s%!" out
    | ("ex", out) | ("root-ex", out) -> eprintf "%s\n%!" out
    | ("value", value) -> (* printf "%s\n%!" value *) ()
    | ("session", _) | ("id", _) | ("ns", _) -> ()
    | (k, v) -> printf "  Unknown response: %s %s\n%!" k v in
  match resp with
    | (k, Bencode.String v) :: tl -> handle k v; handler raw tl
    | ("status", Bencode.List s) :: tl -> handle_status s; handler raw tl
    | (_, _) :: tl -> printf "  Unknown response: %s\n%!" raw; handler raw tl
    | [] -> ()

let port_err = "Couldn't read port from ~/.lein/repl-port or LEIN_REPL_PORT."

let repl_port root =
  match Sys.getenv "LEIN_REPL_PORT" with
    | Some port -> port
    | None -> let filename = String.concat
                ~sep:Filename.dir_sep [(Sys.getenv_exn "HOME");
                                       ".lein"; "repl-port"] in
              match Sys.file_exists filename with
                | `Yes -> In_channel.read_all filename
                | `No | `Unknown -> Printf.printf "%s\n%!" port_err; exit 1; ""

let main cwd root args =
  let port = Int.of_string (repl_port root) in
  let message = message_for cwd root args in
  Nrepl.send_and_receive "127.0.0.1" port message handler

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
