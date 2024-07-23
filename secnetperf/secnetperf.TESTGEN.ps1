#===============================================
# Script Input Parameters Enforcement
#===============================================
Param(
    [parameter(Mandatory=$false)] [string] $Config = "Default",
    [parameter(Mandatory=$true)]  [string] $DestIp,
    [parameter(Mandatory=$true)]  [string] $SrcIp,
    [parameter(Mandatory=$true)]  [ValidateScript({Test-Path $_ -PathType Container})] [String] $OutDir = "",
    [parameter(Mandatory=$false)] [switch] $SamePort = $false
)
$scriptName = $MyInvocation.MyCommand.Name 

function input_display {
    $g_path = Get-Location

    Write-Output "============================================"
    Write-Output "$g_path\$scriptName"
    Write-Output " Inputs:"
    Write-Output "  -Config     = $Config"
    Write-Output "  -DestIp     = $DestIp"
    Write-Output "  -SrcIp      = $SrcIp"
    Write-Output "  -OutDir     = $OutDir"
    Write-Output "============================================"
} # input_display()

#===============================================
# Internal Functions
#===============================================
function banner {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $Msg
    )
    Write-Output "`n==========================================================================="
    Write-Output "| $Msg"
    Write-Output "==========================================================================="
} # banner()

function test_recv {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)]   [int]    $Port,
        [parameter(Mandatory=$true)]  [string]  $Exec
    )

    [string] $cmd = "secnetperf.exe -port:$port -exec:$Exec"
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_log
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_logRecv
    Write-Output   $cmd 
} # test_recv()

function test_send_latency {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)]  [int]    $Secs,
        [parameter(Mandatory=$true)]  [int]    $Size,
        [parameter(Mandatory=$true)]   [int]    $Port,
        [parameter(Mandatory=$true)]   [String] $Type,
        [parameter(Mandatory=$true)]   [int]    $Requests,
        [parameter(Mandatory=$false)]  [String] $Options,
        [parameter(Mandatory=$true)]   [String] $OutDir,
        [parameter(Mandatory=$true)]   [String] $Fname
    )

    [string] $out = (Join-Path -Path $OutDir -ChildPath "$Fname")

    [string] $cmd = "secnetperf.exe -target:$DestIp -port:$Port -tcp:$Type -up:$Requests -down:$Size -run:$($Secs)s -rstream:1 -platency:1 $Options > $out.txt"
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_log
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_logSend
    Write-Output   $cmd 
} # test_send_latency()

function test_send_handshakes {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$false)]  [int]    $Secs,
        [parameter(Mandatory=$true)]   [int]    $Port,
        [parameter(Mandatory=$true)]   [String] $Type,
        [parameter(Mandatory=$true)]   [int]    $Conns,
        [parameter(Mandatory=$false)]  [String] $Options,
        [parameter(Mandatory=$true)]   [String] $OutDir,
        [parameter(Mandatory=$true)]   [String] $Fname
    )

    [string] $out = (Join-Path -Path $OutDir -ChildPath "$Fname")

    [string] $cmd = "secnetperf.exe -target:$DestIp -port:$Port -tcp:$Type -conns:$Conns -run:$($Secs)s -rconn:1 -exec:maxtput -prate:1 $Options > $out.txt"
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_log
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_logSend
    Write-Output   $cmd 
} # test_send_handshakes()

function test_send_throughput {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$false)]  [int]    $Secs,
        [parameter(Mandatory=$true)]   [int]    $Port,
        [parameter(Mandatory=$true)]   [String] $Type,
        [parameter(Mandatory=$true)]   [int]    $Len,
        [parameter(Mandatory=$true)]   [int]    $Conns,
        [parameter(Mandatory=$false)]  [String] $Options,
        [parameter(Mandatory=$true)]   [String] $OutDir,
        [parameter(Mandatory=$true)]   [String] $Fname
    )

    [string] $out = (Join-Path -Path $OutDir -ChildPath "$Fname")

    [string] $cmd = "secnetperf.exe -target:$DestIp -port:$Port -tcp:$Type -iosize:$Len -conns:$Conns -up:$($Secs)s -down:$($Secs)s -exec:maxtput -ptput:1 $Options > $out.txt"
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_log
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_logSend
    Write-Output   $cmd 
} # test_send_throughput()

