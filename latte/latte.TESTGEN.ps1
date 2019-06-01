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
function test_recv {
    .\latte.exe -ga # commands received from remote
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
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_log
} # test_send()

function test_latte_generate {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $OutDir
    )

    # Normalize output directory
    $dir = $OutDir

    # Send types
    [string []] $snds = @('b', 'nb', 'ove', 'ovc', 'ovp', 'sel')

    # Transports
    [string []] $soctypes = @('raw', 'tcp', 'udp')
    foreach ($soc in $soctypes) {
        # Iteration Tests
        # - Measures over input samples
        [int []] $iters = @(10000)
        if ($g_detail) { 
            $iters = @(10000, 1000000) 
        }    

        foreach ($iter in $iters) {
            foreach ($snd in $snds) {
                # Default
                test_send -Iter "-i $iter" -Type "-$soc" -Snd $snd -OutDir $dir -Fname "$soc.i$iter.$snd"
                #optimized
                test_send -Iter "-i $iter" -Type "-$soc" -Snd $snd -Options "-group 0 -rio -riopoll 100000000000" -OutDir $dir -Fname "$soc.i$iter.$snd.OPT"
            }
        }

        # Transaction Tests
        # - Measures operations per bounded time.
        [int []] $secs = @(10)
        if ($g_detail) { 
            $secs = @(10, 60) 
        }   

        foreach ($sec in $secs) {
            foreach ($snd in $snds) {
                # Default
                test_send -Iter "-t $sec" -Type "-$soc" -Snd $snd -OutDir $dir -Fname "$soc.t$sec.$snd"
                # Optimized
                test_send -Iter "-t $sec" -Type "-$soc" -Snd $snd -Options "-group 0 -rio -riopoll 100000000000" -OutDir $dir -Fname "$soc.t$sec.$snd.OPT"
            }
        }
    }
} # test_latte_generate()

<#
function test_execute {
    Param(
        [parameter(Mandatory=$true)]  [string] $Cmd,
        [parameter(Mandatory=$true)]  [string] $OutFile        
    )
        
    Write-Output "$env:USERNAME @ ${env:COMPUTERNAME}:"  | Out-File -Encoding ascii -Append $OutFile
    Write-Output "$(prompt)$cmd" | Out-File -Encoding ascii -Append $OutFile      
    Write-Host   "$cmd"
    # Redirect all output streams to file
    &{
        Write-Output $(Invoke-Expression $cmd) 
    } *>&1 | Out-File -Encoding ascii -Append $OutFile
    Write-Output "`n`n" | Out-File -Encoding ascii -Append $OutFile
} # test_execute()
#>

function test_run {
    Param(
        [parameter(Mandatory=$true)]  [ValidateScript({Test-Path $_ -PathType Container})] [String] $OutDir = "" 
    )

    [string] $execLog = "$OutDir\LATTE.Execution.Log.txt" 

    foreach ($line in Get-Content $g_log) {
        Write-Host $line
        #test_execute -Cmd $line -OutFile $execLog
    }
} # test_run()

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
    
    [bool]   $g_detail = $Detail
    [string] $g_DestIp = $DestIp
    [string] $g_SrcIp  = $SrcIp
    [string] $dir      = (Join-Path -Path $OutDir -ChildPath "latte") 
    [string] $g_log    = "$dir\LATTE.COMMANDS.txt"

    New-Item -ItemType directory -Path $dir | Out-Null
    
    # Optional - Edit spaces in output path for Invoke-Expression compatibility
    # $dir  = $dir  -replace ' ','` '

    test_latte_generate -OutDir $dir
    test_run            -OutDir $dir
} test_main @PSBoundParameters # Entry Point