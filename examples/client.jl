using ObliviousOffload

hostname=get(ENV, "HOSTNAME", localhost)
result = ObliviousOffload.run_client(
    [0.5, 1.5, 2.5, 3.5], "https://$hostname:8080";
    username=get(ENV, "USERNAME", nothing),
    password=get(ENV, "PASSWORD", nothing),
    ca_file = get(ENV, "CA_FILE", nothing),
)
println("Client finished. Result = ", result)