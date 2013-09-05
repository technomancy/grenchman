open Async.Std
open Core.Std
open Printf

let splice_args args =
  String.concat ~sep:"\" \"" (List.map args String.escaped)

(* A message to require the main names - no ns field sent *)
let require ns session =
  ([("session", session);
    ("op", "eval");
    ("id", Uuid.to_string (Uuid.create ()));
    ("code", "(require '" ^ ns ^")")],
   {Nrepl.default_actions with Nrepl.value = Nrepl.do_nothing})

(* A message to run the main - ns field sent, so namespace
   has to have been previously required. *)
let eval ns form session =
  ([("session", session);
    ("op", "eval");
    ("id", Uuid.to_string (Uuid.create ()));
    ("ns", ns);
    ("code", form)],
   Nrepl.default_actions)

let main ns form port =
  ignore (Nrepl.new_session "127.0.0.1" port
                            [require ns;
                             eval ns form]
                            Repl.handler);
  never_returns (Scheduler.go ())

let port_err msg =
  eprintf "%s\n%!" msg;
  Pervasives.exit 1

(* Return an optional int for the port number, based on
   an environment variable or on the contents of the
   specified filename, if it exists. *)
let repl_port env_var filename =
  match Sys.getenv env_var with
  | Some port -> Some (int_of_string port)
  | None -> match Sys.file_exists filename with
            | `Yes -> Some (int_of_string (In_channel.read_all filename))
            | `No | `Unknown -> None

let rec find_root cwd original =
  match Sys.file_exists (String.concat ~sep:Filename.dir_sep
                           [cwd; "project.clj"]) with
    | `Yes -> cwd
    | `No | `Unknown -> if (Filename.dirname cwd) = cwd then
        original
      else
        find_root (Filename.dirname cwd) original
