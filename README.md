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

### Environment variables
The example scripts can be configured with environment variables to enable basic auth and TLS. 
All variables are optional.  
The default is no auth and communication over plain http.

| Variable | Description |
|---|---|
| `REMOTEFHE_USERNAME` | Basic-auth username |
| `REMOTEFHE_PASSWORD` | Basic-auth password |

### TLS setup

It is required that the server has TLS certificate signed by a CA that the client trusts.
For development / POC, we create our own CA and sign a server certificate. 
For this purpose, the "handshake" script and enpoints exist. 
The handshake automatically creates all necessary files, see [](#initial-setup).

### Initial Setup

1. [Server] Clone the project
```sh
git clone git@github.com:hpsc-lab/ObliviousOffload.jl.git
```
2. [Client] Clone the project
```sh
git clone git@github.com:hpsc-lab/ObliviousOffload.jl.git
```
3. [Server] Start the server:
```sh
export REMOTEFHE_USERNAME=user REMOTEFHE_PASSWORD=pass
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
export REMOTEFHE_USERNAME=user REMOTEFHE_PASSWORD=pass
julia --project=ObliviousOffload examples/client.jl
```

## Notes


## Authors
ObliviousOffload.jl was initiated by [Tom Finke](https://github.com/Tom-Finke/) while working for Michael Schlottke-Lakemper at the HPSC Lab of the University of Augsburg, Germany (https://hpsc.math.uni-augsburg.de).


## License and contributing
ObliviousOffload.jl is available under the MIT license (see [LICENSE.md](LICENSE.md)).
Contributions by the community are very welcome! For larger proposed changes, feel free
to reach out via an issue first.

