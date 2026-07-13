module secure_transport

using HTTP
import ..ObliviousOffload: load_config
using OpenSSL_CLI_jll
using Preferences: @load_preference

const CERT_DIR = @load_preference("cert_dir", Ref(joinpath(pwd(), "certs")))


function cert_path(name)
    joinpath(CERT_DIR[], name)
end

const ca_cert = @load_preference("ca_cert_path", cert_path("ca.pem"))
const ca_key = @load_preference("ca_key_path", cert_path("ca-key.pem"))
const extfile = @load_preference("san_config_path", cert_path("san.cnf"))

const csr = @load_preference("signing_request_path", cert_path("server.csr"))
# Following naming convention from LetsEncrypt / Certbot
# https://eff-certbot.readthedocs.io/en/stable/using.html#where-are-my-certificates
# We dont have a chain / fullchain, because our private ca directly signs the csr
const server_key = @load_preference("server_privkey_path", cert_path("privkey.pem"))
const server_cert = @load_preference("server_cert_path", cert_path("cert.pem"))


const remote_ca_cert = @load_preference("trusted_ca_path", cert_path("remote-ca.pem"))

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

function generate_ca()
    mkpath(CERT_DIR[])
    run(openssl(`req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1
         -keyout $ca_key -out $ca_cert -days 3650 -nodes
         -subj "/CN=ObliviousOffload Dev CA"
         -addext basicConstraints=critical,CA:TRUE
         -addext keyUsage=critical,keyCertSign,cRLSign`))
end

function generate_server_cert()
    (; hostname) = load_config()
    mkpath(CERT_DIR[])

    run(openssl(`req -newkey ec -pkeyopt ec_paramgen_curve:prime256v1
         -keyout $server_key -out $csr -nodes
         -subj /CN=localhost`))

    write(extfile, "subjectAltName=DNS:$hostname,IP:127.0.0.1")
    run(openssl(`x509 -req -in $csr -CA $ca_cert -CAkey $ca_key
         -CAcreateserial -out $server_cert -days 365
         -extfile $extfile`))

    rm(csr, force=true)
    rm(extfile, force=true)
end

function fingerprint(cert)
    chomp(read(openssl(`x509 -in $cert -fingerprint -sha256 -noout`), String))
end

ca_fingerprint() = fingerprint(ca_cert)


function fetch_ca()
    # We dont have the CA.pem yet, so we cannot verify the ssl certificate (we must set require_ssl_verification=false)
    # To solve this problem of trust, we print the CA.pem fingerprint on both the server and the client
    # The user setting up the client must initially manually trust the CA.pem by verifying its fingerprint 
    (; port, hostname) = load_config()
    host = "https://$hostname:$port"
    response = HTTP.get("$host/handshake"; require_ssl_verification=false) 

    content_type = HTTP.header(response, "Content-Type")
    content_type == "application/x-pem-file" ||
        error("expected application/x-pem-file, got $content_type")

    # Write to a temp file first so we can fingerprint it before the user accepts
    pem = tempname()
    write(pem, response.body)
    fp = try
        fingerprint(pem)
    catch
        rm(pem, force=true)
        error("response body is not a valid PEM certificate")
    end

    println("Received CA certificate from $hostname")
    println(fp)
    mkpath(CERT_DIR[])
    mv(pem, remote_ca_cert, force=true)
    @info "WARNING: CA certificate trusted saved. You must manually check that the fingerprint is correct." path = remote_ca_cert
    return remote_ca_cert
end


function ensure_ca()
    if !is_valid_cert(ca_cert)
        generate_ca()
    end
end


function ensure_server()
    ensure_ca()
    if !is_valid_cert(server_cert; ca=ca_cert)
        generate_server_cert()
    end
end

function handshake(req)
    ensure_server()
    @info "CA certificate fingerprint: $(ca_fingerprint())"
    println("CA certificate fingerprint: $(ca_fingerprint())")
    return HTTP.Response(200, ["Content-Type" => "application/x-pem-file"], read(ca_cert))
end

end # module secure_transport
