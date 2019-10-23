<#
.SYNOPSIS
    Monitor a target system for ICMP, TCP, and UDP network blackout.
#>
[CmdletBinding(DefaultParameterSetName="Remoting")]
param(
    [Parameter(ParameterSetName="Client", Mandatory=$true)]
    [Parameter(ParameterSetName="Remoting", Mandatory=$true)]
    [String] $Target,

    [Parameter(ParameterSetName="Client", Mandatory=$false)]
    [Parameter(ParameterSetName="Remoting", Mandatory=$false)]
    [String] $PingTarget = $Target,

    [Parameter(ParameterSetName="Remoting", Mandatory=$true)]
    [PSCredential] $Credential,

    [Parameter(ParameterSetName="Client", Mandatory=$true)]
    [Switch] $Client,

    [Parameter(ParameterSetName="Server", Mandatory=$true)]
    [Switch] $Server,

    [Parameter(Mandatory=$false)]
    [ValidateRange(1000, [Int]::MaxValue)]
    [Int] $BlackoutThreshold = 1000, # ms

    [Parameter(Mandatory=$false)]
    [ValidateSet("*", "ICMP", "TCP", "UDP")]
    [String[]] $Protocols = "*",

    [Parameter(Mandatory=$false)]
    [ValidateRange(0, 65536)]
    [Int] $TCPPort = 5554,

    [Parameter(Mandatory=$false)]
    [ValidateRange(1, [Int]::MaxValue)]
    [Int] $TCPConnections = 1,

    [Parameter(Mandatory=$false)]
    [ValidateRange(1, [Int]::MaxValue)]
    [Int] $TCPMillisecondsPerPacket = 2,

    [Parameter(Mandatory=$false)]
    [ValidateRange(0, 65536)]
    [Int] $UDPPort = 5555,

    [Parameter(Mandatory=$false)]
    [ValidateScript({Test-Path $_ -PathType Container})]
    [String] $BinDir = $PSScriptRoot,

    [Parameter(ParameterSetName="Remoting", Mandatory=$false)]
    [ValidateScript({Test-Path $_ -PathType Container})]
    [String] $TargetBinDir = $BinDir
)

$pingCmd = {
    param($Target)

    while ($true) {
        $a = Get-Date
        $b = ping -n 1 -w 50 $Target
        Write-Output "$($a.Ticks),$($b[2])"
    }
}

function Out-ICMPBlackout([Hashtable] $State, [String] $Target, [Int] $BlackoutThreshold) {
    Receive-Job $State.ICMPJob | foreach {
        #Write-Host $_
        $tickCount, $response = $_ -split ","

        if ($response -like "Reply from*") {
            $deltaMS = ([Int64]$tickCount / 10000) - ($State.LastPingTick / 10000)
            if ($deltaMS -gt $BlackoutThreshold) {
                Write-Output "$Target ICMP Blackout: $deltaMS ms"
            }

            $State.LastPingTick = $tickCount
        }
    }
}

$ctsTrafficCmd = {
    param($BinDir, $Target, $Port, $Connections, $msPerPacket, $Protocol, $Role)

    if ($Protocol -eq "UDP") {
        $protocolArgs = @("-Protocol:UDP", "-Port:$Port", "-BitsPerSecond:320000", "-FrameRate:1000", "-BufferDepth:1", "-StreamLength:100000")
    } else {
        $bufferSize = 32 # bytes
        $rateLimit = [Int]($bufferSize * (1000 / $msPerPacket))

        $protocolArgs = @("-Protocol:TCP", "-Port:$Port", "-Pattern:duplex", "-Buffer:$BufferSize", "-RateLimit:$rateLimit", "-RateLimitPeriod:$msPerPacket")
    }

    if ($Role -eq "Server") {
        $roleArgs = @("-Listen:*")
    } else {
        $roleArgs = @("-Target:$Target", "-Connections:$Connections", "-ConsoleVerbosity:1", "-StatusUpdate:10")
    }

    #Write-Host "$BinDir\ctsTraffic.exe $roleArgs $protocolArgs"
    &"$BinDir\ctsTraffic.exe" $roleArgs $protocolArgs
}

<#
.SYNOPSIS
    Cts Traffic always outputs a bunch of text to the console
    we don't care about. This function "scrolls" past it so
    it's not parsed.
#>
function Wait-CtsClientJob($Job) {
    for ($i = 0; $i -lt 1000; $i++) {
        foreach ($line in $(Receive-Job $Job)) {
            if ($line -like " TimeSlice*") {
                return
            }
        }
        Start-Sleep -Milliseconds 15
    }

    throw "Wait-CtsClientJob : Timed out"
}

function Get-CtsTrafficDelta([Double] $Timestamp, [Double] $NewValue) {
    return ($NewValue - $Timestamp) * 1000
}

function Out-TCPBlackout([Hashtable] $State, [String] $Target, [Int] $BlackoutThreshold) {
    Receive-Job $State.TCPJob | foreach {
        #Write-Host $_
        $null, $timestamp, $sendBps, $recvBps, $null = $_ -split "\s+"

        if ($timestamp -eq "TimeSlice") {
            continue
        }

        if (($sendBps -as [Int]) -gt 0) {
            $delta = Get-CtsTrafficDelta $State.LastTCPSend $timestamp
            if ($delta -gt $BlackoutThreshold) {
                Write-Output "$Target TCP Send Blackout: $delta ms"
            }
            $State.LastTCPSend = $timestamp
        }

        if (($recvBps -as [Int]) -gt 0) {
            $delta = Get-CtsTrafficDelta $State.LastTCPRecv $timestamp
            if ($delta -gt $BlackoutThreshold) {
                Write-Output "$Target TCP Recv Blackout: $delta ms"
            }
            $State.LastTCPRecv = $timestamp
        }
    }
}

