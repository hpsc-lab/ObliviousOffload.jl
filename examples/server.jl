using ObliviousOffload
using Logging, LoggingExtras

logger = FormatLogger("server.log"; append=false) do io, args
    println(io, "[$(args.level)] $(args.message)")
end
global_logger(logger)

ObliviousOffload.run_server(
    ;
    username=get(ENV, "REMOTEFHE_USERNAME", nothing),
    password=get(ENV, "REMOTEFHE_PASSWORD", nothing),
)
