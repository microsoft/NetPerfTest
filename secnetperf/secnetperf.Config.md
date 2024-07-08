# Ntttcp Config Guidelines
Any optional variables will be omitted
```
"Secnetperf**NameOfConfig**": { # Name of config must start with Secnetperf
    "Iterations"  : **Int: Number of command iterations**,
    "StartPort"   : **Int: Starting Destination Port Number**,
    "TestType"    : {
        "Latency" : {
            "tcp": {
                "Runtime"     : **Int: Time of Test Duration in seconds**,
                "Requests"     : **Int: Number of requests**,
                "ByteSize" : **Int: Number of bytes send**,
                "Options"      : **String: Additional options for commands** # Optional
            },
            "quic": {
                "Runtime"     : **Int: Time of Test Duration in seconds**,
                "Requests"     : **Int: Number of requests**,
                "ByteSize" : **Int: Number of bytes send**,
                "Options"       : **String: Additional options for commands** # Optional
            }

        },
        "Handshakes" : {
            "tcp": {
                "Runtime"     : **Int: Time of Test Duration in seconds**,
                "Connections"   : **Array: List of number of receiver ports for tcp**,
                "Options"       : **String: Additional options for commands** # Optional
            },
            "quic": {
                "Runtime"     : **Int: Time of Test Duration in seconds**,
                "Connections"   : **Array: List of number of receiver ports for tcp**,
                "Options"       : **String: Additional options for commands** # Optional
            }
        },
        "Throughput" : {
            "tcp": {
                "Runtime"     : **Int: Time of Test Duration in seconds**,
                "BufferLen"     : **Array: List of buffer size for tcp in n[KMG] Bytes**,
                "Connections"   : **Array: List of number of receiver ports for tcp**,
                "Options"       : **String: Additional options for commands** # Optional
            }
            "quic": {
                "Runtime"     : **Int: Time of Test Duration in seconds**,
                "BufferLen"     : **Array: List of buffer size for tcp in n[KMG] Bytes**,
                "Connections"   : **Array: List of number of receiver ports for tcp**,
                "Options"       : **String: Additional options for commands** # Optional
            }
        }
    }
}
```
