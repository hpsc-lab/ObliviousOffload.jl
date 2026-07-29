using ObliviousOffload

function run_client(;kwargs...)
    conn = ConnectParams(;kwargs..., insecure_tls=true)
    ca_binary = offload(conn, "handshake")

    pem = tempname()
    write(pem, ca_binary)
    fp = try
        ObliviousOffload.fingerprint(pem)
    catch
        rm(pem, force=true)
        error("response body is not a valid PEM certificate")
    end

    @info "Received CA certificate, fingerprint: $fp"

    mkpath(conn.cert_dir)
    mv(pem, conn.trusted_ca_path, force=true)

    @info "CA certificate automatically trusted and saved. You must manually check that the fingerprint is correct." path = conn.trusted_ca_path
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_client()
end