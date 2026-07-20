using ObliviousOffload


server, router = ObliviousOffload.create_server()

function handshake()
    ObliviousOffload.secure_transport.ensure_server()
    println("CA certificate fingerprint: $(ObliviousOffload.secure_transport.ca_fingerprint())")
    return read(ObliviousOffload.secure_transport.ca_cert)
end

ObliviousOffload.register(router, "handshake", handshake)

# Block only when executed as a script (`julia server.jl`), not when included
# This is required by the test suite, which starts the server in-process and closes it itself.
if abspath(PROGRAM_FILE) == @__FILE__
    wait(server)
end