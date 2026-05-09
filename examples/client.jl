using RemoteFHE

result = RemoteFHE.run_client("127.0.0.1", 25015, [0.5, 1.5, 2.5, 3.5])
println("Client finished. Result = ", result)