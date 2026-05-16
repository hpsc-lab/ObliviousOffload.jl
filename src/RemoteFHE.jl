module RemoteFHE

using Sockets
using OpenFHE
using SecureArithmetic

export create_context, create_keypair, encrypt_vector, run_server, run_client

function create_context(batch_size::Integer = 8)
    parameters = CCParams{CryptoContextCKKSRNS}()
    SetMultiplicativeDepth(parameters, 1)
    SetScalingModSize(parameters, 50)
    SetBatchSize(parameters, batch_size)

    cc = GenCryptoContext(parameters)
    Enable(cc, PKE)
    Enable(cc, KEYSWITCH)
    Enable(cc, LEVELEDSHE)

    SecureContext(OpenFHEBackend(cc))
end

function create_keypair(context)
    generate_keys(context)
end

function encrypt_vector(values::AbstractVector{<:Real}, public_key, context)
    plaintext = PlainVector(collect(values), context)
    encrypt(plaintext, public_key)
end

# Wire helpers: each blob is a little-endian Int64 byte-count followed by raw bytes.
function send_blob(sock::IO, s::AbstractString)
    bytes = Vector{UInt8}(s)
    write(sock, Int64(length(bytes)))
    write(sock, bytes)
end

function recv_blob(sock::IO)::String
    n = read(sock, Int64)
    String(read(sock, n))
end

# Server-side computation on raw OpenFHE objects (doubles each ciphertext).
function process_ciphertexts_raw(cc_raw, cts_raw)
    [OpenFHE.EvalAdd(cc_raw, ct, ct) for ct in cts_raw]
end

function run_server(port::Integer = 25015)
    server = Sockets.listen(port)
    println("RemoteFHE server listening on port $port")

    sock = accept(server)
    try
        println("Client connected")

        # Receive and fully restore crypto context (includes eval keys).
        s_cc     = recv_blob(sock)
        cc_deser = OpenFHE.DeserializeCryptoContextFromString(s_cc)
        cc_raw   = OpenFHE.GetFullContextByDeserializedContext(cc_deser)

        # Public key (received for protocol completeness; not needed for EvalAdd).
        s_pk = recv_blob(sock)

        # Receive ciphertexts.
        n_cts  = read(sock, Int64)
        s_cts  = [recv_blob(sock) for _ in 1:n_cts]
        cts_raw = [OpenFHE.DeserializeCiphertextFromString(s) for s in s_cts]

        println("Received sizes (bytes): cc=", length(s_cc),
                " pk=", length(s_pk),
                " cts=", length.(s_cts))
        println("Received $n_cts ciphertext(s), processing…")

        result_raw = process_ciphertexts_raw(cc_raw, cts_raw)

        write(sock, Int64(length(result_raw)))
        for ct in result_raw
            send_blob(sock, String(OpenFHE.SerializeToString(ct)))
        end
        flush(sock)
        println("Sent $(length(result_raw)) result ciphertext(s)")
    finally
        close(sock)
        close(server)
    end
end

function run_client(host::AbstractString = "127.0.0.1", port::Integer = 25015,
                    values::AbstractVector{<:Real} = [1.0, 2.0, 3.0, 4.0])
    context    = create_context(length(values))
    public_key, private_key = create_keypair(context)
    ciphertext = encrypt_vector(values, public_key, context)
    println("Encrypted values: ", values)

    cc_raw = context.backend.crypto_context
    s_cc   = String(OpenFHE.SerializeToString(cc_raw))
    s_pk   = String(OpenFHE.SerializeToString(public_key.public_key))
    s_cts  = [String(OpenFHE.SerializeToString(ct)) for ct in ciphertext.data]

    sock = connect(host, port)
    try
        send_blob(sock, s_cc)
        send_blob(sock, s_pk)
        write(sock, Int64(length(s_cts)))
        for s in s_cts
            send_blob(sock, s)
        end
        flush(sock)

        n_result    = read(sock, Int64)
        result_raw  = [OpenFHE.DeserializeCiphertextFromString(recv_blob(sock))
                       for _ in 1:n_result]

        result_ct    = SecureArithmetic.SecureArray(result_raw, ciphertext.shape,
                                                    ciphertext.capacity, context)
        result_plain = collect(decrypt(result_ct, private_key))
        println("Decrypted result: ", result_plain)
        return result_plain
    finally
        close(sock)
    end
end

end # module RemoteFHE
