<#
.SYNOPSIS
    This function generates network performance monitoring commands and executes
    them at the specified endpoints. 

.PARAMETER DestIp
    Required Parameter. The IP Address of the machine which will receive network 
    traffic throughout the duration of network performance tests.

.PARAMETER DestIpUserName
    Required Parameter. The domain\username needed to connect to DestIp Machine

.PARAMETER DestIpPassword
    Required Parameter. The password needed to connect to DestIp Machine. 
    Password will be stored as Secure String and chars will not be displayed 
    on the console.

.PARAMETER SrcIp
    Required Parameter. The IP Address of the machine from which network traffic 
    will originate throughout the duration of network performance tests.

.PARAMETER SrcIpUserName
    Required Parameter. The domain\username needed to connect to SrcIp Machine

.PARAMETER SrcIpPassword
    Required Parameter. The password needed to connect to SrcIp Machine. 
    Password will be stored as Secure String and chars will not be displayed on the console

.PARAMETER Config
    Specifies the profile used to generate commands. Profiles specify the duration of 
    generated commands, the parameter values to sweep through across commands, and the 
    number of iterations for each command.  

.PARAMETER ToolList 
    Specifies the tools which NPT should generate and execute commands for. 

.PARAMETER TransmitEventsLocally
    Optional switch to enable the transmission of event log entries to the local 
    computer. These event logs can be used to synchronize other tools with NPT commands.

.PARAMETER TransmitEventsRemotely
    Optional switch to enable the transmission of event log entries to a remote 
    computer. These event logs can be used to synchronize other tools with NPT commands.

.PARAMETER TransmitIP
    Mandatory (when run with TransmitEventsRemotely switch enabled) parameter used 
    to specify the IP address of the machine which should receive event log transmissions. 

.PARAMETER TransmitUserName
    Mandatory (when run with TransmitEventsRemotely switch enabled) parameter. 
    Gets domain\username needed to connect to TransmitIp Machine 

.PARAMETER TransmitPassword
    Mandatory (when run with TransmitEventsRemotely switch enabled) parameter. 
    Gets password needed to connect to TansmitIp Machine. Password will be stored 
    as Secure String and chars will not be displayed on the console.
    
.DESCRIPTION
    NOTE: Please run SetupTearDown.ps1 -Setup on the DestIp and SrcIp machines 
    before running this script to ensure PSRemoting is enabled at both endpoints. 

    This script first calls PERFTEST.ps1 to generate commands for various network 
    performance tools, as specified in the provided config profile. Next, this 
    script calls the ProcessCommands function to execute the generated commands. 
    Lastly, the script copies the output to a dedicated folder at \NetPerfTest\output.  
#>
Param(
    [parameter(Mandatory=$true)]  
    [string] $DestIp,

    [Parameter(Mandatory=$True, Position=0, HelpMessage="Dest Machine Username?")]
    [string] $DestIpUserName,

    [Parameter(Mandatory=$True, Position=0, HelpMessage="Dest Machine Password?")]
    [SecureString] $DestIpPassword,

    [parameter(Mandatory=$true)]  
    [string] $SrcIp,  

    [Parameter(Mandatory=$True, Position=0, HelpMessage="Src Machine Username?")]
    [string] $SrcIpUserName,

    [Parameter(Mandatory=$True, Position=0, HelpMessage="Src Machine Password?")]
    [SecureString]$SrcIpPassword,

    [ValidateSet("Default", "Azure", "Detail", "Max")]
    [parameter(Mandatory=$false)] 
    [string] $Config = "Default",

    [parameter(Mandatory=$false)]  
    [Array] $ToolList = @("ntttcp", "latte", "cps", "ctstraffic", "ncps", "secnetperf", "l4ping"),

    [Parameter(Mandatory=$false, ParameterSetName="Transmit")] 
    [Switch] $TransmitEventsLocally,

    [Parameter(Mandatory=$True, ParameterSetName="RemoteTransmit")] 
    [Switch] $TransmitEventsRemotely,

    [Parameter(Mandatory=$True, ParameterSetName="RemoteTransmit")] 
    [String] $TransmitIP,

    [Parameter(Mandatory=$True, ParameterSetName="RemoteTransmit")] 
    [String] $TransmitUserName,

    [Parameter(Mandatory=$True, ParameterSetName="RemoteTransmit")] 
    [SecureString] $TransmitPassword
)

$nptDir = [System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Definition)
$commandsDir = "$nptDir\commands" 

# Create commands directory and generate commands
$perftestCmd = "$($nptDir)\PERFTEST.PS1" 
$null = New-Item -Force -Type Directory $commandsDir
$null = & $perftestcmd -SrcIP $SrcIp -DestIp $DestIp -OutDir $commandsDir -Config $Config -ToolList $ToolList

$commandsDir = "$($commandsDir)\msdbg.$env:COMPUTERNAME.perftest"


# Execute commands using ProcessCommands function
Import-Module "$($nptDir)\runPerftool.psm1" -Force
$ProcessCommandsParams = @{
    "SrcIp"                 = $SrcIp
    "SrcIpUsername"         = $SrcIpUserName
    "SrcIPPassword"         = $SrcIpPassword
    "DestIp"                = $DestIp   
    "DestIpUsername"        = $DestIpUserName
    "DestIPPassword"        = $DestIpPassword
    "CommandsDir"           = $commandsDir
}

if ($TransmitEventsLocally) {
    ProcessCommands @ProcessCommandsParams -TransmitEventsLocally
} 
elseif ($TransmitEventsRemotely) {
    ProcessCommands @ProcessCommandsParams -TransmitEventsRemotely -TransmitIP $TransmitIP -TransmitUserName $TransmitUserName -TransmitPassword $TransmitPassword
} 
else {
    ProcessCommands @ProcessCommandsParams
} 

# Move results to output directory
$null = New-Item -Force -Type Directory "$($nptDir)\output"
$null = Remove-Item -Force "$($nptDir)\output\*"
foreach ($item in Get-Item "$($commandsDir)\*") {
    if ($item.Name -match ".zip" -or $item.Name -match ".log") {
        Move-Item -Path "$($commandsDir)\$($item.Name)" -Destination "$($nptDir)\output\$($item.Name)" -Force
    }
}

Write-Host "Saved output to : $($nptDir)\output"
