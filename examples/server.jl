using ObliviousOffload
using Logging, LoggingExtras

logger = FormatLogger("server.log"; append=false) do io, args
    println(io, "[$(args.level)] $(args.message)")
end
global_logger(logger)

# Connection settings (port, hostname, username, password) are read from
# LocalPreferences.toml, section [ObliviousOffload].
ObliviousOffload.run_server()
