using RemoteFHE

result = RemoteFHE.run_client(
    [0.5, 1.5, 2.5, 3.5], "https://127.0.0.1:8080";
    username=get(ENV, "REMOTEFHE_USERNAME", nothing),
    password=get(ENV, "REMOTEFHE_PASSWORD", nothing),
    ca_file = get(ENV, "REMOTEFHE_CA_FILE", nothing),
)
println("Client finished. Result = ", result)