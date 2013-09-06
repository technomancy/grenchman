open Async.Std
open Core.Std

let port_err =
  "Couldn't read port from .nrepl-port or LEIN_REPL_PORT.\n
If Leiningen is not running, launch `lein repl :headless' from the
project directory and try again.\n"

let rec repl_port port_file =
  let filename = match port_file with
    | Some s -> s
    | None -> let cwd = Sys.getcwd () in
              let root = Client.find_root cwd cwd in
              String.concat ~sep:Filename.dir_sep [root; ".nrepl-port"] in
  match Client.repl_port "LEIN_REPL_PORT" filename with
  | Some p -> p
  | None -> Printf.eprintf
              "%s\n%!"
              ("Could not find repl to connect to, and jarpath and " ^
                 "port-file are not specified, so cannot start one");
            Pervasives.exit 1

let main_form =
  Printf.sprintf "(do
                    (use '%s)
                    (require '[clojure.stacktrace :refer [print-cause-trace]])
                    (binding [*exit-process?* false]
                      (try (-main \"%s\")
                      (catch Exception e
                        (let [c (:exit-code (ex-data e))]
                          (when-not (and (number? c) (zero? c))
                            (print-cause-trace e)))))))"

let do_main ~port ~port_file ~ns ~args =
  if ! Sys.interactive then () else
    let port = match port with
      | Some x -> x
      | None -> repl_port port_file in
    let cmd = main_form ns (Client.splice_args args) in
    Client.main ns cmd port

(* a fold function to split a list on a "--" element *)
let splitf (args,others) e =
    match others with
    | None -> if e = "--" then
                (args, Some [])
              else
                (List.append args [e], None)
    | Some l -> (args, Some (List.append l [e]))

let opt_name (short,long,desc,flag) =
  String.sub long 2 ((String.length long) - 2)

let opt_flag (short,long,desc,flag) =
  flag

let option_matches e (short,long,desc,flag) =
  (short = e) || (long = e)

(* a fold function to process options *)
let optionf options (found, args, in_option) e =
    match in_option with
    (* In an option match, assign the value to the open option *)
    | Some opt -> (List.append found [(opt_name opt, e)],
                   args, None)
    (* Look for a matching option *)
    | None ->
       match List.find options (option_matches e) with
       | None -> (found, List.append args [e], None)
       | Some opt ->
          if opt_flag opt then
            (List.append found [(opt_name opt, "true")], args, Some opt)
          else
            (found, args, Some opt)

let process_args args options =
  let (args,others) = List.fold args ~init:([],None) ~f:splitf in
  let (options,args,_) =
    List.fold args ~init:([],[],None) ~f:(optionf options) in
  match others with
  | Some l -> (options,List.append args l)
  | None -> (options, args)

(* Run a clojure main *)
let main args =
  let (options,args) =
    process_args
      args
      [("-p", "--port", "Port to connect to", false);
       ("-f", "--port-file", "Port file for nREPL server", false);]
  in
  let port = match (List.Assoc.find options "port") with
    | None -> None
    | Some p -> Some (int_of_string p) in
  let args = List.to_array args in
  do_main ~port:port
          ~port_file:(List.Assoc.find options "port-file")
          ~ns:(Array.get args 0)
          ~args:(Array.to_list (Array.sub args 1 ((Array.length args) - 1)))
