#===============================================
# Script Input Parameters Enforcement
#===============================================
Param(
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
    Write-Host "  -DestIp = $DestIp"
    Write-Host "  -SrcIp  = $SrcIp"
    Write-Host "  -OutDir = $OutDir"
    Write-Host "============================================"
} # input_display()

#===============================================
# Internal Functions
#===============================================
function test_execute {
    Param(
        [parameter(Mandatory=$true)]  [string] $Cmd
    )
    
    Write-Output "$env:USERNAME @ ${env:COMPUTERNAME}:"  | Out-File -Encoding ascii -Append $g_log
    Write-Output "$(prompt)$cmd" | Out-File -Encoding ascii -Append $g_log      
    Write-Host   "$cmd"
    # Redirect all output streams to file
    &{
        Write-Output $(Invoke-Expression $cmd) 
    } *>&1 | Out-File -Encoding ascii -Append $g_log
    Write-Output "`n`n" | Out-File -Encoding ascii -Append $g_log
} # test_execute()

function test_conn {
    Param(
        [parameter(Mandatory=$true)]  [ValidateScript({Test-Path $_ -PathType Container})] [String] $OutDir = "" 
    )

    [string []] $cmds = "Test-NetConnection $g_DestIp -ConstrainSourceAddress $g_SrcIp -DiagnoseRouting -InformationLevel Detailed",
                        "Test-NetConnection $g_DestIp -TraceRoute -InformationLevel Detailed",
                        "Test-NetConnection $g_DestIp -CommonTCPPort SMB -InformationLevel Detailed",
                        "Test-NetConnection $g_DestIp -CommonTCPPort RDP -InformationLevel Detailed",
                        "Test-NetConnection $g_DestIp -CommonTCPPort HTTP -InformationLevel Detailed",
                        "Test-NetConnection $g_DestIp -CommonTCPPort WINRM -InformationLevel Detailed"
    foreach ($cmd in $cmds) {
        test_execute -Cmd $cmd
    }
} # test_conn()

function test_manager {
    Param(
        [parameter(Mandatory=$true)]  [ValidateScript({Test-Path $_ -PathType Container})] [String] $OutDir = "" 
    )
    
    # Expand groups of tetss here.
    test_conn -OutDir $OutDir
} # test_manager()

#===============================================
# External Functions - Main Program
#===============================================
function test_main {
    Param(
        [parameter(Mandatory=$true)]  [string] $DestIp,
        [parameter(Mandatory=$true)]  [string] $SrcIp,
        [parameter(Mandatory=$true)]  [ValidateScript({Test-Path $_ -PathType Container})] [String] $OutDir = "" 
    )
    input_display

    [string] $g_DestIp = $DestIp
    [string] $g_SrcIp  = $SrcIp
    [string] $dir      = (Join-Path -Path $OutDir -ChildPath "diag") 
    [string] $g_log    = "$dir\Network.Diagnosis.txt"

    # Edit spaces in path for Invoke-Expression compatibility
    $g_base = $g_base -replace ' ','` '
    $dir    = $dir    -replace ' ','` '

    New-Item -ItemType directory -Path $dir | Out-Null
    test_manager -OutDir $OutDir
} test_main @PSBoundParameters # Entry Point

# Feature Requests:
# for a given IP target...
# RTT to DNS, DHCP (if enabled), GW
#  - Get Hostnames or IPs and ping each
#  - repeat for each entry in Tracetroute output
# Consider executing Get-NetView as a child