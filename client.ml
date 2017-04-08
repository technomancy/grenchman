open Async.Std
open Core.Std
open Printf

let exit = Pervasives.exit

let ns = ref "user"
let exit_code = ref 0

let eval_message code ns session =
  Nrepl.eval_message
    code ns
    ~actions:{ Nrepl.default_actions with
               Nrepl.value = fun v ->
                             try
                               exit_code := int_of_string v
                             with
                               Failure "int_of_string" -> ()}
    session

let send_input resp (r,w,p) result =
  match (Nrepl.response_session resp) with
    | Some session -> (match result with
        | Some input -> Nrepl.send w p (Nrepl.stdin_message input session)
        (* TODO: only exit on EOF in a top-level input request *)
        | None -> Nrepl.debug "Eof seen"; exit 0)
    | None -> eprintf "  No session in need-input.\n"

let handle_done (r,w,p) resp =
  if Nrepl.pending_ids p = ["init"] then
    exit !exit_code

let rec handler handle_done (r,w,p) raw resp =

  let resp_actions = Nrepl.response_actions p resp in

  let handle k v = match (k, v) with
    | ("out", out) -> resp_actions.Nrepl.out out
    | ("err", out) -> resp_actions.Nrepl.err out
    | ("ex", out) | ("root-ex", out) -> resp_actions.Nrepl.ex out
    | ("value", value) -> resp_actions.Nrepl.value value
    | ("ns", new_ns) -> ns := new_ns
    | ("session", _) | ("id", _) -> ()
    | (k, v) -> printf "  Unknown response: %s %s\n%!" k v in

  let handle_status status =
    match status with
      | Bencode.String "done" ->
        Nrepl.remove_pending p (Nrepl.response_id resp);
        resp_actions.Nrepl.after_message ();
        handle_done (r,w,p) resp
      | Bencode.String "eval-error" ->
         resp_actions.Nrepl.eval_error (r,w,p) resp
      | Bencode.String "unknown-session" ->
        eprintf "Unknown session.\n"
      | Bencode.String "need-input" ->
        ignore (send_input resp (r,w,p) (Readline.read "")); ()
      | Bencode.String "interrupted" -> print_newline ()
      | x -> printf "  Unknown status: %s\n%!" (Bencode.marshal x) in

  let handle_clause clause =
    match clause with
      | k, Bencode.String v -> handle k v
      | "status", Bencode.List(status) -> List.iter status handle_status
      | k, v ->
        eprintf "  Unknown %s response: %s %s\n%!"
                (Bencode.string_of_type v) k raw in

  List.iter resp handle_clause

let eval port messages handle_done =
  let handler = handler handle_done in
  let _ = Nrepl.new_session "127.0.0.1" port messages handler in
  never_returns (Scheduler.go ())

(* invoking main functions *)

let rec find_root cwd original =
  match Sys.file_exists (String.concat ~sep:Filename.dir_sep
                           [cwd; "project.clj"]) with
    | `Yes -> cwd
    | `No | `Unknown -> if (Filename.dirname cwd) = cwd then
        original
      else
        find_root (Filename.dirname cwd) original

let quoted s =
  "\"" ^ (String.escaped s) ^ "\""

let splice_args args =
  String.concat ~sep:" " (List.map args quoted)

let main_form =
  sprintf "(do
             (require '[clojure.stacktrace :refer [print-cause-trace]])
             (let [raw (symbol \"%s\")
                   ns (symbol (or (namespace raw) raw))
                   m-sym (if (namespace raw) (symbol (name raw)) '-main)]
               (require ns)
               (try ((ns-resolve ns m-sym) %s)
               (catch Exception e
                 (let [c (:exit-code (ex-data e) 1)]
                   (when-not (and (number? c) (zero? c))
                     (print-cause-trace e))
                   c)))))"

let main port args =
  match args with
    | [] -> eprintf "Missing ns argument."; exit 1
    | ns :: args -> let form = main_form ns (splice_args args) in
                    let messages = [eval_message form "user"] in
                    eval port messages handle_done

let stdin_eval port =
  let input = In_channel.input_lines stdin |> String.concat ~sep:"\n" in
  main port ["clojure.main/main"; "-e"; input]
