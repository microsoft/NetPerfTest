# Ntttcp Config Guidelines
Any optional variables will be omitted
```
"Ntttcp**NameOfConfig**": { # Name of config must start with Ntttcp
    "Iterations"  : **Int: Number of command iterations**,
    "StartPort"   : **Int: Starting Destination Port Number**,
    "tcp" : { # Optional
        "BufferLen"     : **Array: List of buffer size for tcp in n[KMG] Bytes**,
        "Connections"   : **Array: List of number of receiver ports for tcp**,
        "OutstandingIo" : **Array: List of Oustanding I/O**, # Optional
        "Options"       : **String: Additional options for tcp commands e.g. --show-tcp-retrans** # Optional
    },
    "udp" : { # Optional
        "BufferLen"     : **Array: List of buffer length for udp**,
        "Connections"   : **Array: List of number of receiver ports for udp**,
        "OutstandingIo" : **Array: List of Oustanding I/O**, # Optional
        "Options"       : **String: Additional options for udp commands** # Optional
    },
    "Warmup"      : **Int: Warm-up time in seconds**,
    "Cooldown"    : **Int: Cooldown time in seconds**,
    "Runtime"     : **Int: Time of Test Duration in seconds**
}
```