open Async.Std
open Core.Std

let buffer_size = 1024

let send message w =
  let encoded = Bencode.marshal (Bencode.Dict(message)) in
  Writer.write w encoded

(* TODO: handle case of reading too much into buffer at once *)
let rec receive_until_done r handler buffer id close =
  let parse_response = fun handler buffer id close resp ->
    match resp with
      | `Eof -> close ()
      | `Ok length -> let response_str = String.sub buffer 0 length in
                      handler response_str (Bencode.to_dict (Bencode.parse response_str));
                      receive_until_done r handler buffer id close in
  Reader.read r buffer >>= parse_response handler buffer id close


let send_and_receive host port message handler =
  let _ = Tcp.connect (Tcp.to_host_and_port host port)
          >>= (fun (_, r, w) ->
            send message w;
            receive_until_done r handler
              (String.create buffer_size)
              (List.Assoc.find message "id")
              (fun () -> Reader.close r)) in ()
