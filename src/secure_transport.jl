using HTTP
using Sockets: IPAddr
using OpenSSL_CLI_jll
using ..ObliviousOffload: ConnectParams

# OpenSSL_CLI_jll's compiled-in OPENSSLDIR points at its build environment and usually
# does not exist on the host, making openssl fail to load its config file. Point
# OPENSSL_CONF at an empty file instead; all required extensions are passed
# explicitly on the command line, so no config is needed.
openssl(args::Cmd) = addenv(`$(OpenSSL_CLI_jll.openssl()) $args`,
                            "OPENSSL_CONF" => Sys.iswindows() ? "nul" : "/dev/null")

function is_valid_cert(cert; ca=nothing)
    isfile(cert) || return false
    if !isnothing(ca)
        success(openssl(`verify -CAfile $ca $cert`)) || return false
    end
    success(openssl(`x509 -in $cert -checkend 86400 -noout`)) || return false
    return true
end

function generate_ca(conn)
    mkpath(conn.cert_dir)
    run(openssl(`req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1
         -keyout $(conn.ca_key_path) -out $(conn.ca_cert_path) -days 3650 -nodes
         -subj "/CN=ObliviousOffload Dev CA"
         -addext basicConstraints=critical,CA:TRUE
         -addext keyUsage=critical,keyCertSign,cRLSign`))
end

function generate_server_cert(conn)
    mkpath(conn.cert_dir)

    run(openssl(`req -newkey ec -pkeyopt ec_paramgen_curve:prime256v1
         -keyout $(conn.server_privkey_path) -out $(conn.signing_request_path) -nodes
         -subj /CN=localhost`))

    # TLS matches IP addresses only against "IP:" SAN entries
    # and DNS names only against "DNS:" entries.
    # We must set the entry type based on what `hostname` is.
    # parse(IPAddr, ...) throws when hostname is not a valid IPv4/IPv6 literal,
    # i.e. when it is a DNS name.
    is_ip = try; parse(IPAddr, conn.hostname); true; catch; false; end
    host_san = is_ip ? "IP:$(conn.hostname)" : "DNS:$(conn.hostname)"
    write(conn.san_config_path, "subjectAltName=$host_san,IP:127.0.0.1")
    run(openssl(`x509 -req -in $(conn.signing_request_path) -CA $(conn.ca_cert_path) -CAkey $(conn.ca_key_path)
         -CAcreateserial -out $(conn.server_cert_path) -days 365
         -extfile $(conn.san_config_path)`))

    rm(conn.signing_request_path, force=true)
    rm(conn.san_config_path, force=true)
end

function fingerprint(cert)
    chomp(read(openssl(`x509 -in $cert -fingerprint -sha256 -noout`), String))
end

ca_fingerprint() = fingerprint(ConnectParams().ca_cert_path)
ca_fingerprint(conn::ConnectParams) = fingerprint(conn.ca_cert_path)

function ensure_ca(conn)
    if !is_valid_cert(conn.ca_cert_path)
        generate_ca(conn)
    end
end


function ensure_server(conn)
    ensure_ca(conn)
    if !is_valid_cert(conn.server_cert_path; ca=conn.ca_cert_path)
        generate_server_cert(conn)
    end
end

function offer_handshake(conn)
    println("CA certificate fingerprint: $(ObliviousOffload.ca_fingerprint(conn))")
    return read(conn.ca_cert_path)
end

function perform_handshake(ca_binary, conn)
    pem = tempname()
    write(pem, ca_binary)
    fp = try
        fingerprint(pem)
    catch
        rm(pem, force=true)
        error("response body is not a valid PEM certificate")
    end

    @info "Received CA certificate, fingerprint: $fp"

    mkpath(conn.cert_dir)
    mv(pem, conn.trusted_ca_path, force=true)

    @info "CA certificate automatically trusted and saved. You must manually check that the fingerprint is correct." path = conn.trusted_ca_path
end