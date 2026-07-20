using Documenter

# Get ObliviousOffload.jl root directory
obliviousoffload_root_dir = dirname(@__DIR__)

# Fix for https://github.com/trixi-framework/Trixi.jl/issues/668
if (get(ENV, "CI", nothing) != "true") && (get(ENV, "OBLIVIOUSOFFLOAD_DOC_DEFAULT_ENVIRONMENT", nothing) != "true")
    push!(LOAD_PATH, obliviousoffload_root_dir)
end

using ObliviousOffload 

# Define module-wide setups such that the respective modules are available in doctests
DocMeta.setdocmeta!(ObliviousOffload, :DocTestSetup, :(using ObliviousOffload); recursive=true)

# Copy some files from the top level directory to the docs and modify them
# as necessary
open(joinpath(@__DIR__, "src", "index.md"), "w") do io
    # Point to source file
    println(io, """
    ```@meta
    EditURL = "https://github.com/hpsc-lab/ObliviousOffload.jl/blob/main/README.md"
    ```
    """)
    # Write the modified contents
    for line in eachline(joinpath(obliviousoffload_root_dir, "README.md"))
        line = replace(line, "[LICENSE.md](LICENSE.md)" => "[License](@ref)")
        println(io, line)
    end
end

open(joinpath(@__DIR__, "src", "license.md"), "w") do io
    # Point to source file
    println(io, """
    ```@meta
    EditURL = "https://github.com/hpsc-lab/ObliviousOffload.jl/blob/main/LICENSE.md"
    ```
    """)
    # Write the modified contents
    println(io, "# License")
    println(io, "")
    for line in eachline(joinpath(obliviousoffload_root_dir, "LICENSE.md"))
        println(io, "> ", line)
    end
end

# Make documentation
makedocs(
    # Specify modules for which docstrings should be shown
    modules = [ObliviousOffload],
    # Set sitename to Trixi.jl
    sitename="ObliviousOffload.jl",
    # Provide additional formatting options
    format = Documenter.HTML(
        # Disable pretty URLs during manual testing
        prettyurls = get(ENV, "CI", nothing) == "true",
        # Set canonical URL to GitHub pages URL
        canonical = "https://hpsc-lab.github.io/ObliviousOffload.jl/stable"
    ),
    # Explicitly specify documentation structure
    pages = [
        "Home" => "index.md",
        "API reference" => "reference.md",
        "License" => "license.md"
    ],
)


if get(ENV, "GITHUB_ACTOR", "") != "dependabot[bot]"
    deploydocs(;
        repo = "github.com/hpsc-lab/ObliviousOffload.jl",
        devbranch = "main",
        push_preview = true
    )
end
