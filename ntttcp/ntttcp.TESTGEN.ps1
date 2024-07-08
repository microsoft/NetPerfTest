#===============================================
# Script Input Parameters Enforcement
#===============================================
Param(
    [parameter(Mandatory=$false)] [string] $Config = "Default",
    [parameter(Mandatory=$true)]  [string] $DestIp,
    [parameter(Mandatory=$true)]  [string] $SrcIp,
    [parameter(Mandatory=$true)]  [ValidateScript({Test-Path $_ -PathType Container})] [String] $OutDir = "",
    [parameter(Mandatory=$false)] [switch] $SamePort = $false
)
$scriptName = $MyInvocation.MyCommand.Name 

function input_display {
    $g_path = Get-Location

    Write-Output "============================================"
    Write-Output "$g_path\$scriptName"
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
    [string] $cmd = "ntttcp.exe -r -m $Conn,*,$g_DestIp $proto $Options -v -wu $($g_Config.Warmup) -cd $($g_Config.Cooldown) -p $Port -t $($g_Config.Runtime) -xml $out.xml"
    Write-Output $cmd | Out-File -Encoding ascii -Append "$out.txt"
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_log
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_logRecv
    Write-Output   $cmd 

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
    [string] $cmd = "ntttcp.exe -s -m $Conn,*,$g_DestIp $proto $Options -v -wu $($g_Config.Warmup) -cd $($g_Config.Cooldown) -p $Port -t $($g_Config.Runtime) -xml $out.xml -nic $g_SrcIp"
    Write-Output $cmd | Out-File -Encoding ascii -Append "$out.txt"
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_log
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_logSend    
    Write-Output   $cmd 
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
        [int] $portstart = $g_Config.StartPort
        if (-Not $g_SamePort) {
            $portstart += ($i * $g_Config.Iterations)
        }
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
    # banner -Msg "$Proto Tests"
    $dir = (Join-Path -Path $OutDir -ChildPath $Proto) 
    New-Item -ItemType directory -Path $dir | Out-Null
    # vary on number of connections
    foreach ($Conn in $g_Config.($Proto).Connections) {
        # vary on buffer len
        foreach ($BufLen in $g_Config.($Proto).BufferLen) {
            # vary on Outstanding IO not null in config
            if (($null -ne $g_Config.($Proto).OutstandingIo) -or ($g_Config.($Proto).OutstandingIo.Count -gt 0)) {
                foreach ($Oio in $g_Config.($Proto).OutstandingIo) {
                    test_iterations -OutDir $dir -Proto $Proto -Conn $Conn -Fname "m$Conn.l$BufLen.a$Oio" -Options "$($g_Config.($Proto).Options) -l $BufLen -a $Oio"
                }
            } else {
                test_iterations -OutDir $dir -Proto $Proto -Conn $Conn -Fname "m$Conn.l$BufLen" -Options "$($g_Config.($Proto).Options) -l $BufLen"
            }
            Write-Output " "
        }
    }
} # test_protocol()

function banner {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $Msg
    )
    Write-Output "`n==========================================================================="
    Write-Output "| $Msg"
    Write-Output "==========================================================================="
} # banner()

function test_ntttcp {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $OutDir
    )
    if ($null -ne $g_Config.Tcp) {
        test_protocol -OutDir $OutDir -Proto "tcp"
    }

    if ($null -ne $g_Config.Udp) {
        test_protocol -OutDir $OutDir -Proto "udp"
    }
} # test_ntttcp()

function validate_config {
    $isValid = $true
    $int_vars = @('Iterations', 'StartPort', 'Warmup', 'Cooldown', 'Runtime')
    foreach ($var in $int_vars) {
        if (($null -eq $g_Config.($var)) -or ($g_Config.($var) -lt 0)) {
            Write-Output "$var is required and must be greater than or equal to 0"
            $isValid = $false
        }
    }
    $port_vars = @('BufferLen', 'Connections')
    $protocols = @('tcp', 'udp')
    foreach ($proto in $protocols) {
        if ($null -ne $g_Config.($proto)) {
            foreach ($var in $port_vars) {
                if ($null -eq $var) {
                    Write-Output "$var is required if $proto is present"
                    $isValid = $false
                }
                foreach ($num in $var) {
                    if ($num -le 0) {
                        Write-Output "Each $var is required to be greater than 0"
                        $isValid = $false
                    }
                }
            }
            if (($null -ne $g_Config.($proto).OutstandingIo) -and ($g_Config.($proto).OutstandingIo -gt 0)) {
                foreach ($num in $g_Config.($proto).OutstandingIo) {
                    if ($num -le 0) {
                        Write-Output "Each OutstandingIO is required to be greater than 0"
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
        [parameter(Mandatory=$true)]  [ValidateScript({Test-Path $_ -PathType Container})] [String] $OutDir = "",
        [parameter(Mandatory=$false)] [switch] $SamePort = $false
    )
    try {
        # input_display
        # get config variables
        $allConfig = Get-Content -Path "$PSScriptRoot\ntttcp.Config.json" | ConvertFrom-Json
        [Object] $g_Config     = $allConfig.("Ntttcp$Config")
        if ($null -eq $g_Config) {
            Write-Output "Ntttcp$Config does not exist in .\ntttcp\ntttcp.Config.json. Please provide a valid config"
            Throw
        }
        if (-Not (validate_config)) {
            Write-Output "Ntttcp$Config is not a valid config"
            Throw
        }
        [string] $g_DestIp     = $DestIp.Trim()
        [string] $g_SrcIp      = $SrcIp.Trim()
        [string] $dir          = (Join-Path -Path $OutDir -ChildPath "ntttcp") 
        [string] $g_log        = "$dir\NTTTCP.Commands.txt"
        [string] $g_logSend    = "$dir\NTTTCP.Commands.Send.txt"
        [string] $g_logRecv    = "$dir\NTTTCP.Commands.Recv.txt"
        [boolean] $g_SamePort  = $SamePort.IsPresent

        # Edit spaces in path for Invoke-Expression compatibility
        $dir = $dir -replace ' ','` '
        
        New-Item -ItemType directory -Path $dir | Out-Null
        #Write-Output "test_ntttcp -OutDir $dir"

        banner -Msg "NTTTCP Tests"
        test_ntttcp -OutDir $dir
    } catch {
        Write-Output "Unable to generate NTTTCP commands"
        Write-Output "Exception $($_.Exception.Message) in $($MyInvocation.MyCommand.Name)"
    }
} test_main @PSBoundParameters # Entry Point
