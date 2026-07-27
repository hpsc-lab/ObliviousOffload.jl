using ObliviousOffload

function run_server(; kwargs...)
    conn = ObliviousOffload.ConnectParams(; kwargs..., insecure_tls=true)
    server = ObliviousOffload.OffloadServer(conn)

    function handshake()
        println("CA certificate fingerprint: $(ObliviousOffload.secure_transport.ca_fingerprint(conn))")
        return read(conn.ca_cert_path)
    end

    ObliviousOffload.register!(server, "handshake", handshake)
    return server
end



# Block only when executed as a script (`julia server.jl`), not when included
# This is required by the test suite, which starts the server in-process and closes it itself.
if abspath(PROGRAM_FILE) == @__FILE__
    include("../parse_args.jl")
    kwargs = parse_commandline()
    server = run_server(;kwargs...)
    wait(server)
end