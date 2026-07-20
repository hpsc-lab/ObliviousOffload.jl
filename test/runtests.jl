using Test

@time @testset verbose=true showtiming=true "ObliviousOffload.jl tests" begin
    include("test_examples.jl")
end

