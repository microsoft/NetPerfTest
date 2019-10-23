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
    [Int] $TCPMillisecondsPerPacket = 1,

    [Parameter(Mandatory=$false)]
    [ValidateRange(0, 65536)]
    [Int] $UDPPort = 5555,

    [Parameter(Mandatory=$false)]
    [ValidateScript({Test-Path $_ -PathType Container})]
    [String] $BinDir = $PSScriptRoot,

    [Parameter(ParameterSetName="Remoting", Mandatory=$false)]
    [ValidateScript({Test-Path $_ -PathType Container})]
    [String] $TargetBinDir = $BinDir,

    [Parameter(Mandatory=$false)]
    [Switch] $AsJob
)

$pingCmd = {
    param($Target)

    while ($true) {
        $a = Get-Date
        $b = ping -n 1 -w 50 $Target
        Write-Output "$($a.Ticks),$($b[2])"
    }
}

$ctsTrafficCmd = {
    param($BinDir, $Target, $Port, $Connections, $msPerPacket, $Protocol, $Role)

    if ($Protocol -eq "UDP") {
        $commonArgs = @("-Protocol:UDP", "-Port:$Port", "-BitsPerSecond:320000", "-FrameRate:1000", "-BufferDepth:1", "-StreamLength:100000")
    } else {
        # Allow 1 packet per msPerPacket
        $bufferSize = 16 # bytes
        $rateLimit = $bufferSize * (1000 / $msPerPacket)

        $commonArgs = @("-Protocol:TCP", "-Port:$Port", "-Pattern:duplex", "-Buffer:$BufferSize", "-RateLimit:$rateLimit", "-RateLimitPeriod:$msPerPacket")
    }

    if ($Role -eq "Server") {
        &"$BinDir\ctsTraffic.exe" -Listen:* $commonArgs
    } else {
        &"$BinDir\ctsTraffic.exe" -Target:$Target $commonArgs -Connections:$Connections -ConsoleVerbosity:1 -StatusUpdate:10
    }
}

function Get-CtsTrafficDelta([Double] $Timestamp, [Double] $NewValue) {
    return ($NewValue - $Timestamp) * 1000
}

<#
    Cts Traffic always outputs a bunch of text to the console
    we don't care about. This function "scrolls" past it so
    it's not parsed.
#>
function Wait-CtsClientJob($Job) {
    for ($i = 0; $i -lt 20000; $i++) {
        foreach ($line in $($Job | Receive-Job)) {
            if ($line -like " TimeSlice*") {
                #Write-Debug "Wait-CtsClientJob : $i iterations."
                return
            }
        }
    }
    throw "Wait-CtsClientJob : Timed out"
}

$emptyJob = Start-Job {return}

$remotingParams = @{
    "ComputerName" = "localhost"
}

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
            $state.ServerJobs += Invoke-Command -ScriptBlock $ctsTrafficCmd -ArgumentList $TargetBinDir, $Target, $TCPPort, $TCPConnections, $TCPMillisecondsPerPacket, "TCP", "Server" @remotingParams -AsJob
        }

        if ($Client) {
            $state.TCPJob = Start-Job -ScriptBlock $ctsTrafficCmd -ArgumentList $BinDir, $Target, $TCPPort, $TCPConnections, $TCPMillisecondsPerPacket, "TCP", "Client"
            Wait-CtsClientJob $state.TCPJob
        }
    }

    if (("UDP" -in $Protocols) -or ("*" -in $Protocols)) {
        if ($Server) {
            $state.ServerJobs += Invoke-Command -ScriptBlock $ctsTrafficCmd -ArgumentList $TargetBinDir, $Target, $UDPPort, 1, 1, "UDP", "Server" @remotingParams -AsJob
        }

        if ($Client) {
            $state.UDPJob = Start-Job -ScriptBlock $ctsTrafficCmd -ArgumentList $BinDir, $Target, $UDPPort, 1, 1, "UDP", "Client"
            Wait-CtsClientJob $state.UDPJob
        }
    }

    Write-Host "Monitoring... Ctrl+C to stop."
    while ($true) {
        Receive-Job $state.ICMPJob | foreach {
            #Write-Debug $_
            $tickCount, $response = $_ -split ","

            if ($response -like "Reply from*") {
                $deltaMS = ([Int64]$tickCount / 10000) - ($state.LastPingTick / 10000)
                if ($deltaMS -gt $BlackoutThreshold) {
                    Write-Output "$Target ICMP Blackout: $deltaMS ms"
                }

                $state.LastPingTick = $tickCount
            }
        }

        # Parse TCP output
        Receive-Job $state.TCPJob | foreach {
            #Write-Debug $_
            $null, $timestamp, $sendBps, $recvBps, $null = $_ -split "\s+"

            if ($timestamp -eq "TimeSlice") {
                continue
            }
 
            if (($sendBps -as [Int]) -gt 0) {
                $delta = Get-CtsTrafficDelta $state.LastTCPSend $timestamp
                if ($delta -gt $BlackoutThreshold) {
                    Write-Output "$Target TCP Send Blackout: $delta ms"
                }
                $state.LastTCPSend = $timestamp
            }

            if (($recvBps -as [Int]) -gt 0) {
                $delta = Get-CtsTrafficDelta $state.LastTCPRecv $timestamp
                if ($delta -gt $BlackoutThreshold) {
                    Write-Output "$Target TCP Recv Blackout: $delta ms"
                }
                $state.LastTCPRecv = $timestamp
            }
        }

        # Parse UDP output
        Receive-Job $state.UDPJob | foreach {
            #Write-Debug $_
            $null, $timestamp, $bitsPerSecond, $null = $_ -split "\s+"

            if ($timestamp -eq "TimeSlice") {
                continue
            }

            if (($bitsPerSecond -as [Int]) -gt 0) {
                if ($state.InitialUDPBlackout -gt 0) {
                    Write-Output "$Target UDP Recv Blackout: $($state.InitialUDPBlackout + ([Double]$timestamp * 1000)) ms"
                    $state.InitialUDPBlackout = 0
                }
                $state.LastUDPRecv = $timestamp
            } elseif ($state.InitialUDPBlackout -eq 0) {
                $delta = Get-CtsTrafficDelta $state.LastUDPRecv $timestamp
                if ($delta -gt $BlackoutThreshold) {

                    # CTS Traffic won't restablish the existing UDP
                    # connection, so we need to restart the client.
                    $restartTime = Measure-Command {
                        $state.UDPJob | Stop-Job | Remove-Job
                        $state.UDPJob = Start-Job $ctsTrafficCmd -ArgumentList $BinDir, $Target, $UDPPort, 1, "UDP", "Client"
                        Wait-CtsClientJob $state.UDPJob
                    }

                    #Write-Debug "Restart time = $($restartTime.TotalMilliseconds)"

                    $state.InitialUDPBlackout = $delta + $restartTime.TotalMilliseconds
                }
            }
        }
    } # while ($true)
} catch {
    throw $_
} finally {
    Write-Host "Stopping background tasks..."

    if ($PSCmdlet.ParameterSetName -eq "Remoting") {
        Invoke-Command -ScriptBlock {taskkill /im ctsTraffic.exe /F} -ComputerName $Target -Credential $Credential
    }
    $state.ServerJobs | foreach {$_ | Stop-Job | Remove-Job}

    $state.ICMPJob | Stop-Job | Remove-Job
    $state.TCPJob | Stop-Job | Remove-Job
    $state.UDPJob | Stop-Job | Remove-Job

    $emptyJob | Stop-Job | Remove-Job
}