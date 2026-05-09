module RemoteFHE

using Sockets
using Serialization
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

function process_ciphertext(ciphertext)
    ciphertext + ciphertext
end

function send_object(sock::Sockets.TCPSocket, obj)
    serialize(sock, obj)
    flush(sock)
end

function receive_object(sock::Sockets.TCPSocket)
    deserialize(sock)
end

function run_server(port::Integer = 25015)
    server = Sockets.listen(port)
    println("RemoteFHE server listening on port $port")

    client_sock = accept(server)
    try
        println("Client connected")
        ciphertext = receive_object(client_sock)
        println("Received ciphertext of type ", typeof(ciphertext))

        result = process_ciphertext(ciphertext)
        send_object(client_sock, result)
        println("Processed ciphertext and returned encrypted result")
    finally
        close(client_sock)
        close(server)
    end
end

function run_client(host::AbstractString = "127.0.0.1", port::Integer = 25015,
                    values::AbstractVector{<:Real} = [1.0, 2.0, 3.0, 4.0])
    context = create_context(length(values))
    public_key, private_key = create_keypair(context)

    ciphertext = encrypt_vector(values, public_key, context)
    println("Encrypted values: ", values)

    sock = connect(host, port)
    try
        send_object(sock, ciphertext)
        result_ciphertext = receive_object(sock)
        println("Received encrypted result from server")

        result_plain = decrypt(result_ciphertext, private_key)
        println("Decrypted result: ", collect(result_plain))
        return collect(result_plain)
    finally
        close(sock)
    end
end

end # module RemoteFHE