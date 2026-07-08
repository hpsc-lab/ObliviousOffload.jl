using ObliviousOffload

# No SSL verification, no auth
# No verification because the purpose of this handshake is to get the CA.pem needed to verify the SSL certificate
# No auth because we don't send a password over unverified connections
ca = ObliviousOffload.secure_transport.fetch_ca("https://127.0.0.1:8080")

# From here on, use the trusted CA for verified requests, e.g.:
# HTTP.get("https://127.0.0.1:8080/..."; sslconfig=MbedTLS.SSLConfig(true, cacert=ca))