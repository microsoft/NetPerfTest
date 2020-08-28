#===============================================
# Script Input Parameters Enforcement
#===============================================
Param(
    [parameter(Mandatory=$false)] [switch] $Detail = $false,
    [parameter(Mandatory=$false)] [Int]    $Iterations = 1,
    [parameter(Mandatory=$false)] [ValidateSet('Sampling','Testing')] [string] $Config = "Sampling",
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
    Write-Host "  -Iterations = $Iterations"
    Write-Host "  -Config     = $Config"
    Write-Host "  -DestIp     = $DestIp"
    Write-Host "  -SrcIp      = $SrcIp"
    Write-Host "  -OutDir     = $OutDir"
    Write-Host "============================================"
} # input_display()

#===============================================
# Internal Functions
#===============================================
function test_recv {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)]   [Int]    $Conn,
        [parameter(Mandatory=$true)]   [Int]    $Port,
        [parameter(Mandatory=$false)]  [string] $Proto,
        [parameter(Mandatory=$true)]   [String] $OutDir,
        [parameter(Mandatory=$true)]   [String] $Fname
    )

    [string] $out = (Join-Path -Path $OutDir -ChildPath "$Fname")
    [string] $cmd = "ntttcp.exe -r -m $Conn,*,$g_DestIp $proto -v -wu $g_ptime -cd $g_ptime -sp -p $Port -t $g_runtime -xml $out.xml"
    Write-Output $cmd | Out-File -Encoding ascii -Append "$out.txt"
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_log
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_logRecv
    Write-Host   $cmd 

} # test_recv()

function test_send {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)]   [Int]    $Conn,
        [parameter(Mandatory=$true)]   [Int]    $Port,
        [parameter(Mandatory=$false)]  [string] $Proto,
        [parameter(Mandatory=$true)]   [String] $OutDir,
        [parameter(Mandatory=$true)]   [String] $Fname
    )

    [string] $out = (Join-Path -Path $OutDir -ChildPath "$Fname")
    [string] $cmd = "ntttcp.exe -s -m $Conn,*,$g_DestIp $proto -v -wu $g_ptime -cd $g_ptime -sp -p $Port -t $g_runtime -xml $out.xml -nic $g_SrcIp"
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
    
    [int]    $tmp    = 50000
    [int]    $BufLen = 1472
    [string] $udpstr = "-u -l $BufLen"
    for ($i=0; $i -lt $g_iters; $i++) {
        [int] $portstart = $tmp + ($i * $g_iters)
        test_recv -Conn $Conn -Port $portstart -Proto $udpstr -OutDir $OutDir -Fname "udp.recv.m$Conn.l$BufLen.iter$i"
        test_send -Conn $Conn -Port $portstart -Proto $udpstr -OutDir $OutDir -Fname "udp.send.m$Conn.l$BufLen.iter$i"
    }
} # test_udp()

function test_tcp {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $OutDir,
        [parameter(Mandatory=$true)] [Int]    $Conn
    )

    # NTTTCP outstanding IO ^2 scaling. Min -> Default (2) -> MAX supported.
    # - Finds optimial outstanding IO scaling value per BW
    [int[]] $OutIoList  = @(2, 16) #default is 2, see ntttcp -help
    [int[]] $BufLenList = @(64)    #default is 64K, see ntttcp -help
    if ($g_detail) {
        $OutIoList  = @(2, 4, 8, 16, 32, 63) # max is 63, see ntttcp -help
        $BufLenList = @(4, 64, 256)          # Azure requested values
    }

    foreach ($BufLen in $BufLenList) {
        foreach ($Oio in $OutIoList) {
            [string] $tcpstr = "-a $Oio -w -l $BufLen"
            [int]    $tmp    = 50000
            for ($i=0; $i -lt $g_iters; $i++) {
                [int] $portstart = $tmp + ($i * $g_iters)
                test_recv -Conn $Conn -Port $portstart -Proto $tcpstr -OutDir $OutDir -Fname "tcp.recv.m$Conn.l$BufLen.a$Oio.iter$i"
                test_send -Conn $Conn -Port $portstart -Proto $tcpstr -OutDir $OutDir -Fname "tcp.send.m$Conn.l$BufLen.a$Oio.iter$i"
            }
            Write-Host " "
        }
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
        [parameter(Mandatory=$true)] [String] $OutDir,
        [parameter(Mandatory=$true)] [ValidateScript({Test-Path $_})] [String] $ConfigFile
    )

    #Load the variables needed to generate the commands
    # execution time in seconds
    [int] $g_runtime = 10
    [int] $g_ptime   = 2

    # execution time ($g_runtime) in seconds, wu, cd times ($g_ptime) will come from the Config ps1 file, if specified and take precedence over defaults 
    Try
    {
        . .\$ConfigFile
    }
    Catch
    {
        Write-Host "$ConfigFile will not be used. Exception $($_.Exception.Message) in $($MyInvocation.MyCommand.Name)"
    }

    # NTTTCP ^2 connection scaling to MAX supported.
    [int]   $ConnMax  = 512 # NTTTCP maximum connections is 999.
    [int[]] $ConnList = @(1, 64)
    if ($g_detail) {
        $ConnList = @(1, 2, 4, 8, 16, 32, 64, 128, 256, $ConnMax)
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
        [parameter(Mandatory=$false)] [Int]    $Iterations = 1,
        [parameter(Mandatory=$false)] [ValidateSet('Sampling','Testing')] [string] $Config = "Sampling",
        [parameter(Mandatory=$true)]  [string] $DestIp,
        [parameter(Mandatory=$true)]  [string] $SrcIp,
        [parameter(Mandatory=$true)]  [ValidateScript({Test-Path $_ -PathType Container})] [String] $OutDir = "" 
    )
    input_display

    [int]    $g_iters      = $Iterations
    [bool]   $g_detail     = $Detail
    [string] $g_DestIp     = $DestIp.Trim()
    [string] $g_SrcIp      = $SrcIp.Trim()
    [string] $dir          = (Join-Path -Path $OutDir -ChildPath "ntttcp") 
    [string] $g_log        = "$dir\NTTTCP.Commands.txt"
    [string] $g_logSend    = "$dir\NTTTCP.Commands.Send.txt"
    [string] $g_logRecv    = "$dir\NTTTCP.Commands.Recv.txt"
    [string] $g_ConfigFile = ".\ntttcp\NTTTCP.$Config.Config.ps1"

    # Edit spaces in path for Invoke-Expression compatibility
    $dir = $dir -replace ' ','` '
    
    New-Item -ItemType directory -Path $dir | Out-Null
    Write-Host "test_ntttcp -OutDir $dir -ConfigFile $g_ConfigFile"

    test_ntttcp -OutDir $dir -ConfigFile $g_ConfigFile
} test_main @PSBoundParameters # Entry Point
