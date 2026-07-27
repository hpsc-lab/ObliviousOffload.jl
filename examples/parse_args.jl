using ArgParse

function parse_commandline()
    s = ArgParseSettings()
    @add_arg_table! s begin        
        "--port"
            help = "Port where the server is reachable (default: 8080)"
            arg_type = Int
        "--hostname"
            help = "DNS name where the server is reachable (default: 'localhost')"
            arg_type = String
        "--username"
            help = "Basic-auth username (default: nothing)"
            arg_type = String
        "--password"
            help = "Basic-auth password (default: nothing)"
            arg_type = String
        "--cert_dir"
            help = "Directory where SSL related files are stored (default: <WorkingDir>/certs) |"
            arg_type = String
        "--ca_cert_path"
            help = "Path where the ca certificate is stored (default: <CertDir>/ca.pem) |"
            arg_type = String
        "--ca_key_path"
            help = "Path where the ca certificate key is stored (default: <CertDir>/ca-key.pem.pem)"
            arg_type = String
        "--trusted_ca_path"
            help = "Path where the trusted remote ca certificate is stored (default: <CertDir>/remote-ca.pem)"
            arg_type = String
        "--server_privkey_path"
            help = "Path where the server certificate key is stored (default: <CertDir>/privkey.pem)"
            arg_type = String
        "--server_cert_path"
            help = "Path where the server certificate is stored (default: <CertDir>/cert.pem)"
            arg_type = String
        "--san_config_path"
            help = "Path where the config file for Subject Alternative Names is stored (default: <CertDir>/san.cnf)"
            arg_type = String
        "--signing_request_path"
            help = "Path where the server certificate signing request is stored (default: <CertDir>/server.csr)"
            arg_type = String
    end
    return NamedTuple(Symbol(k) => v for (k, v) in ArgParse.parse_args(s) if v !== nothing)
end