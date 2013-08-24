open Async.Std
open Core.Std

let buffer_size = (1024 * 16)

let send message w =
  let encoded = Bencode.marshal (Bencode.Dict(message)) in
  Writer.write w encoded


let get_leftover buffer parsed bytes_read =
  match parsed with
    | Some parsed ->
      let bytes_parsed = String.length (Bencode.marshal parsed) in
      let length = bytes_read - bytes_parsed in
      String.sub buffer bytes_parsed length
    | None -> String.sub buffer 0 bytes_read

let rec receive_until_done r handler buffer partial close =
  let parse_single = fun raw bytes_read ->
    let parsed = try Some (Bencode.parse raw) with
      | _ -> None in
    let leftover = get_leftover buffer parsed bytes_read in
    (parsed, leftover) in

  let rec handle_responses = fun handler raw bytes_read ->
    match parse_single raw bytes_read with
      | Some Bencode.Dict parsed, leftover -> handler raw parsed;
        handle_responses handler leftover (bytes_read - (String.length (Bencode.marshal (Bencode.Dict parsed))))
      | Some parsed, leftover -> Printf.printf "Unexpected response: %s %s\n%!"
        (Bencode.string_of_type parsed) (Bencode.marshal parsed);
        handle_responses handler leftover bytes_read
      | None, leftover -> leftover in

  let parse_response = fun handler buffer close resp ->
    match resp with
      | `Eof -> close ()
      | `Ok bytes_read -> let raw = String.sub buffer 0 bytes_read in
                          let partial =
                            handle_responses handler raw bytes_read in
                          receive_until_done r handler buffer partial close in

  String.blit partial 0 buffer 0 (String.length partial);
  Reader.read r buffer >>= parse_response handler buffer close

let send_and_receive host port message handler =
  let _ = Tcp.connect (Tcp.to_host_and_port host port)
          >>= (fun (_, r, w) ->
            send message w;
            receive_until_done r handler
              (String.create buffer_size) ""
              (fun () -> Reader.close r)) in ()
