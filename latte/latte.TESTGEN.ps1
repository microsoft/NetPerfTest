#===============================================
# Script Input Parameters Enforcement
#===============================================
Param(
    [parameter(Mandatory=$false)] [switch] $Detail = $false,
    [parameter(Mandatory=$false)] [Int]    $Iterations = 1,
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
    Write-Host "  -Detail     = $Detail"
    Write-Host "  -Iterations = $Detail"
    Write-Host "  -DestIp     = $DestIp"
    Write-Host "  -SrcIp      = $SrcIp"
    Write-Host "  -OutDir     = $OutDir"
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
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_log
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_logRecv
    Write-Host   $cmd 
} # test_recv()

function test_send {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$false)]  [string] $Iter,
        [parameter(Mandatory=$false)]  [int]    $Secs,
        [parameter(Mandatory=$true)]   [int]    $Port,
        [parameter(Mandatory=$true)]   [String] $Type,
        [parameter(Mandatory=$true)]   [String] $Snd,
        [parameter(Mandatory=$false)]  [String] $Options,
        [parameter(Mandatory=$true)]   [String] $OutDir,
        [parameter(Mandatory=$true)]   [String] $Fname,
        [parameter(Mandatory=$false)]  [bool]   $NoDumpParam = $false
    )

    #[int] $msgbytes = 4  #Latte default is 4B, no immediate need to specify.
    [int] $rangeus  = 10
    [int] $rangemax = 98

    [string] $out        = (Join-Path -Path $OutDir -ChildPath "$Fname")
    [string] $dumpOption = "-dump $out.data.txt"

    if ($NoDumpParam) {
        $dumpOption = ""
    }

    [string] $cmd = "latte.exe -sa -c -a $g_DestIp" + ":"  + "$Port $Iter -hist -hc $rangemax -hl $rangeus $Type -snd $snd $Options -so $dumpOption > $out.txt"
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_log
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
    foreach ($soc in $soctypes) {
        $dirDefault   = (Join-Path -Path $OutDir -ChildPath "default") 
        $dirOptimized = (Join-Path -Path $OutDir -ChildPath "optimized") 

        # Iteration Tests capturing each transaction time
        # - Measures over input samples
        banner -Msg "Iteration Tests: [$soc] operations per bounded iterations"
        [int] $tmp  = 50000
        [int] $iter = 10000 # When "-i" is used, latte limits iterations to 1-10000 range.
        foreach ($snd in $snds) {
            for ($i=0; $i -lt $g_iters; $i++) {
                [int] $portstart = $tmp + ($i * $g_iters)
                #optimized
                test_send -Iter "-i $iter" -Port $portstart -Type "-$soc" -Snd $snd -Options "-group 0 -rio -riopoll 100000000000" -OutDir $dirOptimized -Fname "$soc.i$iter.$snd.OPT.iter$i"
                test_recv

                if ($g_detail) {
                    # Default
                    test_send -Iter "-i $iter" -Port $portstart -Type "-$soc" -Snd $snd -OutDir $dirDefault -Fname "$soc.i$iter.$snd.iter$i"
                    test_recv
                }
            }
        }

        # Transactions per 10s
        # - Measures operations per bounded time.
        banner -Msg "Time Tests: [$soc] operations per bounded time"
        [int] $tmp = 50000
        [int] $sec = 10
        foreach ($snd in $snds) {
            for ($i=0; $i -lt $g_iters; $i++) {
                [int] $portstart = $tmp + ($i * $g_iters)
                # Optimized
                test_send -Iter "-t $sec" -Port $portstart -Type "-$soc" -Snd $snd -Options "-group 0 -rio -riopoll 100000000000" -OutDir $dirOptimized -Fname "$soc.t$sec.$snd.OPT.iter$i" -NoDumpParam $true
                test_recv

                if ($g_detail) {
                    # Default
                    test_send -Iter "-t $sec" -Port $portstart -Type "-$soc" -Snd $snd -OutDir $dirDefault -Fname "$soc.t$sec.$snd.iter$i" -NoDumpParam $true
                    test_recv
                }
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
        [parameter(Mandatory=$false)] [Int]    $Iterations = 1,
        [parameter(Mandatory=$true)]  [string] $DestIp,
        [parameter(Mandatory=$true)]  [string] $SrcIp,
        [parameter(Mandatory=$true)]  [ValidateScript({Test-Path $_ -PathType Container})] [String] $OutDir = "" 
    )
    input_display
    
    [int]    $g_iters   = $Iterations
    [bool]   $g_detail  = $Detail
    [string] $g_DestIp  = $DestIp.Trim()
    [string] $g_SrcIp   = $SrcIp.Trim()
    [string] $dir       = (Join-Path -Path $OutDir -ChildPath "latte") 
    [string] $g_log     = "$dir\LATTE.Commands.txt"
    [string] $g_logSend = "$dir\LATTE.Commands.Send.txt"
    [string] $g_logRecv = "$dir\LATTE.Commands.Recv.txt" 

    New-Item -ItemType directory -Path $dir | Out-Null
    
    # Optional - Edit spaces in output path for Invoke-Expression compatibility
    # $dir  = $dir  -replace ' ','` '

    test_latte_generate -OutDir $dir
} test_main @PSBoundParameters # Entry Point