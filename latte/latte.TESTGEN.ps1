#===============================================
# Script Input Parameters Enforcement
#===============================================
Param(
    [parameter(Mandatory=$false)] [switch] $Detail = $false,
    [parameter(Mandatory=$true)]  [string] $DestIp,
    [parameter(Mandatory=$true)]  [string] $SrcIp,
    [parameter(Mandatory=$true)]  [ValidateScript({Test-Path $_ -PathType Container})] [String] $OutDir = "" 
)
$scriptName = $MyInvocation.MyCommand.Name 

function input_display {
    $g_path = Get-Location

    Write-Host "============================================"
    Write-Host "$g_path\$scriptName"
    Write-Host " Inputs:"
    Write-Host "  -Detail = $Detail"
    Write-Host "  -DestIp = $DestIp"
    Write-Host "  -SrcIp  = $SrcIp"
    Write-Host "  -OutDir = $OutDir"
    Write-Host "============================================"
} # input_display()

#===============================================
# Internal Functions
#===============================================
function banner {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $Msg
    )

    Write-Host "==========================================================================="
    Write-Host "| $Msg"
    Write-Host "==========================================================================="
} # banner()

function test_recv {
    [string] $cmd = "latte.exe -ga"
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_logRecv
    Write-Host   $cmd 
} # test_recv()

function test_send {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$false)]  [string] $Iter,
        [parameter(Mandatory=$false)]  [int]    $Secs,
        [parameter(Mandatory=$true)]   [String] $Type,
        [parameter(Mandatory=$true)]   [String] $Snd,
        [parameter(Mandatory=$false)]  [String] $Options,
        [parameter(Mandatory=$true)]   [String] $OutDir,
        [parameter(Mandatory=$true)]   [String] $Fname
    )

    [int] $sport    = 50000
    [int] $msgbytes = 4
    [int] $rangeus  = 10
    [int] $rangemax = 98

    [string] $out = (Join-Path -Path $OutDir -ChildPath "$Fname")
    [string] $cmd = "latte.exe -sa -c -a $g_DestIp" + ":"  + "$sport $Iter -hist -hc $rangemax -hl $rangeus $Type -snd $snd $Options -dump $out.data.txt > $out.txt"
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_logSend
    Write-Host   $cmd 
} # test_send()

function test_latte_generate {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $OutDir
    )

    # Normalize output directory
    $dir = $OutDir

    # Send types - Default is 'b' per LATTE docs.
    [string]    $sndsDflt = 'b'
    [string []] $snds     = @($sndsDflt)
    if ($g_detail) {
        $snds = @($sndsDflt, 'nb', 'ove', 'ovc', 'ovp', 'sel')
    }

    # Transports
    [string []] $soctypes = @('tcp', 'udp')
    if ($g_detail) {
        $soctypes = @('raw', 'tcp', 'udp')
    }

    foreach ($soc in $soctypes) {
        # Iteration Tests
        # - Measures over input samples
        [int []] $iters = @(10000)
        if ($g_detail) { 
            $iters = @(10000, 1000000) 
        }    

        banner -Msg "Iteration Tests: [$soc] operations per bounded iterations"
        foreach ($iter in $iters) {
            foreach ($snd in $snds) {
                # Default
                test_send -Iter "-i $iter" -Type "-$soc" -Snd $snd -OutDir $dir -Fname "$soc.i$iter.$snd"
                test_recv
                Write-Host " "

                #optimized
                test_send -Iter "-i $iter" -Type "-$soc" -Snd $snd -Options "-group 0 -rio -riopoll 100000000000" -OutDir $dir -Fname "$soc.i$iter.$snd.OPT"
                test_recv
                Write-Host " "
            }
        }

        # Transaction Tests
        # - Measures operations per bounded time.
        [int []] $secs = @(10)
        if ($g_detail) { 
            $secs = @(10, 60) 
        }   

        banner -Msg "Time Tests: [$soc] operations per bounded time"
        foreach ($sec in $secs) {
            foreach ($snd in $snds) {
                # Default
                test_send -Iter "-t $sec" -Type "-$soc" -Snd $snd -OutDir $dir -Fname "$soc.t$sec.$snd"
                test_recv
                Write-Host " "

                # Optimized
                test_send -Iter "-t $sec" -Type "-$soc" -Snd $snd -Options "-group 0 -rio -riopoll 100000000000" -OutDir $dir -Fname "$soc.t$sec.$snd.OPT"
                test_recv
                Write-Host " "
            }
        }
    }
} # test_latte_generate()

#===============================================
# External Functions - Main Program
#===============================================
function test_main {
    Param(
        [parameter(Mandatory=$false)] [switch] $Detail = $false,
        [parameter(Mandatory=$true)]  [string] $DestIp,
        [parameter(Mandatory=$true)]  [string] $SrcIp,
        [parameter(Mandatory=$true)]  [ValidateScript({Test-Path $_ -PathType Container})] [String] $OutDir = "" 
    )
    input_display
    
    [bool]   $g_detail  = $Detail
    [string] $g_DestIp  = $DestIp
    [string] $g_SrcIp   = $SrcIp
    [string] $dir       = (Join-Path -Path $OutDir -ChildPath "latte") 
    [string] $g_logSend = "$dir\LATTE.Commands.Send.txt"
    [string] $g_logRecv = "$dir\LATTE.Commands.Recv.txt" 

    New-Item -ItemType directory -Path $dir | Out-Null
    
    # Optional - Edit spaces in output path for Invoke-Expression compatibility
    # $dir  = $dir  -replace ' ','` '

    test_latte_generate -OutDir $dir
} test_main @PSBoundParameters # Entry Point