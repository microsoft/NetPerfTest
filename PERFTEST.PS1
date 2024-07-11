#===============================================
# Script Input Parameters Enforcement
#===============================================
Param( 
    [parameter(Mandatory=$true)]  [string] $SrcIp, 
    [parameter(Mandatory=$true)]  [string] $DestIp,
    [parameter(Mandatory=$true)]  [ValidateScript({Test-Path $_ -PathType Container})] [String] $OutDir = "",
    [ValidateSet("Default", "Azure", "Detail", "Max", "Container")]
    [parameter(Mandatory=$false)] [string] $Config = "Default",
    [parameter(Mandatory=$false)]  [Array] $ToolList = @("ntttcp", "latte", "l4ping", "cps", "ctstraffic", "ncps", "secnetperf"),
    [parameter(Mandatory=$false)] [switch] $SamePort = $false
)

$scriptName = $MyInvocation.MyCommand.Name 
$SupportedTools = @("ntttcp", "latte", "l4ping", "cps", "ctstraffic", "ncps", "secnetperf")
$start   = Get-Date
$version = "2020.09.13.0" # Version within date context



function input_display {
    $g_path = Get-Location

    Write-Output "============================================"
    Write-Output "$g_path\$scriptName"
    Write-Output " Date: $start"
    Write-Output " Version: $version" 
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


function normalize_toollist {
    Param(
        [Parameter(Mandatory=$true)] [Array] $ToolList
    )

    for ($i = 0; $i -lt $ToolList.Count; $i += 1) {
        $ToolList[$i] = $ToolList[$i].ToLower()
        if (-not ($ToolList[$i] -in $SupportedTools)) {
            $toolstr = ""
            foreach ($tool in $SupportedTools) {$toolstr += "`t$tool`n"}
            Write-Error "NPT does not support the tool: $($ToolList[$i])`nSupported Tools:`n$($toolstr)"
            Exit 
        }
    }

    return $ToolList
}

#===============================================
# External Functions - Main Program
#===============================================
function test_main {
    Param(
        [parameter(Mandatory=$false)] [string] $Config = "Default",
        [parameter(Mandatory=$true)]  [string] $DestIp,
        [parameter(Mandatory=$true)]  [string] $SrcIp,
        [parameter(Mandatory=$true)]  [ValidateScript({Test-Path $_ -PathType Container})] [String] $OutDir = "" ,
        [parameter(Mandatory=$false)] [Array] $ToolList,
        [parameter(Mandatory=$false)] [switch] $SamePort = $false
    )
    
    if (-not $silent) {input_display}

    [string] $g_config    = $Config
    [string] $g_DestIp    = $DestIp
    [string] $g_SrcIp     = $SrcIp

    $workDir = env_normalize -OutDir $OutDir 

    env_destroy -OutDir $workDir
    env_create  -OutDir $workDir

    $ToolList = normalize_toollist -ToolList $ToolList
    
    if ("ctstraffic" -in $ToolList) {
        & "$PSScriptRoot\ctsTraffic\ctsTraffic.TESTGEN.ps1" -DestIp $g_DestIp -SrcIp $g_SrcIp -OutDir $workDir -Config $g_config -SamePort:$SamePort.IsPresent
    }
    if ("cps" -in $ToolList) {
        & "$PSScriptRoot\cps\cps.TESTGEN.ps1" -DestIp $g_DestIp -SrcIp $g_SrcIp -OutDir $workDir -Config $g_config -SamePort:$SamePort.IsPresent
    }
    if ("latte" -in $ToolList) {
        & "$PSScriptRoot\latte\latte.TESTGEN.ps1"   -DestIp $g_DestIp -SrcIp $g_SrcIp -OutDir $workDir -Config $g_config -SamePort:$SamePort.IsPresent
    }
    if ("l4ping" -in $ToolList) {
        & "$PSScriptRoot\l4ping\l4ping.TESTGEN.ps1" -DestIp $g_DestIp -SrcIp $g_SrcIp -OutDir $workDir -Config $g_config -SamePort:$SamePort.IsPresent
    }
    if ("ntttcp" -in $ToolList) {
        & "$PSScriptRoot\ntttcp\ntttcp.TESTGEN.ps1" -DestIp $g_DestIp -SrcIp $g_SrcIp -OutDir $workDir -Config $g_config -SamePort:$SamePort.IsPresent
    } 
    if ("ncps" -in $ToolList) {
        & "$PSScriptRoot\ncps\ncps.TESTGEN.ps1" -DestIp $g_DestIp -SrcIp $g_SrcIp -OutDir $workDir -Config $g_config -SamePort:$SamePort.IsPresent
    }   
    if ("secnetperf" -in $ToolList) {
        & "$PSScriptRoot\secnetperf\secnetperf.TESTGEN.ps1" -DestIp $g_DestIp -SrcIp $g_SrcIp -OutDir $workDir -Config $g_config -SamePort:$SamePort.IsPresent
    }   
    
    
} test_main -Config $Config -DestIp $DestIp -SrcIp $SrcIp -OutDir $OutDir -ToolList $ToolList



# TODO
# =============================================================
# - create a flag for command generation only
#    - If files present, user is free to edit to rerun/reexecute or loop via edits
# - create a flag for command execution only
# - Capture Get-NetView before and after Test run
# - Zip results
# =============================================================
