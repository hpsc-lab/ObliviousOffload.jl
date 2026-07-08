using ObliviousOffload

result = ObliviousOffload.run_client(
    [0.5, 1.5, 2.5, 3.5], "https://127.0.0.1:8080";
    username=get(ENV, "USERNAME", nothing),
    password=get(ENV, "PASSWORD", nothing),
    ca_file = get(ENV, "CA_FILE", nothing),
)
println("Client finished. Result = ", result)