# L4pingConfig Guidelines
Any optional variables will be omitted
```
    "L4ping**ConfigName**": { # Name of config must start with L4ping
        "Iterations"     : **Int: Number of command iterations**,
        "StartPort"      : **Int: Starting Server Port Number**,
        "Measures"       : **Int: Count of measures to take**,
        "ByteSizeSend"   : **Int: Byte size to send**,
        "ByteSizeRecv"   : **Int: Byte size to receive**,
        "Options"        : **String: Additional options for sender commands**
    }
```