module ObliviousOffload

using Serialization
using HTTP
using Reseau.TLS
using Base64
using OpenFHE
using SecureArithmetic
using Preferences: @load_preference
include("secure_transport.jl")
using .secure_transport
export run_server, run_client

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


function setup_context(; batch_size::Integer = 8, mult_depth::Integer = 2, scaling_modulus::Integer = 50)
    parameters = CCParams{CryptoContextCKKSRNS}()
    SetMultiplicativeDepth(parameters, mult_depth)
    SetScalingModSize(parameters, scaling_modulus)
    SetBatchSize(parameters, batch_size)

    cc = GenCryptoContext(parameters)
    Enable(cc, PKE)
    Enable(cc, KEYSWITCH)
    Enable(cc, LEVELEDSHE)

    context = SecureContext(OpenFHEBackend(cc))
    public_key, private_key = generate_keys(context)
    init_multiplication!(context, private_key)

    (; context, public_key, private_key, cc)
end

function encrypt_vector(values::AbstractVector{<:Real}, public_key, context)
    plaintext = PlainVector(collect(values), context)
    encrypt(plaintext, public_key)
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

function simple_array_operations(req)
    parts = HTTP.parse_multipart_form(req)
    parts === nothing && return HTTP.Response(415, "expected multipart/form-data")
    fields = parse_parts(parts)
    @info "Deserialized fields from client" names=collect(keys(fields))

    sa1 = fields["sa1"]
    sa2 = fields["sa2"]

    sa_add = sa1 + sa2

    sa_sub = sa1 - sa2

    sa_scalar = sa1 * 4.0

    sa_mult = sa1 * sa2

    sa_shift1 = circshift(sa1, (0, 1, 0))
    sa_shift2 = circshift(sa1, (1, -1, 1))

    sa_after_bootstrap = bootstrap!(sa1)
    @info "Computed results"

    form = HTTP.Form([
        "sa1" => make_part(sa1),
        "sa_add" => make_part(sa_add),
        "sa_sub" => make_part(sa_sub),
        "sa_scalar" => make_part(sa_scalar),
        "sa_mult" => make_part(sa_mult),
        "sa_shift1" => make_part(sa_shift1),
        "sa_shift2" => make_part(sa_shift2),
        "sa_after_bootstrap" => make_part(sa_after_bootstrap),
    ])
    body = read(form)
    @info "Serialized results" length=length(body)
    return HTTP.Response(200, ["Content-Type" => HTTP.content_type(form)]; body)

end

function run_server()
    (; port, hostname, username, password) = load_config()
    secure_transport.ensure_server(hostname)
    router = HTTP.Router()

    HTTP.register!(router, "POST", "/simple_array_operations") do req
        try
            simple_array_operations(req)
        catch e
            @error "Error in /simple_array_operations handler:\n$(sprint(showerror, e, catch_backtrace()))"
            HTTP.Response(500, "Internal server error")
        end
    end

    HTTP.register!(router, "GET", "/handshake") do req
        println("handshake")
        secure_transport.handshake(req, hostname)
    end

    HTTP.register!(router, "POST", "/compute") do req
        try
            parts = HTTP.parse_multipart_form(req)
            parts === nothing && return HTTP.Response(415, "expected multipart/form-data")
            fields = parse_parts(parts)
            @info "Deserialized fields from client" names=collect(keys(fields))

            context = fields["context"]
            public_key = fields["public_key"]
            ciphertext = fields["ciphertext"]

            result = ciphertext + ciphertext
            @info "Computed result"

            form = HTTP.Form(["result" => make_part(result)])
            body = read(form)
            @info "Serialized result" length=length(body)
            return HTTP.Response(200, ["Content-Type" => HTTP.content_type(form)]; body)
        catch e
            @error "Error in /compute handler" exception=(e, catch_backtrace())
            rethrow()
        end
    end

    handler = if username !== nothing && password !== nothing
        basic_auth_middleware(router, username, password)
    else
        router
    end

    tls_config = TLS.Config(; cert_file=secure_transport.server_cert, key_file=secure_transport.server_key)
    listener = TLS.listen("tcp", "0.0.0.0:$port", tls_config)
    @info "ObliviousOffload server listening on 0.0.0.0:$port (TLS), certificate for $hostname"
    server = HTTP.serve!(handler, listener)
    wait(server)
