# CtsTraffic Config Guidelines
Any optional variables will be omitted
```
"CtsTraffic**NameOfConfig**": { # Name of config must start with CtsTraffic
    "Iterations"  : **Int: Number of command iterations**,
    "StartPort"   : **Int: Starting Destination Port Number**,
    "tcp" : { # Optional
        "BufferLen"     : **Array: List of buffer size for tcp in n[KMG] Bytes**,
        "Connections"   : **Array: List of number of receiver ports for tcp**, 
        "Options"       : **String: Additional options for tcp commands e.g. --show-tcp-retrans** # Optional
    }
    "Runtime"     : **Int: Time of Test Duration in seconds**
}
```