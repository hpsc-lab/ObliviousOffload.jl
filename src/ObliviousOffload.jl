module ObliviousOffload

using Serialization
using Dates
using HTTP
using Reseau.TLS
using Base64
using Preferences: @load_preference
export OffloadServer, ConnectParams, register_service!, offload

"""
    ConnectParams(; port, hostname, username, password,
                   cert_dir, ca_cert_path, ca_key_path, trusted_ca_path,
                   server_privkey_path, server_cert_path, san_config_path,
                   signing_request_path, insecure_tls=false) -> ConnectParams

Configuration parameters for connecting to or running an ObliviousOffload server.

# Fields

- `port::Union{Int, String}`: Server port
- `hostname::String`: Server hostname
- `username::String`: Username for basic authentication
- `password::String`: Password for basic authentication
- `cert_dir::String`: Directory for certificate files
- `ca_cert_path::String`: Path to the CA certificate
- `ca_key_path::String`: Path to the CA private key
- `trusted_ca_path::String`: Path to the remote CA certificate for client verification
- `server_privkey_path::String`: Path to the server's private key
- `server_cert_path::String`: Path to the server's certificate
- `san_config_path::String`: Path to the Subject Alternative Names configuration file
- `signing_request_path::String`: Path to the certificate signing request
- `insecure_tls::Bool`: If true, disables TLS verification (default: false)

# Computed Properties

- `host::String`: Computed as "https://hostname:port"
- `basicauth`: Tuple of (username, password) if both are provided, otherwise nothing

# Notes

- All paths are loaded from preferences if available, allowing project-wide configuration
- When `insecure_tls=true`, username and password are automatically reset to `nothing`
- Basic authentication is automatically disabled if either username or password is `nothing`
"""
struct ConnectParams
    port::Union{Int, String}
    hostname::String
    username::String
    password::String
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

        username = username || ""
        password = password || ""

        # Reset auth credentials when using insecure TLS (e.g., during handshake)
        if insecure_tls && (username !== "" || password !== "")
            @warn "Authentication cannot be used with insecure TLS. Username and password have been reset."
            username = ""
            password = ""
        end

        basicauth = if username !== "" && password !== ""
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

"""
    OffloadServer(conn::ConnectParams) -> OffloadServer
    OffloadServer() -> OffloadServer

Creates a TLS-secured HTTP server that listens for incoming function calls. Services are
registered with [`register_service!`](@ref) and called remotely via [`offload`](@ref).

# Fields

- `server::HTTP.Server`: The underlying HTTP server instance
- `router::HTTP.Handlers.Router`: The HTTP router for dispatching requests to registered services

# Examples

```julia
server = OffloadServer()
register_service!(server, "myfunc", (x, y) -> x + y)
wait(server)
```
"""
struct OffloadServer
    server::HTTP.Server
    router::HTTP.Handlers.Router
end



OffloadServer(conn::ConnectParams) = create_server(conn)
OffloadServer() = create_server(ConnectParams())

function create_server(conn::ConnectParams)
    secure_transport.ensure_server(conn)
    router = HTTP.Router()

    handler = if conn.username !== "" && conn.password != ""
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


"""
    register_service!(server::OffloadServer, endpoint, function_handler)

Register a function as a remotely callable service on the server.

The function is exposed as a POST endpoint at `/<endpoint>`. When called via [`offload`](@ref),
positional and keyword arguments are serialized, sent as multipart form data, and passed to
`function_handler`. The return value is serialized back to the caller.

# Arguments

- `server::OffloadServer`: The server to register the service on
- `endpoint`: The URL path segment for this service (e.g., `"myfunc"` becomes `/myfunc`)
- `function_handler`: A callable that accepts the offloaded arguments and keyword arguments

# Examples

```julia
server = OffloadServer()
register_service!(server, "add", (x, y) -> x + y)
function greet(name; greeting="Hello")
    return "\$(greeting), \$(name)!"
end
register_service!(server, "greet", greet)
```
"""
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

"""
    offload(conn::ConnectParams, endpoint::String, args...; kwargs...)
    offload(endpoint::String, args...; kwargs...)

Call a remote service registered on an ObliviousOffload server.

Serializes `args` and `kwargs`, sends them as multipart form data to the server's `/<endpoint>`,
and deserializes the result. Communication is secured via TLS using the certificates configured
in `conn`.

# Arguments

- `conn::ConnectParams`: Connection parameters (omit to use defaults)
- `endpoint::String`: The service endpoint to call
- `args...`: Positional arguments passed to the remote function
- `kwargs...`: Keyword arguments passed to the remote function

# Returns

The deserialized return value of the remote function.

# Examples

```julia
offload("add", 2, 3)  # returns 5
offload("greet", "Alice")  # returns "Hello, Alice!"
offload("greet", "Bob", greeting="Howdy")  # returns "Howdy, Bob!"
```
"""
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

offload(endpoint::String, args...; kwargs...) = offload(ConnectParams(), endpoint, args...; kwargs...) 

end # module ObliviousOffload
