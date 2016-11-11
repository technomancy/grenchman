open Async.Std
open Core.Std

type msg_actions =
    { out : string -> unit;
      err : string -> unit;
      ex : string -> unit;
      value : string -> unit;
    }

let do_nothing _ = ()

let default_actions =
    { out = Printf.printf "%s%!";
      err = Printf.eprintf "%s%!";
      value = do_nothing;
      ex = do_nothing;
    }

let quiet_actions =
  { default_actions with out = do_nothing; }

let exit_actions =
  { default_actions with ex = fun e -> Pervasives.exit 1 }

let print_all =
  { default_actions with value = Printf.printf "%s\n%!"; }

let buffer_size = (1024 * 16)

let debug out =
  match Sys.getenv "DEBUG" with
    | Some _ -> Printf.printf "%s\n%!" out
    | None -> ()

let rec convert_message message converted =
  match message with
    | (k, v) :: tl -> convert_message tl ((k, Bencode.String(v)) :: converted)
    | [] -> converted

let current_msg_id = ref ""

let send w pending (message,actions) =
  let converted = Bencode.Dict(convert_message message []) in
  let out = Bencode.marshal converted in
  debug ("-> " ^ out);
  Writer.write w out;
  match List.Assoc.find message "id" with
    | Some id ->
      Hashtbl.set pending ~key:id ~data:actions;
      current_msg_id := id
    | None -> Printf.eprintf "  Sending message without id!\n%!"

let rec loop (r,w,p) handler buffer partial =
  let parse_single contents =
    try let parsed = Bencode.parse contents in
        let bytes_parsed = String.length (Bencode.marshal parsed) in
        let total_bytes = String.length contents in
        let leftover_length = total_bytes - bytes_parsed in
        let leftover = String.sub contents bytes_parsed leftover_length in
        (Some parsed, leftover)
    with
      | _ -> (None, contents) in

  let rec handle_responses handler contents =
    match parse_single contents with
      | Some Bencode.Dict parsed, leftover -> handler (r,w,p) contents parsed;
        debug ("<- " ^ (Bencode.marshal (Bencode.Dict parsed)));
        handle_responses handler leftover
      | Some parsed, leftover -> Printf.printf "Unexpected %s: %s | %s \n%!"
        (Bencode.string_of_type parsed) (Bencode.marshal parsed) leftover;
        handle_responses handler leftover
      | None, leftover -> leftover in

  let parse_response handler buffer partial resp =
    match resp with
      | `Eof -> Pervasives.exit 0
      | `Ok bytes_read -> let just_read = String.sub buffer 0 bytes_read in
                          let partial =
                            handle_responses handler (partial ^ just_read) in
                          loop (r,w,p) handler buffer partial in

  Reader.read r buffer >>= parse_response handler buffer partial

let get_session buffer resp =
  let no_session ()  = Printf.eprintf "No session!"; Pervasives.exit 0 in
  match resp with
    | `Eof -> no_session ()
    | `Ok bytes_read -> match Bencode.parse (String.sub buffer 0 bytes_read) with
        | Bencode.Int _ | Bencode.String _ | Bencode.List _ -> no_session ()
        | Bencode.Dict(d) -> match List.Assoc.find d "new-session" with
            | Some Bencode.String(session) -> session
            | Some _ | None -> no_session ()

let interrupt_message session id =
  ([("session", session);
    ("op", "interrupt");
    ("id", "interrupt-" ^ (Uuid.to_string (Uuid.create ())));
    ("interrupt-id", id)],
   quiet_actions)

let interrupt session w p _ =
  match Hashtbl.keys p with
    | ["init"] | [] -> Pervasives.exit 0
    | _ -> send w p (interrupt_message session !current_msg_id)

let register_interrupt session w p =
  Caml.Sys.signal Caml.Sys.sigint (Caml.Sys.Signal_handle (interrupt session w p))

let rec send_messages (w,p) messages session =
  match messages with
  | message :: tail ->
     message session |> send w p;
     send_messages (w,p) tail session
  | [] -> ()

let defer_send_messages (w,p) messages session =
  let f ivar = Ivar.fill ivar (send_messages (w,p) messages session) in
  Deferred.create f

let initiate_session (s,r,w,p) buffer =
  Reader.read r buffer
  >>| fun resp -> (s,r,w,p,get_session buffer resp)

let connect host port messages handler =
  let buffer = (String.create buffer_size) in
  let pending = String.Table.create () in
  Tcp.connect (Tcp.to_host_and_port host port)
  >>= (fun (s, r, w) ->
    send w pending ([("op", "clone"); ("id", "init")], quiet_actions);
    initiate_session (s,r,w,pending) buffer
    >>= (fun (_, r, w, p, session) ->
      ignore (register_interrupt session w p);
      ignore (defer_send_messages (w,p) messages session);
      loop (r,w,p) handler buffer ""))

(* Create a new session *)
let new_session host port messages handler =
  try_with (fun () -> connect host port messages handler)
  >>| function
    | Ok () -> ()
    | Error _ ->
      eprintf "Could not connect on port %i.\n%!" port;
      Pervasives.exit 111
