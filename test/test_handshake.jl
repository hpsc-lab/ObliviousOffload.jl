module TestHandshake

using Test
using Preferences
using Sockets

certs_dir = "handshake_test_certs"
port = 8000
Preferences.set_preferences!(
    "ObliviousOffload",
    (
        "port" => "$port",
        "hostname" => "localhost",
        "username" => "test",
        "password" => "test",
        "cert_dir" => "$certs_dir",
        "trusted_ca_path" => "$certs_dir/trusted_ca.pem",
    )...
    ; force=true
)


@testset verbose=true showtiming=true "examples/handshake" begin
    certs_dir="handshake_test_certs"
    @test ~isdir(certs_dir) # fails if certs dir already exists

    include("../examples/handshake/server.jl")

    include("../examples/handshake/client.jl")

    close(server)

    @test isfile("$certs_dir/ca-key.pem")
    @test isfile("$certs_dir/ca.pem")
    @test isfile("$certs_dir/ca.srl")
    @test isfile("$certs_dir/privkey.pem")
    @test isfile("$certs_dir/cert.pem")
    @test isfile("$certs_dir/trusted_ca.pem")
    rm(certs_dir; recursive=true)
end

end # module
