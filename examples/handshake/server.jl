using ObliviousOffload

function run_server(; kwargs...)
    conn = ConnectParams(; kwargs..., insecure_tls=true)
    server = OffloadServer(conn)

    register_service!(server, "handshake", ObliviousOffload.offer_handshake, conn)
    return server
end



# Block only when executed as a script (`julia server.jl`), not when included
# This is required by the test suite, which starts the server in-process and closes it itself.
if abspath(PROGRAM_FILE) == @__FILE__
    server = run_server()
    wait(server)
end