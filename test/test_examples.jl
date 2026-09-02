module TestExamples

using Test
using ObliviousOffload

# Using scratch for cert dir during testing
# See https://pkgdocs.julialang.org/v1/creating-packages/#Warning-20f4412fd0c496ad
using Scratch: get_scratch!, delete_scratch!, clear_scratchspaces!

@testset verbose=true showtiming=true "test_examples.jl" begin
clear_scratchspaces!(ObliviousOffload) 
@testset verbose=true showtiming=true "examples/handshake" begin
    certs_dir = get_scratch!(ObliviousOffload, "examples_handshake_dir")
    @test isempty(readdir(certs_dir))

    conn = (
            cert_dir = "$certs_dir",
            trusted_ca_path = "$certs_dir/trusted_ca.pem",
    )

    include("../examples/handshake/server.jl")
    server = run_server(;conn...)

    include("../examples/handshake/client.jl")
    run_client(;conn...)

    close(server)

    @test isfile("$certs_dir/ca-key.pem")
    @test isfile("$certs_dir/ca.pem")
    @test isfile("$certs_dir/ca.srl")
    @test isfile("$certs_dir/privkey.pem")
    @test isfile("$certs_dir/cert.pem")
    @test isfile("$certs_dir/trusted_ca.pem")
    delete_scratch!(ObliviousOffload, "examples_handshake_dir")
end

@testset verbose=true showtiming=true "perform_handshake invalid certificate" begin
    certs_dir = get_scratch!(ObliviousOffload, "examples_handshake_dir")
    @test isempty(readdir(certs_dir))

    conn = ConnectParams(;
            cert_dir = "$certs_dir",
    )
    invalid_cert_data = "123456789"
    @test_throws ErrorException ObliviousOffload.perform_handshake(invalid_cert_data, conn)
end

@testset verbose=true showtiming=true "examples/simple_array_operations" begin
    certs_dir = get_scratch!(ObliviousOffload, "examples_simple_array_operations_certs_dir")
    @test isempty(readdir(certs_dir))
    conn = (
            username = "test",
            password = "test",
            cert_dir = "$certs_dir",
            trusted_ca_path = "$certs_dir/ca.pem", # set locally generated ca.pem as trusted ca, so that no handshake is necessary. Testing handshake separately
    )
    include("../examples/simple_array_operations/server.jl")
    server = run_server(;conn...)
    include("../examples/simple_array_operations/client.jl")
    run_client(;conn...)

    close(server)

    delete_scratch!(ObliviousOffload, "examples_simple_array_operations_certs_dir")
end



end # @testset "test_examples.jl"

end # module
