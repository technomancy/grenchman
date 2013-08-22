open Core.Std
open Async.Std

let send message w =
  Writer.write w (Bencode.marshal (Bencode.Dict(message)))

(* handle partial responses buffering up *)
let parse_response handler buffer resp =
  match resp with
    | `Eof -> ()
    | `Ok length -> let response_string = String.sub buffer 0 length in
                    Printf.printf "%s" response_string;
                    (Bencode.parse response_string
                        |> Bencode.to_dict
                        |> handler)

let with_connection host port message handler =
  let buffer = String.create (16 * 1024) in
  let _ = Tcp.connect (Tcp.to_host_and_port host port)
          >>= (fun (s, r, w) ->
            send message w;
            Writer.flushed w >>=
              (fun () ->
                Reader.read r buffer >>| parse_response handler buffer)) in ()
