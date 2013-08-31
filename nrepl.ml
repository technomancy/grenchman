open Async.Std
open Core.Std

let buffer_size = (1024 * 16)

let debug out =
  match Sys.getenv "DEBUG" with
    | Some _ -> Printf.printf "%s\n%!" out
    | None -> ()

let rec convert_message message converted =
  match message with
    | (k, v) :: tl -> convert_message tl ((k, Bencode.String(v)) :: converted)
    | [] -> converted

let send w pending message =
  let converted = Bencode.Dict(convert_message message []) in
  let out = Bencode.marshal converted in
  debug ("-> " ^ out);
  Writer.write w out;
  match List.Assoc.find message "id" with
    | Some id -> pending := id :: (! pending)
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
      | `Eof -> Reader.close r
      | `Ok bytes_read -> let just_read = String.sub buffer 0 bytes_read in
                          let partial =
                            handle_responses handler (partial ^ just_read) in
                          receive_until_done (r,w,p) handler buffer partial in

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

let initiate (r,w,p) buffer handler message resp =
  get_session buffer resp |> message |> send w p;
  receive_until_done (r,w,p) handler buffer ""

let new_session host port message handler =
  let buffer = (String.create buffer_size) in
  let pending = ref [] in
  Tcp.connect (Tcp.to_host_and_port host port)
  >>= (fun (_, r, w) ->
    send w pending [("op", "clone"); ("id", "init")];
    Reader.read r buffer >>= initiate (r,w,pending) buffer handler message)
