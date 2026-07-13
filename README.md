> [!WARNING]
> This project is in an early alpha state. It is not recommended to use this package in its current state.

# ObliviousOffload.jl

A minimal Julia project demonstrating a simple OpenFHE client/server flow.

## Overview

This project uses Julia's `Serialization` librariy to pass data SecureArithmetic objects between client and server.
The server does not decrypt client data; it operates on encrypted ciphertext and returns an encrypted result.

- `ObliviousOffload.je` creates an OpenFHE-backed `SecureContext`.
- The client encrypts a vector with a public key and sends the ciphertext to the server.
- The server processes the encrypted payload and sends the encrypted result back.
- The client decrypts the returned ciphertext with its private key.

## Usage

### Configuration
The package can be configured via the `[ObliviousOffload]` section in `LocalPreferences.toml`. 
All variables are optional with defaults for local testing.  
The default is no auth and connecting to localhost as the remote.

| Variable | Description | Default |
|---|---|---|
| port | port name where the server is reachable | 8080 |
| hostname | DNS name where the server is reachable | localhost |
| username | Basic-auth username | nothing |
| password | Basic-auth password | nothing |
||||
|cert_dir | Directory where SSL related files are stored | <WorkingDir>/certs |
|ca_cert_path | Path where the ca certificate is stored | certs/ca.pem |
|ca_key_path | Path where the ca certificate key is stored | certs/ca-key.pem |
|trusted_ca_path | Path where the trusted remote ca certificate is stored | certs/remote-ca.pem |
|server_privkey_path | Path where the server certificate key is stored | certs/privkey.pem |
|server_cert_path | Path where the server certificate is stored | certs/cert.pem |
|san_config_path | Path where the config files for Subject Alternative Names is stored | certs/san.cnf |
|signing_request_path | Path where the server certificate signing request is stored | certs/server.csr |


### TLS setup

It is required that the server has TLS certificate signed by a CA that the client trusts.
For development / POC, we create our own CA and sign a server certificate. 
For this purpose, the "handshake" script and enpoints exist. 
The handshake automatically creates all necessary files, see [](#initial-setup).

### Initial Setup

1. [Server] Clone the project and initialize 
```sh
git clone git@github.com:hpsc-lab/ObliviousOffload.jl.git
cd ObliviousOffload.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```
> [!NOTE]
>  If, for development purposes, local versions of SecureArithmetic and / or OpenFHE should be used, one can add local references with
> ```sh
> julia --project=. -e 'using Pkg; Pkg.develop([PackageSpec(path="/abs/path/to/SecureArithmetic.jl"), PackageSpec(path="/abs/path/to/OpenFHE.jl")])'
> ```
> and can remove them with 
> ```sh
> julia --project=. -e 'using Pkg; Pkg.free(["SecureArithmetic", "OpenFHE.jl"])'
> ```
2. [Client] Clone the project and initialize 
```sh
git clone git@github.com:hpsc-lab/ObliviousOffload.jl.git
cd ObliviousOffload.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```
3. [Server] Start the server:
```sh
julia --project=ObliviousOffload examples/server.jl
```
The server automatically checks for existing CA and Server certificate and creates them if necessary

4. [Client] Run the handshake script 
```sh
julia --project=ObliviousOffload examples/handshake.jl
```
The Handshake script connects to the server and downloads its CA.pem. 
Since it cannot yet trust the server on that first connection, both the server and the handshake script display the CA.pem fingerprint.
The server logs the Fingerprint in `server.log`.
The user running the handshake script **must** manually verify that the fingerprints match and then accept the CA.pem by typing "y".

5. [Client] Run any client scripts
A trusted client-server connection is now established. 
Now, any client side scripts can connect to the server to offload data processing. 
For example, run 
```sh
julia --project=ObliviousOffload examples/client.jl
```

## Notes


## Authors
ObliviousOffload.jl was initiated by [Tom Finke](https://github.com/Tom-Finke/) while working for Michael Schlottke-Lakemper at the HPSC Lab of the University of Augsburg, Germany (https://hpsc.math.uni-augsburg.de).


## License and contributing
ObliviousOffload.jl is available under the MIT license (see [LICENSE.md](LICENSE.md)).
Contributions by the community are very welcome! For larger proposed changes, feel free
to reach out via an issue first.

