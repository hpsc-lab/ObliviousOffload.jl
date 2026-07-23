module TestSimpleArrayOperations

using Test
using Preferences
using Sockets

certs_dir="array_op_test_certs"
port = 8000
Preferences.set_preferences!(
    "ObliviousOffload", 
    (
        "port" => "$port", 
        "hostname" => "localhost",
        "username" => "test",
        "password" => "test",
        "cert_dir" => "$certs_dir",
        "trusted_ca_path" => "$certs_dir/ca.pem", # set locally generated ca.pem as trusted ca, so that no handshake is necessary. Testing handshake separately  
    )...
    ; force=true
)


@testset verbose=true showtiming=true "examples/simple_array_operations" begin
    @test ~isdir(certs_dir) # fails if certs dir already exists
    
    include("../examples/simple_array_operations/server.jl")

    include("../examples/simple_array_operations/client.jl")

    close(server)
    rm(certs_dir; recursive=true)
end

end # module
