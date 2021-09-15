#===============================================
# Script Input Parameters Enforcement
#===============================================
Param(
    [parameter(Mandatory=$false)] [switch] $Diag = $false,
    [ValidateSet("Default", "Azure", "Detail", "Max")]
    [parameter(Mandatory=$false)] [string] $Config = "Default",
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
    Write-Host "  -Diag       = $Diag"
    Write-Host "  -Config     = $Config"
    Write-Host "  -DestIp     = $DestIp"
    Write-Host "  -SrcIp      = $SrcIp"
    Write-Host "  -OutDir     = $OutDir"
    Write-Host "============================================"
} # input_display()

#===============================================
# Internal Functions
#===============================================

function env_normalize {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $OutDir
    )

    $baseDir = if (-not [String]::IsNullOrWhiteSpace($OutDir)) {
                   if (Test-Path $OutDir) {
                       (Resolve-Path $OutDir).Path # full path
                   } 
                   else {
                       throw "-> The directory ""$OutDir"" does not exist."
                   }
               } 
    $workDirName = "msdbg.$env:COMPUTERNAME.perftest"

    return (Join-Path $baseDir $workDirName).TrimEnd("\")
} # env_normalize()

function env_create {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $OutDir
    )

    # Attempt to create working directory, fail gracefully otherwise
    try {
        New-Item -ItemType directory -Path $OutDir -ErrorAction Stop | Out-Null
    } catch {
        throw "-> Failed to create directory ""$OutDir"" because " + $error[0]
    }
} # env_create()

function env_destroy {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $OutDir
    )

    If (Test-Path $OutDir) {
        # Careful - Deletes $OurDir and all its contents
        Remove-Item $OutDir -Recurse -Force # Careful - Deletes $OurDir and all its contents
    }
} # env_destroy()

#===============================================
# External Functions - Main Program
#===============================================
function test_main {
    Param(
        [parameter(Mandatory=$false)] [string] $Config = "Default",
        [parameter(Mandatory=$true)]  [string] $DestIp,
        [parameter(Mandatory=$true)]  [string] $SrcIp,
        [parameter(Mandatory=$true)]  [ValidateScript({Test-Path $_ -PathType Container})] [String] $OutDir = "" ,
        [parameter(Mandatory=$false)] [switch] $Diag = $false
    )
    Clear-Host
    input_display

    $start   = Get-Date
    $version = "2020.09.13.0" # Version within date context

    Write-Host $start
    Write-Host $version

    [bool]   $g_diag      = $Diag
    [string] $g_config    = $Config
    [string] $g_DestIp    = $DestIp
    [string] $g_SrcIp     = $SrcIp

    $workDir = env_normalize -OutDir $OutDir
    Write-Host $workDir

    env_destroy -OutDir $workDir
    env_create  -OutDir $workDir


    if ($g_diag) {
        # More work needed here.  Specifically to generate the commands to file and integrate with execution.
        #.\diag\Network.Diagnosis.ps1 -DestIp $g_DestIp -SrcIp $g_SrcIp -OutDir $workDir
    }else {
        & "$PSScriptRoot\cps\cps.TESTGEN.ps1" -DestIp $g_DestIp -SrcIp $g_SrcIp -OutDir $workDir -Config $g_config
        & "$PSScriptRoot\latte\latte.TESTGEN.ps1"   -DestIp $g_DestIp -SrcIp $g_SrcIp -OutDir $workDir -Config $g_config
        & "$PSScriptRoot\ntttcp\ntttcp.TESTGEN.ps1" -DestIp $g_DestIp -SrcIp $g_SrcIp -OutDir $workDir -Config $g_config
    }
} test_main @PSBoundParameters # Entry Point

# TODO
# =============================================================
# - create a flag for command generation only
#    - If files present, user is free to edit to rerun/reexecute or loop via edits
# - create a flag for command execution only
# - Capture Get-NetView before and after Test run
# - Zip results
# =============================================================
