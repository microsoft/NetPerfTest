# L4pingConfig Guidelines
Any optional variables will be omitted
```
    "L4ping**ConfigName**": { # Name of config must start with L4ping
        "Iterations"        : **Int: Number of command iterations**,
        "StartPort"         : **Int: Starting Server Port Number**,
        "ClientSendSize"    : **Int: Number of bytes the client should send to the server for every ping**,
        "ClientReceiveSize" : **Int: Number of bytes the client should receive back from the server for every ping**,
        "PingIterations"    : **Int: Number of pings to send per command iteration**,
        "Percentiles"       : **String: List of percentiles to report in the results output**
    }
```