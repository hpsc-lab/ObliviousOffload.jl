using ObliviousOffload

# Connection settings (hostname, port, username, password) are read from
# LocalPreferences.toml, section [ObliviousOffload].
result = ObliviousOffload.run_client([0.5, 1.5, 2.5, 3.5])
println("Client finished. Result = ", result)