module ObliviousOffload

using Serialization
using Dates
using HTTP
using Reseau.TLS
using Base64
using Preferences: @load_preference
export OffloadServer, ConnectParams, register_service!, offload

struct ConnectParams
    port::Union{Int, String}
    hostname::String
    username
    password
    cert_dir::String
    ca_cert_path::String
    ca_key_path::String
    trusted_ca_path::String
    server_privkey_path::String
    server_cert_path::String
    san_config_path::String
    signing_request_path::String
    insecure_tls::Bool
    # Computed properties
    host::String
    basicauth

    function ConnectParams(;
        port = @load_preference("port", 8080),
        hostname = @load_preference("hostname", "localhost"),
        username = @load_preference("username", nothing),
        password = @load_preference("password", nothing),
        cert_dir = @load_preference("cert_dir", "certs/"),
        ca_cert_path = @load_preference("ca_cert_path", joinpath(cert_dir, "ca.pem")),
        ca_key_path = @load_preference("ca_key_path", joinpath(cert_dir, "ca-key.pem")),
        trusted_ca_path = @load_preference("trusted_ca_path", joinpath(cert_dir, "remote-ca.pem")),
        # Following naming convention from LetsEncrypt / Certbot
        # https://eff-certbot.readthedocs.io/en/stable/using.html#where-are-my-certificates
        # We don't have a chain / fullchain, because our private ca directly signs the csr
        server_privkey_path = @load_preference("server_privkey_path", joinpath(cert_dir, "privkey.pem")),
        server_cert_path = @load_preference("server_cert_path", joinpath(cert_dir, "cert.pem")),
        san_config_path = @load_preference("san_config_path", joinpath(cert_dir, "san.cnf")),
        signing_request_path = @load_preference("signing_request_path", joinpath(cert_dir, "server.csr")),
        insecure_tls = false,
    )
        host = "https://$hostname:$port"

        # Reset auth credentials when using insecure TLS (e.g., during handshake)
        if insecure_tls && (username !== nothing || password !== nothing)
            @warn "Authentication cannot be used with insecure TLS. Username and password have been reset to nothing."
            username = nothing
            password = nothing
        end

        basicauth = if username !== nothing && password !== nothing
            (username, password)
        else
            nothing
        end
        new(
            port,
            hostname,
            username,
            password,
            cert_dir,
            ca_cert_path,
            ca_key_path,
            trusted_ca_path,
            server_privkey_path,
            server_cert_path,
            san_config_path,
            signing_request_path,
            insecure_tls,
            host,
            basicauth,
        )
    end
end

include("secure_transport.jl")
using .secure_transport

"""
    make_part(obj) -> HTTP.Multipart

Serialize `obj` into an `HTTP.Multipart` part using Julia's `Serialization` stdlib.

The content type `application/x-julia-serialized-object` follows the convention
established by Java's `application/x-java-serialized-object` for language-specific
serialized objects.
"""
function make_part(obj)
    io = IOBuffer()
    serialize(io, obj)
    seekstart(io)
    HTTP.Multipart(nothing, io, "application/x-julia-serialized-object")
end

"""
    parse_parts(parts::Vector{HTTP.Multipart}) -> Dict{String, Any}

Deserialize a vector of multipart form parts into a name-value dictionary.
Parts with content type `application/x-julia-serialized-object` are deserialized
via `Serialization.deserialize`.
"""
function parse_parts(parts::Vector{HTTP.Multipart})
    Dict(
        p.name => if p.contenttype == "application/x-julia-serialized-object"
            deserialize(p.data)
        else
            read(p.data)  # return raw data for unknown types
        end
        for p in parts
    )
end


function basic_auth_middleware(handler, username::AbstractString, password::AbstractString)
    expected = base64encode("$username:$password")
    return function(req)
        auth = HTTP.header(req, "Authorization", "")
        if startswith(auth, "Basic ") && SubString(auth, 7) == expected
            return handler(req)
        end
        HTTP.Response(401, ["WWW-Authenticate" => "Basic realm=\"ObliviousOffload\""], "Unauthorized")
    end
