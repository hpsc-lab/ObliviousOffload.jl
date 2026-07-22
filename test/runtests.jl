using Test

@time @testset verbose=true showtiming=true "ObliviousOffload.jl tests" begin
    # We have to run tests in isolated environments so that preferences are loaded for each test independently
    # Compare https://github.com/JuliaLang/julia/blob/7794d01a273a2fdd81b008f47a8dce37377efba1/test/trim.jl#L94 
    # and https://github.com/JuliaPackaging/Preferences.jl/blob/bc31eee839328926282ff32c7dcc34e17172f820/test/runtests.jl#L35
    @testset verbose=true showtiming=true "examples" begin
        @test success(addenv(`$(Base.julia_cmd()) $(joinpath(@__DIR__, "test_handshake.jl"))`))
        @test success(addenv(`$(Base.julia_cmd()) $(joinpath(@__DIR__, "test_simple_array_operations.jl"))`))
    end
end

