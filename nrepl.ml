open Core.Std
open Async.Std

let send message w =
  Writer.write w (Bencode.marshal (Bencode.Dict(message)))

let parse_response handler buffer resp =
  match resp with
    | `Eof -> ()
    | `Ok length -> (handler (Bencode.to_dict (Bencode.parse (String.sub buffer 0 length))))

let with_connection host port message handler =
  let buffer = String.create (16 * 1024) in
  Tcp.with_connection
    (Tcp.to_host_and_port host port)
    (fun _ r w ->
      send message w;
      Writer.flushed w >>=
        (fun () ->
          Reader.read r buffer >>| parse_response handler buffer))
