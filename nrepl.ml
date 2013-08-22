open Async.Std
open Core.Std

let send message w =
  let encoded = Bencode.marshal (Bencode.Dict(message)) in
  Writer.write w encoded

(* handle partial responses buffering up *)
let parse_response handler buffer resp =
  match resp with
    | `Eof -> ()
    | `Ok length -> let response_string = String.sub buffer 0 length in
                    (Bencode.parse response_string
                        |> Bencode.to_dict
                        |> handler)

let send_and_receive host port message handler =
  let buffer = String.create 1024 in
  let _ = Tcp.connect (Tcp.to_host_and_port host port)
          >>= (fun (s, r, w) ->
            send message w;
            Reader.read r buffer >>| parse_response handler buffer) in ()
