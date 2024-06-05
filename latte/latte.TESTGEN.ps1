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
function banner {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $Msg
    )
    Write-Output "`n==========================================================================="
    Write-Output "| $Msg"
    Write-Output "==========================================================================="
} # banner()

function test_recv {
    [string] $cmd = "latte.exe -ga"
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_log
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_logRecv
    Write-Output   $cmd 
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
    Write-Output   $cmd 
} # test_send()

function test_protocol {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$false)] [String] $OutDirDefault,
        [parameter(Mandatory=$false)] [String] $OutDirOpt,
        [parameter(Mandatory=$true)] [String] $Protocol,
        [parameter(Mandatory=$true)] [String] $Iter,
        [parameter(Mandatory=$true)] [String] $Fname,
        [parameter(Mandatory=$false)] [bool]   $NoDumpParam = $false
    )
    # vary send method
    foreach ($snd in $g_Config.SendMethod) {
        for ($i=0; $i -lt $g_Config.Iterations; $i++) {
            # vary port number
            [int] $portstart = $g_Config.StartPort
            if (-Not $g_SamePort) {
                $portstart += ($i * $g_Config.Iterations)
            }
            # output optimized commands
            if ($null -ne  $g_Config.Optimized) {
                test_send -Iter $Iter -Port $portstart -Type "-$Protocol" -Snd $snd -Options $g_Config.Optimized -OutDir $OutDirOpt -Fname "$Fname.$snd.OPT.iter$i" -NoDumpParam $NoDumpParam
                test_recv
            } 
            # output default commands
            if ($null -ne  $g_Config.Default) {
                test_send -Iter $Iter -Port $portstart -Type "-$Protocol" -Snd $snd -Options $g_Config.Default -OutDir $OutDirDefault -Fname "$Fname.$snd.iter$i" -NoDumpParam $NoDumpParam
                test_recv
            }
        }
    }
}

function test_latte_generate {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $OutDir
    )
    # Normalize output directory
    $dir = $OutDir
    # create default and optimized directory if not null in config to store commands in
    $dirDefault = $null
    $dirOptimized = $null
    if ($null -ne $g_Config.Default) {
        $dirDefault = (Join-Path -Path $OutDir -ChildPath "default") 
    }
    if ($null -ne $g_Config.Optimized) {
        $dirOptimized = (Join-Path -Path $OutDir -ChildPath "optimized") 
    }

    # Transports
    foreach ($Protocol in $g_Config.Protocol) {
        # Iteration Tests capturing each transaction time
        # - Measures over input samples
        if ($g_Config.PingIterations -gt 0) {
            Write-Output "" # banner -Msg "Iteration Tests: [$Protocol] operations per bounded iterations"
            test_protocol -Iter "-i $($g_Config.PingIterations)" -Protocol $Protocol -OutDirOpt $dirOptimized -OutDirDefault $dirDefault -Fname "$Protocol.i$($g_Config.PingIterations)"
        }
        # Transactions per 10s
        # - Measures operations per bounded time.
        if ($g_Config.Time -gt 0) {
            Write-Output "" # banner -Msg "Time Tests: [$Protocol] operations per bounded time"
            test_protocol -Iter "-t $($g_Config.Time)" -Protocol $Protocol -OutDirOpt $dirOptimized -OutDirDefault $dirDefault -Fname "$Protocol.t$($g_Config.Time)" -NoDumpParam $true
        }
    }
} # test_latte_generate()

function validate_config {
    $isValid = $true
    $int_vars = @('Iterations', 'StartPort', 'Time', 'PingIterations')
    foreach ($var in $int_vars) {
        if (($null -eq $g_Config.($var)) -or ($g_Config.($var) -lt 0)) {
            Write-Output "$var is required and must be greater than or equal to 0"
            $isValid = $false
        }
    }
    $valid_protocols = @('tcp', 'udp', 'raw')
    if ($null -ne $g_Config.Protocol) {
        foreach ($proto in $g_Config.Protocol) {
            if (-Not $valid_protocols.Contains($proto)) {
                Write-Output "$proto is not a valid protocol"
                $isValid = $false
            }
        }
    } else {
        Write-Output "Protocol cannot be null"
        $isValid = $false
    }
    $valid_send = @('b', 'nb', 'ove', 'ovc', 'ovp', 'sel')
    if ($null -ne $g_Config.SendMethod) {
        foreach ($snd in $g_Config.SendMethod) {
            if (-Not $valid_send.Contains($snd)) {
                Write-Output "$snd is not a valid send method"
                $isValid = $false
            }
        }
    } else {
        Write-Output "SendMethod cannot be null"
        $isValid = $false
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
        $allConfig = Get-Content -Path "$PSScriptRoot\latte.Config.json" | ConvertFrom-Json
        [Object] $g_Config     = $allConfig.("Latte$Config")
        if ($null -eq $g_Config) {
            Write-Output "Latte$Config does not exist in .\latte\latte.Config.json. Please provide a valid config"
            Throw
        }
        if (-Not (validate_config)) {
            Write-Output "Latte$Config is not a valid config"
            Throw
        }
        [string] $g_DestIp     = $DestIp.Trim()
        [string] $g_SrcIp      = $SrcIp.Trim()
        [string] $dir          = (Join-Path -Path $OutDir -ChildPath "latte") 
        [string] $g_log        = "$dir\LATTE.Commands.txt"
        [string] $g_logSend    = "$dir\LATTE.Commands.Send.txt"
        [string] $g_logRecv    = "$dir\LATTE.Commands.Recv.txt"
        [boolean] $g_SamePort  = $SamePort.IsPresent

        New-Item -ItemType directory -Path $dir | Out-Null
        
        # Optional - Edit spaces in output path for Invoke-Expression compatibility
        # $dir  = $dir  -replace ' ','` '
        banner -Msg "Latte Tests"
        test_latte_generate -OutDir $dir
    } catch {
        Write-Output "Unable to generate LATTE commands"
        Write-Output "Exception $($_.Exception.Message) in $($MyInvocation.MyCommand.Name)"
    }
} test_main @PSBoundParameters # Entry Point