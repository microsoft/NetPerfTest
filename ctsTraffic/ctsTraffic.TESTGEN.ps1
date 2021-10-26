#===============================================
# Script Input Parameters Enforcement
#===============================================
Param(
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
        [parameter(Mandatory=$true)]   [String] $Fname,
        [parameter(Mandatory=$true)]   [String] $Options
    )

    [string] $out = (Join-Path -Path $OutDir -ChildPath "$Fname")
    [string] $cmd = "ctstraffic.exe -listen:$g_DestIp -Port:$Port -verify:connection -transfer:0xffffffffffffffff -msgwaitall:on -io:rioiocp $Options"
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
        [parameter(Mandatory=$true)]   [String] $Fname,
        [parameter(Mandatory=$true)]   [String] $Options
    )

    [string] $out = (Join-Path -Path $OutDir -ChildPath "$Fname")
    [string] $cmd = "ctstraffic.exe -bind:$g_SrcIp -target:$g_DestIp -Port:$Port -connections:$Conn -timeLimit:$(1000 * [Int]$g_Config.Runtime) -verify:connection -transfer:0xffffffffffffffff -msgwaitall:on -io:rioiocp -statusfilename:$out.csv $Options"
    Write-Output $cmd | Out-File -Encoding ascii -Append "$out.txt"
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_log
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_logSend    
    Write-Host   $cmd 
} # test_send()

function test_iterations {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $OutDir,
        [parameter(Mandatory=$true)] [String] $Proto,
        [parameter(Mandatory=$true)]   [Int]    $Conn,
        [parameter(Mandatory=$true)]   [String] $Fname,
        [parameter(Mandatory=$true)]   [String] $Options
    )
    $protoParam = if ($Proto -eq "udp") {"-u"} else {""};
    for ($i=0; $i -lt $g_Config.Iterations; $i++) {
        # vary on port number
        [int] $portstart = $g_Config.StartPort + ($i * $g_Config.Iterations)
        test_recv -Conn $Conn -Port $portstart -Proto $protoParam -OutDir $OutDir -Fname "$Proto.recv.$Fname.iter$i" -Options $Options 
        test_send -Conn $Conn -Port $portstart -Proto $protoParam -OutDir $OutDir -Fname "$Proto.send.$Fname.iter$i" -Options $Options
    }
} # test_iterations()

function test_protocol {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $OutDir,
        [parameter(Mandatory=$true)] [String] $Proto 
    )
    banner -Msg "$Proto Tests"
    $dir = (Join-Path -Path $OutDir -ChildPath $Proto) 
    New-Item -ItemType directory -Path $dir | Out-Null
    # vary on number of connections
    foreach ($Conn in $g_Config.($Proto).Connections) {
        # vary on buffer len
        foreach ($BufLen in $g_Config.($Proto).BufferLen) {
            # vary on Outstanding IO not null in config
            test_iterations -OutDir $dir -Proto $Proto -Conn $Conn -Fname "m$Conn.l$BufLen" -Options "$($g_Config.($Proto).Options) -buffer:$BufLen -statusUpdate:1000"
            Write-Host " "
        }
    }
} # test_protocol()

function banner {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $Msg
    )
    Write-Host "==========================================================================="
    Write-Host "| $Msg"
    Write-Host "==========================================================================="
} # banner()

function test_ctsTraffic {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $OutDir
    )
    if ($null -ne $g_Config.Tcp) {
        test_protocol -OutDir $OutDir -Proto "tcp"
    }
} # test_ntttcp()

function validate_config {
    $isValid = $true
    $int_vars = @('Iterations', 'StartPort', 'Runtime')
    foreach ($var in $int_vars) {
        if (($null -eq $g_Config.($var)) -or ($g_Config.($var) -lt 0)) {
            Write-Host "$var is required and must be greater than or equal to 0"
            $isValid = $false
        }
    }
    $port_vars = @('BufferLen', 'Connections')
    $protocols = @('tcp')
    foreach ($proto in $protocols) {
        if ($null -ne $g_Config.($proto)) {
            foreach ($var in $port_vars) {
                if ($null -eq $var) {
                    Write-Host "$var is required if $proto is present"
                    $isValid = $false
                }
                foreach ($num in $var) {
                    if ($num -le 0) {
                        Write-Host "Each $var is required to be greater than 0"
                        $isValid = $false
                    }
                }
            }
        }
    }
    return $isValid
} # validate_config()

#===============================================
# External Functions - Main Program
#===============================================
function test_main {
    Param(
        [parameter(Mandatory=$false)] [string] $Config = "Default",
        [parameter(Mandatory=$true)]  [string] $DestIp,
        [parameter(Mandatory=$true)]  [string] $SrcIp,
        [parameter(Mandatory=$true)]  [ValidateScript({Test-Path $_ -PathType Container})] [String] $OutDir = "" 
    )
    try {
        input_display
        # get config variables
        $allConfig = Get-Content -Path "$PSScriptRoot\ctsTraffic.Config.json" | ConvertFrom-Json
        [Object] $g_Config     = $allConfig.("CtsTraffic$Config")
        if ($null -eq $g_Config) {
            Write-Host "CtsTraffic$Config does not exist in .\ctsTraffic\ctsTraffic.Config.json. Please provide a valid config"
            Throw
        }
        if (-Not (validate_config)) {
            Write-Host "CtsTraffic$Config is not a valid config"
            Throw
        }
        
        [string] $g_DestIp     = $DestIp.Trim()
        [string] $g_SrcIp      = $SrcIp.Trim()
        [string] $dir          = (Join-Path -Path $OutDir -ChildPath "ctsTraffic") 
        [string] $g_log        = "$dir\CtsTraffic.Commands.txt"
        [string] $g_logSend    = "$dir\CtsTraffic.Commands.Send.txt"
        [string] $g_logRecv    = "$dir\CtsTraffic.Commands.Recv.txt"

        # Edit spaces in path for Invoke-Expression compatibility
        $dir = $dir -replace ' ','` '
        
        New-Item -ItemType directory -Path $dir | Out-Null
        Write-Host "test_ctsTraffic -OutDir $dir"

        test_ctsTraffic -OutDir $dir
    } catch {
        Write-Host "Unable to generate CtsTraffic commands"
        Write-Host "Exception $($_.Exception.Message) in $($MyInvocation.MyCommand.Name)"
    }
} test_main @PSBoundParameters # Entry Point
