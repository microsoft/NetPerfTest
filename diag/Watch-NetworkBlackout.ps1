<#
.SYNOPSIS
    Monitor a target system for ICMP, TCP, and UDP network blackout.
#>
param(
    [Parameter(Mandatory=$true)]
    [String] $Target,

    [Parameter(Mandatory=$true)]
    [PSCredential] $Credential,

    [Parameter(Mandatory=$false)]
    [ValidateRange(1000, [Int]::MaxValue)]
    [Int] $BlackoutThreshold = 1000, # ms

    [Parameter(Mandatory=$false)]
    [ValidateSet("ICMP", "TCP", "UDP")]
    [String[]] $Protocols = @("ICMP", "TCP", "UDP"),

    [Parameter(Mandatory=$false)]
    [ValidateRange(0, 65536)]
    [Int] $TCPPort = 5554,

    [Parameter(Mandatory=$false)]
    [ValidateRange(1, [Int]::MaxValue)]
    [Int] $TCPConnections = 1,

    [Parameter(Mandatory=$false)]
    [ValidateRange(0, 65536)]
    [Int] $UDPPort = 5555,

    [Parameter(Mandatory=$false)]
    [ValidateScript({Test-Path $_ -PathType Container})]
    [String] $BinDir = $PSScriptRoot,

    [Parameter(Mandatory=$false)]
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

$ctsTrafficCmd = {
    param($BinDir, $Target, $Port, $Connections, $Protocol, $Role)

    if ($Protocol -eq "UDP") {
        $commonArgs = @("-Protocol:UDP", "-Port:$Port", "-BitsPerSecond:320000", "-FrameRate:1000", "-BufferDepth:1", "-StreamLength:100000")
    } else {
        $bufferSize = 64 # bytes
        $rateLimitPeriod = 1 # ms

        # Allows 1 packet per rateLimitPeriod
        $rateLimit = $bufferSize * (1000 / $rateLimitPeriod)

        $commonArgs = @("-Protocol:TCP", "-Port:$Port", "-Pattern:duplex", "-Buffer:$BufferSize", "-RateLimit:$rateLimit", "-RateLimitPeriod:$rateLimitPeriod")
    }

    if ($Role -eq "Server") {
        &"$BinDir\ctsTraffic.exe" -Listen:$Target $commonArgs
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

try {
    $emptyJob = Start-Job {return}

    # Init state tracking
    $servers = @()
    $client = @{
        ICMPJob = $emptyJob
        LastPingTick = [Int64](Get-Date).Ticks

        TCPJob = $emptyJob
        LastTCPSend = 0d
        LastTCPRecv = 0d

        UDPJob = $emptyJob
        LastUDPRecv = 0d
        InitialUDPBlackout = 0
    }

    if ("ICMP" -in $Protocols) {
        $client.ICMPJob = Start-Job -ScriptBlock $pingCmd -ArgumentList $Target
    }

    if ("TCP" -in $Protocols) {
        $servers += Invoke-Command -ScriptBlock $ctsTrafficCmd -ArgumentList $TargetBinDir, $Target, $TCPPort, $TCPConnections, "TCP", "Server" -ComputerName $Target -Credential $Credential -AsJob
        $client.TCPJob = Start-Job -ScriptBlock $ctsTrafficCmd -ArgumentList $BinDir, $Target, $TCPPort, $TCPConnections, "TCP", "Client"
        Wait-CtsClientJob $client.TCPJob
    }

    if ("UDP" -in $Protocols) {
        $servers += Invoke-Command -ScriptBlock $ctsTrafficCmd -ArgumentList $TargetBinDir, $Target, $UDPPort, 1, "UDP", "Server" -ComputerName $Target -Credential $Credential -AsJob
        $client.UDPJob = Start-Job -ScriptBlock $ctsTrafficCmd -ArgumentList $BinDir, $Target, $UDPPort, 1, "UDP", "Client"
        Wait-CtsClientJob $client.UDPJob
    }

    Write-Host "Monitoring... Ctrl+C to stop."
    while ($true) {
        Receive-Job $client.ICMPJob | foreach {
            #Write-Debug $_
            $tickCount, $response = $_ -split ","

            if ($response -like "Reply from*") {
                $deltaMS = ([Int64]$tickCount / 10000) - ($client.LastPingTick / 10000)
                if ($deltaMS -gt $BlackoutThreshold) {
                    Write-Output "$Target ICMP Blackout: $deltaMS ms"
                }

                $client.LastPingTick = $tickCount
            }
        }

        # Parse TCP output
        Receive-Job $client.TCPJob | foreach {
            #Write-Debug $_
            $null, $timestamp, $sendBps, $recvBps, $null = $_ -split "\s+"

            if ($timestamp -eq "TimeSlice") {
                continue
            }
 
            if (($sendBps -as [Int]) -gt 0) {
                $delta = Get-CtsTrafficDelta $client.LastTCPSend $timestamp
                if ($delta -gt $BlackoutThreshold) {
                    Write-Output "$Target TCP Send Blackout: $delta ms"
                }
                $client.LastTCPSend = $timestamp
            }

            if (($recvBps -as [Int]) -gt 0) {
                $delta = Get-CtsTrafficDelta $client.LastTCPRecv $timestamp
                if ($delta -gt $BlackoutThreshold) {
                    Write-Output "$Target TCP Recv Blackout: $delta ms"
                }
                $client.LastTCPRecv = $timestamp
            }
        }
    
        # Parse UDP output
        Receive-Job $client.UDPJob | foreach {
            #Write-Debug $_
            $null, $timestamp, $bitsPerSecond, $null = $_ -split "\s+"

            if ($timestamp -eq "TimeSlice") {
                continue
            }

            if (($bitsPerSecond -as [Int]) -gt 0) {
                if ($client.InitialUDPBlackout -gt 0) {
                    Write-Output "$Target UDP Recv Blackout: $($client.InitialUDPBlackout + ([Double]$timestamp * 1000)) ms"
                    $client.InitialUDPBlackout = 0
                }
                $client.LastUDPRecv = $timestamp
            } elseif ($client.InitialUDPBlackout -eq 0) {
                $delta = Get-CtsTrafficDelta $client.LastUDPRecv $timestamp
                if ($delta -gt $BlackoutThreshold) {

                    # CTS Traffic won't restablish the existing UDP
                    # connection, so we need to restart the client.
                    $restartTime = Measure-Command {
                        $client.UDPJob | Stop-Job | Remove-Job
                        $client.UDPJob = Start-Job $ctsTrafficCmd -ArgumentList $BinDir, $Target, $UDPPort, 1, "UDP", "Client"
                        Wait-CtsClientJob $client.UDPJob
                    }

                    #Write-Debug "Restart time = $($restartTime.TotalMilliseconds)"

                    $client.InitialUDPBlackout = $delta + $restartTime.TotalMilliseconds
                }
            }
        }
    } # while ($true)
} catch {
    throw $_
} finally {
    Write-Host "Stopping background tasks..."

    Invoke-Command -ScriptBlock {taskkill /im ctsTraffic.exe /F} -ComputerName $Target -Credential $Credential
    $servers | foreach {$_ | Stop-Job | Remove-Job}

    $client.ICMPJob | Stop-Job | Remove-Job
    $client.TCPJob | Stop-Job | Remove-Job
    $client.UDPJob | Stop-Job | Remove-Job

    $emptyJob | Stop-Job | Remove-Job
}