using ObliviousOffload

ObliviousOffload.secure_transport.ensure_server(get(ENV, "HOSTNAME", "localhost"))
print(ObliviousOffload.secure_transport.ca_fingerprint())