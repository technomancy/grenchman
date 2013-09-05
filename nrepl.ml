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
    { out = Printf.printf "%s\n%!";
      err = Printf.eprintf "%s\n%!";
      ex = Printf.eprintf "%s\n%!";
      value = do_nothing;
    }

let quiet_actions =
  { default_actions with out = do_nothing; }

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

let send w pending (message,actions) =
  let converted = Bencode.Dict(convert_message message []) in
  let out = Bencode.marshal converted in
  debug ("-> " ^ out);
  Writer.write w out;
  match List.Assoc.find message "id" with
    | Some id -> Hashtbl.replace pending ~key:id ~data:actions
    | None -> Printf.eprintf "  Sending message without id!\n%!"

let rec receive_until_done (r,w,p) handler buffer partial =
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
        let re_encoded = (Bencode.marshal (Bencode.Dict parsed)) in
        debug ("<- " ^ re_encoded);
        handle_responses handler leftover
      | Some parsed, leftover -> Printf.printf "Unexpected %s: %s | %s \n%!"
        (Bencode.string_of_type parsed) (Bencode.marshal parsed) leftover;
        handle_responses handler leftover
      | None, leftover -> leftover in

  let parse_response handler buffer partial resp =
    match resp with
      | `Eof -> 
         debug "Eof seen";
         Reader.close r
      | `Ok bytes_read -> let just_read = String.sub buffer 0 bytes_read in
                          let partial =
                            handle_responses handler (partial ^ just_read) in
                          receive_until_done (r,w,p) handler buffer partial in

  debug "Receiving message";
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

let rec send_messages (w,p) messages session =
  debug "Sending message";
  match messages with
  | message :: tail ->
     message session |> send w p;
     send_messages (w,p) tail session
  | [] -> ()

(* Write a list of messages to the nrepl server *)
let send_all_messages (w,p) messages session =
  let f ivar =
    Ivar.fill ivar (send_messages (w,p) messages session)
  in
  Deferred.create f

(* Returns a deferred tuple with a session id *)
let initiate_session (s,r,w,p) buffer =
  Reader.read r buffer
  >>= fun resp -> return (s,r,w,p,get_session buffer resp)

(* Create a new session *)
let new_session host port messages handler =
  let buffer = (String.create buffer_size) in
  let pending = String.Table.create () in
  Tcp.connect (Tcp.to_host_and_port host port)
  >>= (fun (s, r, w) ->
    send w pending ([("op", "clone"); ("id", "init")], quiet_actions);
    initiate_session (s,r,w,pending) buffer
    >>= (fun (_, r, w, p, session) ->
         ignore (send_all_messages (w,p) messages session);
         receive_until_done (r,w,p) handler buffer ""))