function test_latency {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$false)] [String] $OutDir,
        [parameter(Mandatory=$true)] [String] $Proto
    )
    # vary send method
    $protoParam = if ($Proto -eq "tcp") {"1"} else {"0"};
    $dir = (Join-Path -Path $OutDir -ChildPath $Proto) 
    New-Item -ItemType directory -Path $dir | Out-Null
    $Config = $g_Config.TestType.Latency.$Proto
    $Fname = "t$($Config.Runtime).i$($Config.Requests)"
    for ($i=0; $i -lt $g_Config.Iterations; $i++) {
        # vary on port number
        [int] $portstart = $g_Config.StartPort
        if (-Not $g_SamePort) {
            $portstart += ($i * $g_Config.Iterations)
        }
        test_recv -Port $portstart -Exec 'lowlat'
        test_send_latency -Port $portstart -Secs $Config.Runtime -Size $Config.ByteSize -Type $protoParam -Requests $Config.Requests -OutDir $dir -Fname "$Proto.send.$Fname.iter$i" -Options $Options
    }
}

function test_handshakes {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$false)] [String] $OutDir,
        [parameter(Mandatory=$true)] [String] $Proto
    )
    # vary send method
    $protoParam = if ($Proto -eq "tcp") {"1"} else {"0"};
    $dir = (Join-Path -Path $OutDir -ChildPath $Proto) 
    New-Item -ItemType directory -Path $dir | Out-Null
    $Config = $g_Config.TestType.Handshakes.$Proto
    for ($j=0; $j -lt $Config.Connections.Length; $j++) {
        $Conn = $Config.Connections[$j]
        $Fname = "m$Conn"
        for ($i=0; $i -lt $g_Config.Iterations; $i++) {
            # vary on port number
            [int] $portstart = $g_Config.StartPort
            if (-Not $g_SamePort) {
                $portstart += ($i * $g_Config.Iterations)
            }
            test_recv -Port $portstart -Exec 'maxtput'
            test_send_handshakes -Port $portstart -Secs $Config.Runtime -Conns $Conn -Type $protoParam -OutDir $dir -Fname "$Proto.send.$Fname.iter$i" -Options $Options
        }
    }
}

function test_throughput {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$false)] [String] $OutDir,
        [parameter(Mandatory=$true)] [String] $Proto
    )
    # vary send method
    $protoParam = if ($Proto -eq "tcp") {"1"} else {"0"};
    $dir = (Join-Path -Path $OutDir -ChildPath $Proto) 
    New-Item -ItemType directory -Path $dir | Out-Null
    $Config = $g_Config.TestType.Throughput.$Proto
    for ($j=0; $j -lt $Config.Connections.Length; $j++) {
        $Conn = $Config.Connections[$j]
        for ($k=0; $k -lt $Config.BufferLen.Length; $k++) {
            $Len = $Config.BufferLen[$k]
            $Fname = "m$Conn.l$Len"
            for ($i=0; $i -lt $g_Config.Iterations; $i++) {
                # vary on port number
                [int] $portstart = $g_Config.StartPort
                if (-Not $g_SamePort) {
                    $portstart += ($i * $g_Config.Iterations)
                }
                test_recv -Port $portstart -Exec 'maxtput'
                test_send_throughput -Port $portstart -Secs $Config.Runtime -Conns $Conn -Len $Len -Type $protoParam -OutDir $dir -Fname "$Proto.send.$Fname.iter$i" -Options $Options
            }
        }
    }
}

function test_secnetperf_generate {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $OutDir
    )
    if ($null -ne $g_Config.TestType.Latency) {
        # latency directory
        $dir = (Join-Path -Path $OutDir -ChildPath "latency") 
        New-Item -ItemType directory -Path $dir | Out-Null
        if ($null -ne $g_Config.TestType.Latency.tcp) {
            test_latency -OutDir $dir -Proto 'tcp'
        }
        if ($null -ne $g_Config.TestType.Latency.quic) {
            test_latency -OutDir $dir -Proto 'quic'
        }
    }

    if ($null -ne $g_Config.TestType.Handshakes) {
        # latency directory
        $dir = (Join-Path -Path $OutDir -ChildPath "handshakes") 
        New-Item -ItemType directory -Path $dir | Out-Null
        if ($null -ne $g_Config.TestType.Handshakes.tcp) {
            test_handshakes -OutDir $dir -Proto 'tcp'
        }
        if ($null -ne $g_Config.TestType.Handshakes.quic) {
            test_handshakes -OutDir $dir -Proto 'quic'
        }
    }

    if ($null -ne $g_Config.TestType.Throughput) {
        $dir = (Join-Path -Path $OutDir -ChildPath "throughput") 
        New-Item -ItemType directory -Path $dir | Out-Null
        if ($null -ne $g_Config.TestType.Throughput.tcp) {
            test_throughput -OutDir $dir -Proto 'tcp'
        }
        if ($null -ne $g_Config.TestType.Throughput.quic) {
            test_throughput -OutDir $dir -Proto 'quic'
        }
    }
} # test_secnetperf()

