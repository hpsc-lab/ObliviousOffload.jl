# RemoteFHE

A minimal Julia project demonstrating a simple OpenFHE client/server flow.

## Overview

- `RemoteFHE` creates an OpenFHE-backed `SecureContext`.
- The client encrypts a vector with a public key and sends the ciphertext to the server.
- The server processes the encrypted payload and sends the encrypted result back.
- The client decrypts the returned ciphertext with its private key.

## Usage

1. Start the server:

```sh
julia --project=RemoteFHE examples/server.jl
```

2. In another terminal, run the client:

```sh
julia --project=RemoteFHE examples/client.jl
```

## Notes

This project uses Julia's `Sockets` and `Serialization` libraries for transport.
The server does not decrypt client data; it operates on encrypted ciphertext and returns an encrypted result.