end

function run_client(values::AbstractVector{<:Real})
    (; port, hostname, username, password) = load_config()
    host = "https://$hostname:$port"
    tls_config = TLS.Config(; ca_file=secure_transport.remote_ca_cert)
    transport = HTTP.Transport(; tls_config)
    client = HTTP.Client(; transport)
 
    (; context, public_key, private_key) = setup_context()
    ciphertext = encrypt_vector(values, public_key, context)
    println("Encrypted values: ", values)

    form = HTTP.Form([
        "context" => make_part(context),
        "public_key" => make_part(public_key),
        "ciphertext" => make_part(ciphertext),
    ])
    basicauth = if username !== nothing && password !== nothing
        (username, password)
    else
        nothing
    end
    response = HTTP.post("$host/compute", ["Content-Type" => HTTP.content_type(form)], form;
                         basicauth, client)

    ct = HTTP.header(response, "Content-Type")
    resp_parts = HTTP.parse_multipart_form(ct, response.body)
    resp_fields = parse_parts(resp_parts)
    result_encrypted = resp_fields["result"]

    result_plain = decrypt(result_encrypted, private_key)
    println("Decrypted result: ", result_plain)
    return result_plain
end

function simple_array_operations_remote(context)
    (; port, hostname, username, password) = load_config()
    host = "https://$hostname:$port"
    tls_config = TLS.Config(; ca_file=secure_transport.remote_ca_cert)
    transport = HTTP.Transport(; tls_config)
    client = HTTP.Client(; transport)

    public_key, private_key = generate_keys(context)
    init_multiplication!(context, private_key)
    init_bootstrapping!(context, private_key)
    init_rotation!(context, private_key, (3, 3, 3), (1, -1, 1), (0, 1, 0))
 
    a1 = reshape(Vector(range(1, 27)), (3, 3, 3))
    a2 = reshape(Vector(range(27, 1, step=-1)), (3, 3, 3))

    pa1 = PlainArray(a1, context)
    pa2 = PlainArray(a2, context)

    println("Input array a1: ", pa1)
    println("Input array a2: ", pa2)

    sa1 = encrypt(pa1, public_key)
    sa2 = encrypt(pa2, public_key)


    form = HTTP.Form([
        "context" => make_part(context),
        "public_key" => make_part(public_key),
        "sa1" => make_part(sa1),
        "sa2" => make_part(sa2),
    ])
    basicauth = if username !== nothing && password !== nothing
        (username, password)
    else
        nothing
    end
    response = HTTP.post("$host/simple_array_operations", ["Content-Type" => HTTP.content_type(form)], form;
                         basicauth, client)

    ct = HTTP.header(response, "Content-Type")
    resp_parts = HTTP.parse_multipart_form(ct, response.body)
    resp_fields = parse_parts(resp_parts)
    
    println()
    println("Results of homomorphic computations: ")

    result_sa1 = decrypt(resp_fields["sa1"], private_key)
    println("a1 = ", result_sa1)

    result_sa_add = decrypt(resp_fields["sa_add"], private_key)
    println("a1 + a2 = ", result_sa_add)

    result_sa_sub = decrypt(resp_fields["sa_sub"], private_key)
    println("a1 - a2 = ", result_sa_sub)

    result_sa_scalar = decrypt(resp_fields["sa_scalar"], private_key)
    println("4 * a1 = ", result_sa_scalar)

    result_sa_mult = decrypt(resp_fields["sa_mult"], private_key)
    println("a1 * a2 = ", result_sa_mult)

    result_sa_shift1 = decrypt(resp_fields["sa_shift1"], private_key)
    println("a1 shifted circularly by (0, 1, 0) = ", result_sa_shift1)

    result_sa_shift2 = decrypt(resp_fields["sa_shift2"], private_key)
    println("a1 shifted circularly by (1, -1, 1) = ", result_sa_shift2)

    result_after_bootstrap = decrypt(resp_fields["sa_after_bootstrap"], private_key)
    println("a1 after bootstrapping \n\t", result_after_bootstrap)
    
    # Clean all `OpenFHE.CryptoContext`s and generated keys.
    release_context_memory()
    GC.gc()
end

end # module ObliviousOffload