end

"""
    access_log_middleware(handler)

Log each request in an nginx-like access log format:

    127.0.0.1 - [14/Jul/2026:13:37:00 +0000] "POST /endpoint HTTP/1.1" 200 1234 0.042s
"""
function access_log_middleware(handler)
    return function(req)
        t0 = time()
        response = handler(req)
        duration = time() - t0
        timestamp = Dates.format(Dates.now(), "dd/u/yyyy:HH:MM:SS")
        println("[$timestamp] \"$(req.method) $(req.target) HTTP/$(req.version)\" $(response.status) $(round(duration; digits=3))s")
        return response
    end
end

struct OffloadServer
    server::HTTP.Server
    router::HTTP.Handlers.Router
end



OffloadServer(conn::ConnectParams) = create_server(conn)
OffloadServer() = create_server(ConnectParams())

function create_server(conn::ConnectParams)
    secure_transport.ensure_server(conn)
    router = HTTP.Router()

    handler = if conn.username !== nothing && conn.password !== nothing
        basic_auth_middleware(router, conn.username, conn.password)
    else
        router
    end
    handler = access_log_middleware(handler)

    tls_config = TLS.Config(; cert_file=conn.server_cert_path, key_file=conn.server_privkey_path)
    listener = TLS.listen("tcp", "0.0.0.0:$(conn.port)", tls_config)
    @info "ObliviousOffload server listening on 0.0.0.0:$(conn.port) (TLS), certificate for '$(conn.hostname)'"
    server = HTTP.serve!(handler, listener)
    return OffloadServer(server, router)
end

function Base.:wait(server::OffloadServer)
    wait(server.server)
end

function Base.:close(server::OffloadServer)
    close(server.server)
end


function register_service!(server::OffloadServer, endpoint, function_handler)
    HTTP.register!(server.router, "POST", "/$endpoint") do req
        try
            parts = HTTP.parse_multipart_form(req)
            parts === nothing && return HTTP.Response(415, "expected multipart/form-data")
            fields = parse_parts(parts)

            # Functions registered with the server might be only registered after the server was already started
            result = Base.invokelatest(function_handler, fields["args"]...; fields["kwargs"]...)

            form = HTTP.Form(["result" => make_part(result)])
            body = read(form)
            return HTTP.Response(200, ["Content-Type" => HTTP.content_type(form)]; body)
        catch e
            @error "Error in /$endpoint handler:\n$(sprint(showerror, e, catch_backtrace()))"
            HTTP.Response(500, "Internal server error")
        end
    end
end

function offload(conn::ConnectParams, endpoint::String, args...; kwargs...)
    # For the initial handshake, `require_ssl_verification=false` is required.
    if conn.insecure_tls
        # When require_ssl_verification=false, no custom client can be passed to HTTP.post
        client = nothing
    else
        tls_config = TLS.Config(; ca_file=conn.trusted_ca_path)
        transport = HTTP.Transport(; tls_config)
        client = HTTP.Client(; transport)
    end
    
    form = HTTP.Form([
        "args" => make_part(args),
        "kwargs" => make_part(kwargs),
    ])
    
    response = HTTP.post("$(conn.host)/$endpoint", ["Content-Type" => HTTP.content_type(form)], form;
                         conn.basicauth, client, require_ssl_verification=!conn.insecure_tls)

    ct = HTTP.header(response, "Content-Type")
    resp_parts = HTTP.parse_multipart_form(ct, response.body)
    resp_fields = parse_parts(resp_parts)
    result = resp_fields["result"]

    return result
end

offload(endpoint::String, args...; kwargs...) = run(ConnectParams(), endpoint, args...; kwargs...) 

end # module ObliviousOffload
