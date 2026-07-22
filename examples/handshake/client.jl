using ObliviousOffload
ca_binary = task_local_storage(:insecure_tls, true) do
    ObliviousOffload.run("handshake")
end

pem = tempname()
write(pem, ca_binary)
fp = try
    ObliviousOffload.secure_transport.fingerprint(pem)
catch
    rm(pem, force=true)
    error("response body is not a valid PEM certificate")
end

@info "Received CA certificate, fingerprint: $fp"

mkpath(ObliviousOffload.secure_transport.CERT_DIR)
mv(pem, ObliviousOffload.secure_transport.remote_ca_cert, force=true)

@info "CA certificate automatically trusted and saved. You must manually check that the fingerprint is correct." path = ObliviousOffload.secure_transport.remote_ca_cert
