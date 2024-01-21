# L4pingConfig Guidelines
Any optional variables will be omitted
```
    "L4ping**ConfigName**": { # Name of config must start with L4ping
        "Iterations"     : **Int: Number of command iterations**,
        "Protocol"       : **Array: List of Protocols - tcp | udp | raw**,
        "StartPort"      : **Int: Starting Server Port Number**,
        "Time"           : **Int: Test Duration**, # set to 0 to omit
        "PingIterations" : **Int: Ping Iteration**, # set to 0 to omit
        "SendMethod"     : **Array: List of Send methods Options - b | nb | ove | ovc | ovp | sel **,
        "Default"        : **String: Send options for default commands**, # Optional
        "Optimized"      : **String: Send Command options for optimized commands**, # Optional
        "Options"        : **String: Additional options for sender commands**
    }
```