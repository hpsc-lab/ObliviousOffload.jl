using ObliviousOffload
using SecureArithmetic



function simple_array_operations(sa1, sa2)
    sa_add = sa1 + sa2

    sa_sub = sa1 - sa2

    sa_scalar = sa1 * 4.0

    sa_mult = sa1 * sa2

    sa_shift1 = circshift(sa1, (0, 1, 0))
    sa_shift2 = circshift(sa1, (1, -1, 1))

    sa_after_bootstrap = bootstrap!(sa1)

    return (; sa1, sa_add, sa_sub, sa_scalar, sa_mult, sa_shift1, sa_shift2, sa_after_bootstrap)

end


# Connection settings (port, hostname, username, password) are read from
# LocalPreferences.toml, section [ObliviousOffload].
server, router = ObliviousOffload.create_server()

ObliviousOffload.register(router, "simple_array_operations", simple_array_operations)

# Block only when executed as a script (`julia server.jl`), not when included
# This is required by the test suite, which starts the server in-process and closes it itself.
if abspath(PROGRAM_FILE) == @__FILE__
    wait(server)
end