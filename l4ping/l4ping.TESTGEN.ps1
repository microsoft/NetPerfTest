#===============================================
# Script Input Parameters Enforcement
#===============================================
Param(
    [parameter(Mandatory=$false)] [ValidateSet("Default", "Azure", "Detail", "Max", "Container")]   [string] $Config = "Default",
    [parameter(Mandatory=$true)]  [ValidateScript({$_ -match [IPAddress]$_ })]         [string] $DestIp,
    [parameter(Mandatory=$true)]  [ValidateScript({$_ -match [IPAddress]$_ })]         [string] $SrcIp,
    [parameter(Mandatory=$true)]  [ValidateScript({Test-Path $_ -PathType Container})] [String] $OutDir,
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
        [parameter(Mandatory=$true)] [ValidateScript({-Not [String]::IsNullOrWhiteSpace($_)})] [String] $Msg
    )
    Write-Output "`n==========================================================================="
    Write-Output "| $Msg"
    Write-Output "==========================================================================="
} # banner()

function test_recv {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)]   [int] $Port,
        [parameter(Mandatory=$true)]   [int] $ClientReceiveSize,
        [parameter(Mandatory=$true)]   [int] $ClientSendSize
    )
    [string] $cmd = "l4ping.exe -s $g_DestIp`:$Port -R $ClientSendSize -S $ClientReceiveSize"
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_log
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_logRecv
    Write-Output $cmd
} # test_recv()

function test_send {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)]   [int]    $Port,
        [parameter(Mandatory=$true)]   [int]    $ClientReceiveSize,
        [parameter(Mandatory=$true)]   [int]    $ClientSendSize,
        [parameter(Mandatory=$true)]   [int]    $PingIterations,
        [parameter(Mandatory=$true)]   [String] $Percentiles,
        [parameter(Mandatory=$true)]   [String] $OutDir,
        [parameter(Mandatory=$true)]   [String] $Fname
    )

    [string] $out = (Join-Path -Path $OutDir -ChildPath $Fname)
    [string] $cmd = "l4ping.exe -c $g_DestIp`:$Port -S $ClientSendSize -R $ClientReceiveSize -m $PingIterations -p `"$Percentiles`" -o $out"

    Write-Output $cmd | Out-File -Encoding ascii -Append $g_log
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_logSend
    Write-Output $cmd
} # test_send()

function test_l4ping_generate {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $OutDir
    )
    # Normalize output directory
    $dir = $OutDir

    for ($i=0; $i -lt $g_Config.Iterations; $i++) {
        # vary port number
        [int] $port = $g_Config.StartPort
        if (-Not $g_SamePort) {
            $port += ($i * $g_Config.Iterations)
        }

        # Output receive command
        test_recv -Port $port -ClientReceiveSize $g_Config.ClientReceiveSize -ClientSendSize $g_Config.ClientSendSize

        # Output send command
        test_send -Port $port -ClientReceiveSize $g_Config.ClientReceiveSize -ClientSendSize $g_Config.ClientSendSize -PingIterations $g_Config.PingIterations -Percentiles $g_Config.Percentiles -OutDir $dir -Fname "tcp.i$($g_Config.PingIterations).iter$i.csv"
    }
} # test_l4ping_generate()

function validate_config {
    $isValid = $true
    $int_vars = @('Iterations', 'StartPort', 'ClientSendSize', 'ClientReceiveSize', 'PingIterations')
    foreach ($var in $int_vars) {
        if (($null -eq $g_Config.($var)) -or ($g_Config.($var) -le 0)) {
            Write-Host "$var is required and must be greater than 0"
            $isValid = $false
        }
    }

    foreach ($var in @('StartPort', 'ClientSendSize', 'ClientReceiveSize')) {
        if (($null -eq $g_Config.($var)) -or ($g_Config.($var) -gt 65535)) {
            Write-Host "$var is required and must be less than or equal to 65535"
            $isValid = $false
        }
    }

    if ([String]::IsNullOrWhitespace($g_Config.Percentiles))
    {
        Write-Host "Percentiles is required and must have a value"
        $isValid = $false
    }
    else
    {
        foreach ($val in $g_Config.Percentiles.Split(','))
        {
            $val = $val.Trim()
            [double] $DoubleVal = -1.0
            if (-NOT [Double]::TryParse($val, [ref]$DoubleVal))
            {
                Write-Host "Percentile values must be of type double: $val"
                $isValid = $false
            }

            if ($DoubleVal -lt 0.0)
            {
                Write-Host "Percentile values must be great than or equal to 0.0: $val"
                $isValid = $false
            }

            if ($DoubleVal -gt 1.0)
            {
                Write-Host "Percentile values must be less than or equal to 1.0: $val"
                $isValid = $false
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
        $allConfig = Get-Content -Path "$PSScriptRoot\l4ping.Config.json" | ConvertFrom-Json
        [Object] $g_Config     = $allConfig.("l4ping$Config")
        if ($null -eq $g_Config) {
            Write-Output "l4ping$Config does not exist in .\l4ping\l4ping.Config.json. Please provide a valid config"
            Throw
        }
        if (-Not (validate_config)) {
            Write-Output "l4ping$Config is not a valid config"
            Throw
        }
        [string] $g_DestIp     = $DestIp.Trim()
        [string] $g_SrcIp      = $SrcIp.Trim()
        [string] $dir          = (Join-Path -Path $OutDir -ChildPath "l4ping") 
        [string] $g_log        = "$dir\l4ping.Commands.txt"
        [string] $g_logSend    = "$dir\l4ping.Commands.Send.txt"
        [string] $g_logRecv    = "$dir\l4ping.Commands.Recv.txt"
        [boolean] $g_SamePort  = $SamePort.IsPresent

        New-Item -ItemType directory -Path $dir | Out-Null
        
        # Optional - Edit spaces in output path for Invoke-Expression compatibility
        # $dir  = $dir  -replace ' ','` '
        banner -Msg "l4ping Tests"
        test_l4ping_generate -OutDir $dir
    } catch {
        Write-Output "Unable to generate l4ping commands"
        Write-Output "Exception $($_.Exception.Message) in $($MyInvocation.MyCommand.Name)"
    }
} test_main @PSBoundParameters # Entry Point