function Out-UDPBlackout([Hashtable] $State, [String] $Target, [Int] $BlackoutThreshold) {
    Receive-Job $State.UDPJob | foreach {
        #Write-Host $_
        $null, $timestamp, $bitsPerSecond, $null = $_ -split "\s+"

        if ($timestamp -eq "TimeSlice") {
            continue
        }

        if (($bitsPerSecond -as [Int]) -gt 0) {
            if ($State.InitialUDPBlackout -gt 0) {
                Write-Output "$Target UDP Recv Blackout: $($State.InitialUDPBlackout + ([Double]$timestamp * 1000)) ms"
                $State.InitialUDPBlackout = 0
            }
            $State.LastUDPRecv = $timestamp
        } elseif ($State.InitialUDPBlackout -eq 0) {
            $delta = Get-CtsTrafficDelta $State.LastUDPRecv $timestamp
            if ($delta -gt $BlackoutThreshold) {

                # CTS Traffic won't restablish the existing UDP
                # connection, so we need to restart the client.
                $restartTime = Measure-Command {
                    $State.UDPJob | Stop-Job | Remove-Job
                    $State.UDPJob = Start-Job $ctsTrafficCmd -ArgumentList $BinDir, $Target, $UDPPort, 1, 1, "UDP", "Client"
                    Wait-CtsClientJob $State.UDPJob
                }

                $State.InitialUDPBlackout = $delta + $restartTime.TotalMilliseconds
            }
        }
    }
}

$emptyJob = Start-Job {return}

$remotingParams = @{}
if ($PSCmdlet.ParameterSetName -eq "Remoting") {
    $Server = $true
    $Client = $true
    $remotingParams["ComputerName"] = $Target
    $remotingParams["Credential"] = $Credential
}

$state = @{
    ServerJobs = @()
    ICMPJob = $emptyJob
    LastPingTick = [Int64](Get-Date).Ticks

    TCPJob = $emptyJob
    LastTCPSend = 0d
    LastTCPRecv = 0d

    UDPJob = $emptyJob
    LastUDPRecv = 0d
    InitialUDPBlackout = 0
}

try {
    if (("ICMP" -in $Protocols) -or ("*" -in $Protocols)) {
        if ($Client) {
            $state.ICMPJob = Start-Job -ScriptBlock $pingCmd -ArgumentList $PingTarget
        }
    }

    if (("TCP" -in $Protocols) -or ("*" -in $Protocols)) {
        if ($Server) {
            $tcpArgs = @($TargetBinDir, $Target, $TCPPort, $TCPConnections, $TCPMillisecondsPerPacket, "TCP", "Server")

            if ($PSCmdlet.ParameterSetName -eq "Remoting") {
                $state.ServerJobs += Invoke-Command @remotingParams -ScriptBlock $ctsTrafficCmd -ArgumentList $tcpArgs -AsJob
            } else {
                $state.ServerJobs += Start-Job -ScriptBlock $ctsTrafficCmd -ArgumentList $tcpArgs
            }
        }

        if ($Client) {
            $state.TCPJob = Start-Job -ScriptBlock $ctsTrafficCmd -ArgumentList $BinDir, $Target, $TCPPort, $TCPConnections, $TCPMillisecondsPerPacket, "TCP", "Client"
            Wait-CtsClientJob $state.TCPJob
        }
    }

    if (("UDP" -in $Protocols) -or ("*" -in $Protocols)) {
        if ($Server) {
            $udpArgs = @($TargetBinDir, $Target, $UDPPort, 1, 1, "UDP", "Server")
            if ($PSCmdlet.ParameterSetName -eq "Remoting") {
                $state.ServerJobs += Invoke-Command @remotingParams -ScriptBlock $ctsTrafficCmd -ArgumentList $udpArgs -AsJob
            } else {
                $state.ServerJobs += Start-Job -ScriptBlock $ctsTrafficCmd -ArgumentList $udpArgs
            }
        }

        if ($Client) {
            $state.UDPJob = Start-Job -ScriptBlock $ctsTrafficCmd -ArgumentList $BinDir, $Target, $UDPPort, 1, 1, "UDP", "Client"
            Wait-CtsClientJob $state.UDPJob
        }
    }

    if ($Client) {
        Write-Host "Monitoring... Ctrl+C to stop."
        while ($true) {
            Out-ICMPBlackout -State $state -Target $PingTarget -BlackoutThreshold $BlackoutThreshold
            Out-TCPBlackout -State $state -Target $Target -BlackoutThreshold $BlackoutThreshold
            Out-UDPBlackout -State $state -Target $Target -BlackoutThreshold $BlackoutThreshold
            Start-Sleep -Milliseconds 10
        }
    } else {
        Write-Host "Server started... Ctrl+C to stop."
        while ($true) {
            Start-Sleep 30
        }
    }
} finally {
    Write-Host "Stopping background tasks..."

    #if ($PSCmdlet.ParameterSetName -eq "Remoting") {
    #    Invoke-Command -ScriptBlock {taskkill /im ctsTraffic.exe /F} -ComputerName $Target -Credential $Credential
    #}

    $state.ServerJobs | foreach {
        $_ | Stop-Job
        $_ | Remove-Job
    }

    @($state.ICMPJob, $state.TCPJob, $state.UDPJob, $emptyJob) | foreach {
        $_ | Stop-Job
        $_ | Remove-Job
    }
}
