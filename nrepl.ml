open Core.Std
open Async.Std

let send message w =
  Writer.write w (Bencode.marshal (Bencode.Dict(message)))

let parse_response handler text =
  handler (Bencode.parse text)

let with_connection host port message handler =
  Tcp.with_connection
    (Tcp.to_host_and_port host port)
    (fun _ r w ->
      return (send message w)
      (* Reader.read r >>= parse_response handler *)
    )
