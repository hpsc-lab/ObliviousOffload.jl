using Test
using OpenFHE
using SecureArithmetic
using RemoteFHE

@testset "Ciphertext serialization round-trip" begin
    values = [1.0, 2.0, 3.0, 4.0]
    context = create_context(length(values))
    public_key, private_key = create_keypair(context)
    ciphertext = encrypt_vector(values, public_key, context)

    # Serialize context, public key, and all ciphertexts in the collection.
    s_cc  = String(OpenFHE.SerializeToString(context.backend.crypto_context))
    s_pk  = String(OpenFHE.SerializeToString(public_key.public_key))
    s_cts = [String(OpenFHE.SerializeToString(ct)) for ct in ciphertext.data]

    println("Serialized sizes (bytes): cc=", length(s_cc),
            " pk=", length(s_pk), " cts=", length.(s_cts))

    @test length(s_cc) > 0
    @test length(s_pk) > 0
    @test all(length(s) > 0 for s in s_cts)

    # Deserialize each object from its binary string.
    new_cc_raw  = OpenFHE.DeserializeCryptoContextFromString(s_cc)
    new_pk_raw  = OpenFHE.DeserializePublicKeyFromString(s_pk)
    new_cts_raw = [OpenFHE.DeserializeCiphertextFromString(s) for s in s_cts]

    println("Deserialized ciphertext types: ", typeof.(new_cts_raw))

    # Rewrap the raw OpenFHE objects into SecureArithmetic types.
    new_ctx = SecureContext(OpenFHEBackend(new_cc_raw))
    new_pk  = SecureArithmetic.PublicKey(new_ctx, new_pk_raw)
    new_ct  = SecureArithmetic.SecureArray(new_cts_raw, ciphertext.shape,
                                           ciphertext.capacity, new_ctx)

    decrypted = collect(decrypt(new_ct, private_key))

    println("Original values:  ", values)
    println("Decrypted values: ", decrypted)

    @test decrypted ≈ values atol=1e-6
end

@testset "Server-side rotation round-trip via serialization" begin
    values = [1.0, 2.0, 3.0, 4.0]
    shift = 1
    context = create_context(length(values))
    public_key, private_key = create_keypair(context)

    # Generate rotation keys (stored globally in the crypto context).
    cc_raw = context.backend.crypto_context
    OpenFHE.EvalRotateKeyGen(cc_raw, private_key.private_key, [shift])

    ciphertext = encrypt_vector(values, public_key, context)

    # Client serializes cc, pk, and all ciphertexts in the collection.
    s_cc  = String(OpenFHE.SerializeToString(cc_raw))
    s_pk  = String(OpenFHE.SerializeToString(public_key.public_key))
    s_cts = [String(OpenFHE.SerializeToString(ct)) for ct in ciphertext.data]

    # Server: deserialize cc, pk, cts; recover full context (with rotation keys);
    # rotate each ciphertext; re-serialize.
    srv_cc_deser = OpenFHE.DeserializeCryptoContextFromString(s_cc)
    srv_cc       = OpenFHE.GetFullContextByDeserializedContext(srv_cc_deser)
    _srv_pk      = OpenFHE.DeserializePublicKeyFromString(s_pk)
    srv_cts      = [OpenFHE.DeserializeCiphertextFromString(s) for s in s_cts]

    rot_cts_raw = [OpenFHE.EvalRotate(srv_cc, ct, shift) for ct in srv_cts]
    s_rot_cts   = [String(OpenFHE.SerializeToString(ct)) for ct in rot_cts_raw]

    println("Serialized rotated ciphertext sizes (bytes): ", length.(s_rot_cts))
    @test all(length(s) > 0 for s in s_rot_cts)

    # Client: deserialize and decrypt the rotated ciphertexts.
    final_cts_raw = [OpenFHE.DeserializeCiphertextFromString(s) for s in s_rot_cts]
    final_ct      = SecureArithmetic.SecureArray(final_cts_raw, ciphertext.shape,
                                                 ciphertext.capacity, context)
    rotated = collect(decrypt(final_ct, private_key))

    expected = circshift(values, -shift)
    println("Original values:    ", values)
    println("Expected (rotated): ", expected)
    println("Decrypted (rotated): ", rotated)

    @test rotated ≈ expected atol=1e-6
end
