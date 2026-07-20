module TestExamples

using Test
using Preferences


@testset verbose=true showtiming=true "test_examples.jl" begin

@testset verbose=true showtiming=true "examples/simple_array_operations" begin
    rm("test_certs"; force=true, recursive=true)
    Preferences.set_preferences!(
        "ObliviousOffload", 
        (
            "port" => "8000", 
            "hostname" => "localhost",
            "username" => "test",
            "password" => "test",
            "cert_dir" => "test_certs",
            "trusted_ca_path" => "test_certs/ca.pem", # set locally generated ca.pem as trusted ca, so that no handshake is necessary. Testing handshake separately  
        )...
        ; force=true
    )

    include("../examples/simple_array_operations/server.jl")
    include("../examples/simple_array_operations/client.jl")
    rm("test_certs"; recursive=true)
end

end # @testset "test_examples.jl"

end # module
