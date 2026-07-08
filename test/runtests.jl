using Test
using HTTP
using OpenFHE
using SecureArithmetic
using ObliviousOffload

@testset verbose=true showtiming=true "ObliviousOffload" begin

@testset "Multipart serialization round-trip" begin
    values = [1.0, 2.0, 3.0, 4.0]
    cli = ObliviousOffload.setup_context()
    ciphertext = ObliviousOffload.encrypt_vector(values, cli.public_key, cli.context)

    form = HTTP.Form([
        "context" => ObliviousOffload.make_part(cli.context),
        "public_key" => ObliviousOffload.make_part(cli.public_key),
        "ciphertext" => ObliviousOffload.make_part(ciphertext),
    ])

    content_type = HTTP.content_type(form)
    @test startswith(content_type, "multipart/form-data")
    parts = HTTP.parse_multipart_form(content_type, read(form))
    fields = ObliviousOffload.parse_parts(parts)

    @test fields["ciphertext"] isa SecureArray
    decrypted = decrypt(fields["ciphertext"], cli.private_key)
    @test collect(decrypted) ≈ values
end


@testset "Server-side modification" begin
    values = [1.0, 2.0, 3.0, 4.0]
    values_2 = [1, 1.0, 2, 2.0]
    cli = ObliviousOffload.setup_context()
    ciphertext = ObliviousOffload.encrypt_vector(values, cli.public_key, cli.context)

    form = HTTP.Form([
        "context" => ObliviousOffload.make_part(cli.context),
        "public_key" => ObliviousOffload.make_part(cli.public_key),
        "ciphertext" => ObliviousOffload.make_part(ciphertext),
        "string" => "A raw string",
    ])
    body = read(form)
    content_type = HTTP.content_type(form)
    parts = HTTP.parse_multipart_form(content_type, body)
    fields = ObliviousOffload.parse_parts(parts)

    ciphertext_2 = ObliviousOffload.encrypt_vector(values_2, fields["public_key"], fields["context"])

    result = fields["ciphertext"] + ciphertext_2

    decrypted = decrypt(result, cli.private_key)
    @test collect(decrypted) ≈ [2, 3, 5, 6]
end

end # @testset "ObliviousOffload"
