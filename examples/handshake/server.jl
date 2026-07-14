using ObliviousOffload


server, router = ObliviousOffload.create_server()

function handshake()
    ObliviousOffload.secure_transport.ensure_server()
    println("CA certificate fingerprint: $(ObliviousOffload.secure_transport.ca_fingerprint())")
    return read(ObliviousOffload.secure_transport.ca_cert)
end

ObliviousOffload.register(router, "handshake", handshake)
wait(server)