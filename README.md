# ObliviousOffload.jl
[![Docs-stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://hpsc-lab.github.io/ObliviousOffload.jl/stable)
[![Docs-dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://hpsc-lab.github.io/ObliviousOffload.jl/dev)
[![Build Status](https://github.com/hpsc-lab/ObliviousOffload.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/hpsc-lab/ObliviousOffload.jl/actions?query=workflow%3ACI)
[![Coveralls](https://coveralls.io/repos/github/hpsc-lab/ObliviousOffload.jl/badge.svg?branch=main)](https://coveralls.io/github/hpsc-lab/ObliviousOffload.jl?branch=main)
[![Codecov](https://codecov.io/gh/hpsc-lab/ObliviousOffload.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/hpsc-lab/ObliviousOffload.jl)
[![License: MIT](https://img.shields.io/badge/License-MIT-success.svg)](https://opensource.org/license/mit/)
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.21699027.svg)](https://doi.org/10.5281/zenodo.21699027)

A minimal Julia project demonstrating a simple OpenFHE client/server flow.

## Overview

This project demonstrates how OpenFHE objects can be sent over HTTP using Julia's `Serialization` library 
to pass SecureArithmetic objects between a client and server for remote secure calculation.
The idea is that the server does not decrypt client data; it operates on encrypted ciphertext and returns encrypted results.
But this package is agnostic as to what functions get registered as endpoints with the webserver, 
it does not depend on SecureArithmetic / OpenFHE objects, although that is its intended purpose.

Outline:
- A client script creates an OpenFHE-backed `SecureContext`.
- A server script registers some function as a web endpoint using `ObliviousOffload.jl` 
- The client encrypts data with a public key and sends the ciphertext to the server.
- The server processes the encrypted payload and sends the encrypted result back.
- The client decrypts the returned ciphertext with its private key.

## Usage

### Configuration
The package can be configured via the `[ObliviousOffload]` section in `LocalPreferences.toml`. 
All variables are optional with defaults for local testing.  
The default is no auth and connecting to localhost as the remote.

A complete LocalPreferences entry could look like this:
```toml
[ObliviousOffload]
# Port where the server is reachable
port = 8080

# DNS name/IP address where the server is reachable
hostname = "localhost"

# Basic-auth username
username = ""

# Basic-auth password
password = ""

# Directory where SSL related files are stored
cert_dir = "certs/"

# Path where the CA certificate is stored
ca_cert_path = "certs/ca.pem"

# Path where the CA certificate key is stored
ca_key_path = "certs/ca-key.pem"

# Path where the trusted remote CA certificate is stored
trusted_ca_path = "certs/remote-ca.pem"

# Path where the server certificate key is stored
server_privkey_path = "certs/privkey.pem"

# Path where the server certificate is stored
server_cert_path = "certs/cert.pem"

# Path where the config files for Subject Alternative Names is stored
san_config_path = "certs/san.cnf"

# Path where the server certificate signing request is stored
signing_request_path = "certs/server.csr"
```

### TLS setup

It is required that the server has a TLS certificate signed by a CA that the client trusts.
For development / POC, we create our own CA and sign a server certificate. 
For this purpose, the "handshake" server and client example scripts exist. 
The handshake automatically creates all necessary files.

### Running Examples

The Package provides example scripts for showcasing basic functionality. 

1. [Server] Clone the project and initialize 
```sh
git clone git@github.com:hpsc-lab/ObliviousOffload.jl.git
cd ObliviousOffload.jl/examples
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```
> [!NOTE]
>  If, for development purposes, local versions of SecureArithmetic and / or OpenFHE should be used, one can add local references with
> ```sh
> julia --project=. -e 'using Pkg; Pkg.develop([PackageSpec(path="/abs/path/to/SecureArithmetic.jl"), PackageSpec(path="/abs/path/to/OpenFHE.jl")])'
> ```
> and can remove them with 
> ```sh
> julia --project=. -e 'using Pkg; Pkg.free(["SecureArithmetic", "OpenFHE"])'
> ```
2. [Client] Clone the project and initialize 
```sh
git clone git@github.com:hpsc-lab/ObliviousOffload.jl.git
cd ObliviousOffload.jl/examples
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```
3. [Server] Start the server:
```sh
julia --project=. handshake/server.jl
```
The server automatically checks for existing CA and Server certificate and creates them if necessary.

4. [Client] Run the handshake script 
```sh
julia --project=. handshake/client.jl
```
The Handshake script connects to the server and downloads its CA.pem. 
Since it cannot yet trust the server on that first connection, both the server and the handshake script display the CA.pem fingerprint.
The user running the handshake script **must** manually verify that the fingerprints match.

5. [Client] Run any client scripts
A trusted client-server connection is now established. 
Now, any client side scripts can connect to the server to offload data processing. 
For example, run 
```sh
julia --project=. simple_array_operations/server.jl
```
and
```sh
julia --project=. simple_array_operations/client.jl
```

## Authors
ObliviousOffload.jl was initiated by [Tom Finke](https://github.com/Tom-Finke/) while working for Michael Schlottke-Lakemper at the HPSC Lab of the University of Augsburg, Germany (https://hpsc.math.uni-augsburg.de).


## License and contributing
ObliviousOffload.jl is available under the MIT license (see [LICENSE.md](LICENSE.md)).
Contributions by the community are very welcome! For larger proposed changes, feel free
to reach out via an issue first.

