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
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)]   [Int]    $Conn,
        [parameter(Mandatory=$false)]  [string] $Proto,
        [parameter(Mandatory=$true)]   [String] $OutDir,
        [parameter(Mandatory=$true)]   [String] $Fname
    )

    [string] $out = (Join-Path -Path $OutDir -ChildPath "$Fname")
    [string] $cmd = "ntttcp.exe -r -m $Conn,*,$g_DestIp $proto -v -wu $g_ptime -cd $g_ptime -sp -p 50001 -t $g_runtime -xml $out.xml"
    Write-Output $cmd | Out-File -Encoding ascii -Append "$out.txt"
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_log
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_logRecv
    Write-Host   $cmd 
} # test_recv()

function test_send {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)]   [Int]    $Conn,
        [parameter(Mandatory=$false)]  [string] $Proto,
        [parameter(Mandatory=$true)]   [String] $OutDir,
        [parameter(Mandatory=$true)]   [String] $Fname
    )

    [string] $out = (Join-Path -Path $OutDir -ChildPath "$Fname")
    [string] $cmd = "ntttcp.exe -s -m $Conn,*,$g_DestIp $proto -v -wu $g_ptime -cd $g_ptime -sp -p 50001 -t $g_runtime -xml $out.xml -nic $g_SrcIp"
    Write-Output $cmd | Out-File -Encoding ascii -Append "$out.txt"
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_log
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_logSend    
    Write-Host   $cmd 
} # test_send()

function test_udp {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $OutDir,
        [parameter(Mandatory=$true)] [Int]    $Conn
    )

    [string] $udpstr = "-u"
    test_recv -Conn $Conn -Proto $udpstr -OutDir $OutDir -Fname "udp.recv.m$Conn"
    test_send -Conn $Conn -Proto $udpstr -OutDir $OutDir -Fname "udp.send.m$Conn"
} # test_udp()

function test_tcp {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $OutDir,
        [parameter(Mandatory=$true)] [Int]    $Conn
    )

    # NTTTCP outstanding IO ^2 scaling. Min -> Default (2) -> MAX supported.
    # - Finds optimial outstanding IO scaling value per BW
    [int]   $OutIoDflt = 2
    [int]   $OutIoMax  = 63    
    [int[]] $OutIoList = @($OutIoDflt, 16)
    if ($g_detail) {
        $OutIoList  = @(1, 2, 4, 8, 16, 32, $OutIoMax)
    }

    foreach ($Oio in $OutIoList) {
        [string] $tcpstr = "-a $Oio -w"
        test_recv -Conn $Conn -Proto $tcpstr -OutDir $OutDir -Fname "tcp.recv.m$Conn.a$Oio"
        test_send -Conn $Conn -Proto $tcpstr -OutDir $OutDir -Fname "tcp.send.m$Conn.a$Oio"
        Write-Host " "
    }
} # test_tcp()

function banner {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $Msg
    )

    Write-Host "==========================================================================="
    Write-Host "| $Msg"
    Write-Host "==========================================================================="
} # banner()

function test_ntttcp {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $OutDir
    )

    # execution time in seconds
    [int] $g_runtime = 10
    [int] $g_ptime   = 2

    # NTTTCP ^2 connection scaling to MAX supported.
    [int]   $ConnMax  = 128 # NTTTCP maximum connections is 999.
    [int[]] $ConnList = @(1, 64)
    if ($g_detail) {
        $ConnList = @(1, 2, 4, 8, 16, 32, 64, $ConnMax)
    }

    [string] $dir = $OutDir
    # Separate loops simply for output readability
    banner -Msg "TCP Tests"
    $dir = (Join-Path -Path $OutDir -ChildPath "tcp") 
    New-Item -ItemType directory -Path $dir | Out-Null
    foreach ($Conn in $ConnList) {
        test_tcp -Conn $Conn -OutDir $dir
        Write-Host " "
    }

    banner -Msg "UDP Tests"
    $dir = (Join-Path -Path $OutDir -ChildPath "udp") 
    New-Item -ItemType directory -Path $dir | Out-Null
    foreach ($Conn in $ConnList) {
        test_udp -Conn $Conn -OutDir $dir
        Write-Host " "
    }
} # test_ntttcp()

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
    [string] $g_DestIp  = $DestIp.Trim()
    [string] $g_SrcIp   = $SrcIp.Trim()
    [string] $dir       = (Join-Path -Path $OutDir -ChildPath "ntttcp") 
    [string] $g_log     = "$dir\NTTTCP.Commands.txt"
    [string] $g_logSend = "$dir\NTTTCP.Commands.Send.txt"
    [string] $g_logRecv = "$dir\NTTTCP.Commands.Recv.txt"

    # Edit spaces in path for Invoke-Expression compatibility
    $dir = $dir -replace ' ','` '
    
    New-Item -ItemType directory -Path $dir | Out-Null
    test_ntttcp -OutDir $dir
} test_main @PSBoundParameters # Entry Point
