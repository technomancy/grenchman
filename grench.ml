open Async.Std
open Core.Std
open Printf

let exit = Pervasives.exit

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

let eval_message root cwd args session =
  (* TODO: move id generation to Nrepl.send *)
  match Uuid.sexp_of_t (Uuid.create ()) with
      Sexp.Atom uuid -> [("session", Bencode.String(session));
                         ("op", Bencode.String("eval"));
                         ("id", Bencode.String("eval-" ^ uuid));
                         ("ns", Bencode.String("leiningen.core.main"));
                         ("code", Bencode.String(main_form root cwd
                                                   (splice_args args)))]
    | Sexp.List _ -> [] (* no. *)

let rec handler rw raw resp =
  let handle k v = match (k, v) with
    | ("out", out) -> printf "%s%!" out
    | ("err", out) -> eprintf "%s%!" out
    | ("ex", out) | ("root-ex", out) -> eprintf "%s\n%!" out
    | ("value", value) -> Nrepl.debug ("-: " ^ value)
    | ("session", _) | ("id", _) | ("ns", _) -> ()
    | (k, v) -> printf "  Unknown response: %s %s\n%!" k v in

  let handle_done resp =
    match List.Assoc.find resp "id" with
      (* TODO: terrible heuristic; need to track ids properly *)
      | Some Bencode.String(id) -> if String.sub id 0 5 = "eval-" then
          exit 0 else ()
      | None | Some _ -> () in

  let rec handle_status resp status =
    match status with
      (* TODO: handle messages with multiple status fields by recuring on tl *)
      | Bencode.String("done") :: tl -> handle_done resp
      | Bencode.String("eval-error") :: tl -> exit 1
      | Bencode.String("unknown-session") :: tl -> eprintf "Unknown session.\n"; exit 1
      | x -> printf "  Unknown status: %s\n%!" (Bencode.marshal (Bencode.List(x))) in

  (* currently if it's a status message we ignore every other field *)
  match List.Assoc.find resp "status" with
    | Some Bencode.List(status) -> handle_status resp status
    | Some _ -> eprintf "  Unexpected status type: %s\n%!" raw
    | None -> match resp with
        | (k, Bencode.String(v)) :: tl -> handle k v; handler rw raw tl
        | _ :: tl -> printf "  Unknown response: %s\n%!" raw; handler rw raw tl
        | [] -> ()

let port_err () =
  eprintf "Couldn't read port from ~/.lein/repl-port or LEIN_REPL_PORT.\n
If Leiningen is not running, launch `lein repl :headless' from outside a
project directory and try again.\n";
  exit 1

let repl_port root =
  match Sys.getenv "LEIN_REPL_PORT" with
    | Some port -> port
    | None -> let filename = String.concat
                ~sep:Filename.dir_sep [(Sys.getenv_exn "HOME");
                                       ".lein"; "repl-port"] in
              match Sys.file_exists filename with
                | `Yes -> In_channel.read_all filename
                | `No | `Unknown -> port_err ()

let main cwd root args =
  let port = Int.of_string (repl_port root) in
  let message = eval_message cwd root args in
  Nrepl.new_session "127.0.0.1" port message handler

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
      | Some args -> main root cwd args;
        never_returns (Scheduler.go ())
