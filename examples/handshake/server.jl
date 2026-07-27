using ObliviousOffload


server = ObliviousOffload.OffloadServer()

function handshake()
    println("CA certificate fingerprint: $(ObliviousOffload.secure_transport.ca_fingerprint())")
    return read(ObliviousOffload.ConnectParams().ca_cert_path)
end

ObliviousOffload.register!(server, "handshake", handshake)

# Block only when executed as a script (`julia server.jl`), not when included
# This is required by the test suite, which starts the server in-process and closes it itself.
if abspath(PROGRAM_FILE) == @__FILE__
    wait(server)
end