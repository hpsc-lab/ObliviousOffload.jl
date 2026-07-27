module ObliviousOffload

using Serialization
using Dates
using HTTP
using Reseau.TLS
using Base64
using Preferences: @load_preference
include("secure_transport.jl")
using .secure_transport

"""
    load_config() -> NamedTuple

Load the connection configuration from `LocalPreferences.toml` (section
`[ObliviousOffload]`). Recognized keys: `port`, `hostname`, `username`,
`password`. Missing keys fall back to defaults; `username` and `password`
default to `nothing`, which disables basic auth.

`hostname` is the server's public name: it is placed in the TLS
certificate's SAN and used by clients as the address to connect to. The
server itself always listens on all interfaces (`0.0.0.0`).
"""
function load_config()
    (
        port = @load_preference("port", 8080),
        hostname = @load_preference("hostname", "localhost"),
        username = @load_preference("username", nothing),
        password = @load_preference("password", nothing),
    )
end


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


function basic_auth_middleware(handler, username::AbstractString, password::AbstractString; exempt_paths=("/handshake",))
    expected = base64encode("$username:$password")
    return function(req)        
        if HTTP.URI(req.target).path in exempt_paths
            return handler(req)
        end
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

function create_server()
    (; port, hostname, username, password) = load_config()
    secure_transport.ensure_server()
    router = HTTP.Router()

    handler = if username !== nothing && password !== nothing
        basic_auth_middleware(router, username, password)
    else
        router
    end
    handler = access_log_middleware(handler)

    tls_config = TLS.Config(; cert_file=secure_transport.server_cert, key_file=secure_transport.server_key)
    listener = TLS.listen("tcp", "0.0.0.0:$port", tls_config)
    @info "ObliviousOffload server listening on 0.0.0.0:$port (TLS), certificate for '$hostname'"
    server = HTTP.serve!(handler, listener)
    return server, router
end

function register(router, endpoint, function_handler)
    HTTP.register!(router, "POST", "/$endpoint") do req
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

function run(endpoint, args...; kwargs...)
    (; port, hostname, username, password) = load_config()
    host = "https://$hostname:$port"

    # For the initial handshake, `require_ssl_verification=false` is required.
    # We don't pass it as a regular argument, because it could potentially interfere with the arguments of the function being called
    insecure_tls = get(task_local_storage(), :insecure_tls, false)
    if insecure_tls
        # When require_ssl_verification=false, no custom client can be passed to HTTP.post
        client = nothing
    else
        tls_config = TLS.Config(; ca_file=secure_transport.remote_ca_cert)
        transport = HTTP.Transport(; tls_config)
        client = HTTP.Client(; transport)
    end
    
    form = HTTP.Form([
        "args" => make_part(args),
        "kwargs" => make_part(kwargs),
    ])
    basicauth = if username !== nothing && password !== nothing
        (username, password)
    else
        nothing
    end
    response = HTTP.post("$host/$endpoint", ["Content-Type" => HTTP.content_type(form)], form;
                         basicauth, client, require_ssl_verification=!insecure_tls)

    ct = HTTP.header(response, "Content-Type")
    resp_parts = HTTP.parse_multipart_form(ct, response.body)
    resp_fields = parse_parts(resp_parts)
    result = resp_fields["result"]

    return result
end

end # module ObliviousOffload