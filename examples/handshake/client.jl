using ObliviousOffload

function run_client(;kwargs...)
    conn = ConnectParams(;kwargs..., insecure_tls=true)
    handshake_data = offload(conn, "handshake")
    ObliviousOffload.perform_handshake(handshake_data, conn)
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_client()
end