function validate_config {
    $isValid = $true
    $int_vars = @('Iterations', 'StartPort')
    foreach ($var in $int_vars) {
        if (($null -eq $g_Config.($var)) -or ($g_Config.($var) -lt 0)) {
            Write-Output "$var is required and must be greater than or equal to 0"
            $isValid = $false
        }
    }
    $valid_protocols = @('tcp', 'quic')
    if ($null -ne $g_Config.TestType.Latency) {
        foreach ($proto in $valid_protocols) {
            if ($null -ne $g_Config.TestType.Latency.$proto) {
                $port_vars = @('Runtime', 'ByteSize', 'Requests')
                foreach ($var in $port_vars) {
                    if (($null -eq $g_Config.TestType.Latency.$proto.$var) -or ($g_Config.TestType.Latency.$proto.$var -le 0)) {
                        Write-Output "$var is required to be greater than 0 if $proto is present "
                        $isValid = $false
                    }
                }
            } 
        }
    }
    if ($null -ne $g_Config.TestType.Handshakes) {
        foreach ($proto in $valid_protocols) {
            if ($null -ne $g_Config.TestType.Handshakes.$proto) {
                if (($null -eq $g_Config.TestType.Handshakes.$proto.Runtime) -or ($g_Config.TestType.Handshakes.$proto.Runtime -le 0)) {
                    Write-Output "Runtime is required to be greater than 0 if $proto is present "
                    $isValid = $false
                }
                $arr = $g_Config.TestType.Handshakes.$proto.Connections
                if (($null -eq $arr) -or ($arr.length -le 0)) {
                    Write-Output "$var is required and must have at least 1 item"
                    $isValid = $false
                } else {
                    foreach ($num in $arr) {
                        if ($num -le 0) {
                            Write-Output "$num in Connections is required to be greater than 0"
                            $isValid = $false
                        }
                    }
                }
            }
        }
    }
    if ($null -ne $g_Config.TestType.Throughput) {
        foreach ($proto in $valid_protocols) {
            if ($null -ne $g_Config.TestType.Throughput.$proto) {
                if (($null -eq $g_Config.TestType.Throughput.$proto.Runtime) -or ($g_Config.TestType.Throughput.$proto.Runtime -le 0)) {
                    Write-Output "Runtime is required to be greater than 0 if $proto is present "
                    $isValid = $false
                }
                $arr_vars = @('BufferLen', 'Connections')
                foreach ($var in $arr_vars) {
                    $arr = $g_Config.TestType.Throughput.$proto.$var
                    if (($null -eq $arr) -or ($arr.length -le 0)) {
                        Write-Output "$var is required and must have at least 1 item"
                        $isValid = $false
                    } else {
                        foreach ($num in $arr) {
                            if ($num -le 0) {
                                Write-Output "$num in $var is required to be greater than 0"
                                $isValid = $false
                            }
                        }
                    }

                }
            } 
        }
    }
    return $isValid
} # validate_config()

#===============================================
# External Functions - Main Program
#===============================================
function test_main {
    Param(
        [parameter(Mandatory=$false)] [string] $Config = "Default",
        [parameter(Mandatory=$true)]  [string] $DestIp,
        [parameter(Mandatory=$true)]  [string] $SrcIp,
        [parameter(Mandatory=$true)]  [ValidateScript({Test-Path $_ -PathType Container})] [String] $OutDir = "",
        [parameter(Mandatory=$false)] [switch] $SamePort = $false
    )
    try {
        # input_display
        # get config variables
        $allConfig = Get-Content -Path "$PSScriptRoot\secnetperf.Config.json" | ConvertFrom-Json
        [Object] $g_Config     = $allConfig.("Secnetperf$Config")
        if ($null -eq $g_Config) {
            Write-Output "Secnetperf$Config does not exist in .\secnetperf\Secnetperf.Config.json. Please provide a valid config"
            Throw
        }
        if (-Not (validate_config)) {
            Write-Output "Secnetperf$Config is not a valid config"
            Throw
        }
        [string] $g_DestIp     = $DestIp.Trim()
        [string] $g_SrcIp      = $SrcIp.Trim()
        [string] $dir          = (Join-Path -Path $OutDir -ChildPath "secnetperf") 
        [string] $g_log        = "$dir\SECNETPERF.Commands.txt"
        [string] $g_logSend    = "$dir\SECNETPERF.Commands.Send.txt"
        [string] $g_logRecv    = "$dir\SECNETPERF.Commands.Recv.txt"
        [boolean] $g_SamePort  = $SamePort.IsPresent

        New-Item -ItemType directory -Path $dir | Out-Null
        
        # Optional - Edit spaces in output path for Invoke-Expression compatibility
        # $dir  = $dir  -replace ' ','` '
        banner -Msg "Secnetperf Tests"
        test_secnetperf_generate -OutDir $dir
    } catch {
        Write-Output "Unable to generate SECNETPERF commands"
        Write-Output "Exception $($_.Exception.Message) in $($MyInvocation.MyCommand.Name)"
    }
} test_main @PSBoundParameters # Entry Point