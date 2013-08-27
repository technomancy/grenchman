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

let get_leftover buffer parsed bytes_read =
  match parsed with
    | Some parsed ->
      let bytes_parsed = String.length (Bencode.marshal parsed) in
      let length = bytes_read - bytes_parsed in
      String.sub buffer bytes_parsed length
    | None -> String.sub buffer 0 bytes_read

let rec receive_until_done (r,w,p) handler buffer partial =
  let parse_single raw bytes_read =
    let parsed = try Some (Bencode.parse raw) with
      | _ -> None in
    let leftover = get_leftover buffer parsed bytes_read in
    (parsed, leftover) in

  let rec handle_responses handler raw bytes_read =
    match parse_single raw bytes_read with
      | Some Bencode.Dict parsed, leftover -> handler (r,w,p) raw parsed;
        let re_encoded = (Bencode.marshal (Bencode.Dict parsed)) in
        let bytes_parsed = String.length re_encoded in
        debug ("<- " ^ re_encoded);
        handle_responses handler leftover (bytes_read - bytes_parsed)
      | Some parsed, leftover -> Printf.printf "Unexpected %s: %s | %s \n%!"
        (Bencode.string_of_type parsed) (Bencode.marshal parsed) leftover;
        handle_responses handler leftover bytes_read
      | None, leftover -> leftover in

  let parse_response handler buffer resp =
    match resp with
      | `Eof -> Reader.close r
      | `Ok bytes_read -> let raw = String.sub buffer 0 bytes_read in
                          let partial =
                            handle_responses handler raw bytes_read in
                          receive_until_done (r,w,p) handler buffer partial in

  String.blit partial 0 buffer 0 (String.length partial);
  Reader.read r buffer >>= parse_response handler buffer

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
