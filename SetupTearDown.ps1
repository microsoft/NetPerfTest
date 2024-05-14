<#
.SYNOPSIS
    Set up (or clean up) PSRemoting on this computer. Setup up option will Enable-PSRemoting and setup the machine to be able to run ps commands programmatically
    Cleanup up option will Disable-PSRemoting and perform other tasks that were done during setup like disable WinRM service, delete remoting specific firewall rules, etc.

.PARAMETER Setup
    This Switch will trigger the setup calls which ends up enabling PS Remoting (and which in turn starts the WinRM service and opens up remoting via the firewall

.PARAMETER Cleanup
    This switch triggers the cleanup path which disables WinRM service, removes the firewall rules that were created earlier for remoting, and also Disables PSRemoting

.PARAMETER SetupSshRemotingClient
    This switch triggers the setup calls which end up enabling PS Remoting over SSH on the client machine (this is typically the NPT orchestrator machine)

.PARAMETER PrivateKeyPath
    The file path to the SSH private key file (e.g. '$env:USERPROFILE\.ssh\id_ed25519')

.PARAMETER SetupSshRemotingServer
    This switch triggers the setup calls which end up enabling PS Remoting over SSH on a server machine (installing and configurating OpenSSH server and PowerShell 7)

.PARAMETER AuthorizedKey
    The SSH public key from the client machine. This should be the key that matches the private key configured on the client.
    For example, if the private key is $env:USERPROFILE\.ssh\id_ed25519, then you can obtain the public key by running 'Get-Content -Path $env:USERPROFILE\.ssh\id_ed25519.pub')

.DESCRIPTION
    Run this script to setup your machine for PS Remoting so that you can leverage the functionality of runPerfTool.psm1
    Run this script at the end of the tool runs to restore state on the machines.
    Ex: SetupTearDown.ps1 -Setup or SetupTearDown.ps1 -Cleanup
#>

Param(
    [Parameter(Mandatory=$True, ParameterSetName="Setup")]
    [switch] $Setup,

    [Parameter(Mandatory=$True, ParameterSetName="Cleanup")]
    [switch] $Cleanup,

    [Parameter(Mandatory=$True, ParameterSetName="SetupSshRemotingClient")]
    [switch] $SetupSshRemotingClient,

    [ValidateScript({Test-Path $_ -PathType Leaf})]
    [Parameter(Mandatory=$True, ParameterSetName="SetupSshRemotingClient")]
    [string] $PrivateKeyPath,
    
    [Parameter(Mandatory=$True, ParameterSetName="SetupSshRemotingServer")]
    [switch] $SetupSshRemotingServer,
    
    [ValidateScript({-Not [String]::IsNullOrWhiteSpace($_)})]
    [Parameter(Mandatory=$True, ParameterSetName="SetupSshRemotingServer")]
    [string] $AuthorizedKey
)


Function SetupRemoting{

    Write-Host "Enabling PSRemoting on this computer..."

    netsh advfirewall firewall add rule name="Windows Remote Management (HTTP-In)" dir=in action=allow service=any enable=yes profile=any localport=5985 protocol=tcp
    Enable-PSRemoting -SkipNetworkProfileCheck -Force -ErrorAction Ignore
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value '*' -Force

} # SetupRemoting()

Function SetupSshRemotingClient{
param(
    [Parameter(Mandatory=$True)] [string]$PrivateKeyPath
)

    Write-Host "Enabling SSH Remoting on host computer..."

    Write-Host "`nConfigure SSH-Agent with Private Key"
    Get-Service ssh-agent | Set-Service -StartupType Automatic
    Start-Service ssh-agent
    ssh-add $PrivateKeyPath

    if (-NOT (Test-Path "$env:ProgramFiles\PowerShell\7\"))
    {
        Write-Host "`nInstall PowerShell"
        Invoke-WebRequest https://github.com/PowerShell/PowerShell/releases/download/v7.4.0/PowerShell-7.4.0-win-x64.msi -OutFile "$env:Temp\PowerShell-7.4.0-win-x64.msi"
        msiexec.exe /package "$env:Temp\PowerShell-7.4.0-win-x64.msi" /quiet ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1 USE_MU=1 ENABLE_MU=1 ADD_PATH=1
    }
    else
    {
        Write-Host "`nPowerShell 7 already installed"
    }

    Write-Host "`nDone"

} # SetupSshRemotingClient()


Function SetupSshRemotingServer{
param(
    [Parameter(Mandatory=$True)] [string]$AuthorizedKey
)

    Write-Host "Enabling SSH Remoting on container..."

    if ((Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*').State -NE 'Installed')
    {
        Write-Host "`nInstall OpenSSH Server"
        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
    }
    else
    {
        Write-Host "`nOpenSSH Server already installed"
    }

    if (-NOT (Test-Path "$env:ProgramData\ssh\sshd_config"))
    {
        # Start the SSHD service to create all the default config files
        Write-Host "`nCreate SSHD default config files"
        start-service sshd
        stop-service sshd
    }
    else
    {
        Write-Host "`nSSHD default config files already exist"
    }

    if (-NOT (Test-Path "$env:ProgramData\ssh\administrators_authorized_keys"))
    {
        Write-Host "`nAdd the AuthorizedKey as a trusted admin key"
        Add-Content -Force -Path "$env:ProgramData\ssh\administrators_authorized_keys" -Value "$authorizedKey"
        icacls.exe "$env:ProgramData\ssh\administrators_authorized_keys" /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"
    }
    else
    {
        Write-Host "`nTrusted admin keys already exist"
    }

    if (-NOT (Test-Path "$env:ProgramFiles\PowerShell\7\"))
    {
        Write-Host "`nInstall PowerShell"
        Invoke-WebRequest https://github.com/PowerShell/PowerShell/releases/download/v7.4.0/PowerShell-7.4.0-win-x64.msi -OutFile "$env:Temp\PowerShell-7.4.0-win-x64.msi"
        msiexec.exe /package "$env:Temp\PowerShell-7.4.0-win-x64.msi" /quiet ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1 USE_MU=1 ENABLE_MU=1 ADD_PATH=1
    }
    else
    {
        Write-Host "`nPowerShell 7 already installed"
    }

    if (-NOT (Test-Path "C:\Progra~1"))
    {
        Write-Host "`nCreate the symlink for the Program Files folder"
        cmd /C mklink /J 'C:\Progra~1' 'C:\Program Files\'
    }
    else
    {
        Write-Host "`nProgram Files symlink already exists"
    }

    $SshdConfigContent = Get-Content "$env:ProgramData\ssh\sshd_config"
    if ($SshdConfigContent -NotContains "Subsystem powershell C:\Progra~1\powershell\7\pwsh.exe -sshs -nologo")
    {
        Write-Host "`nUpdate the PowerShell subsystem config"
        $SshdConfigContent[78] = "Subsystem powershell C:\Progra~1\powershell\7\pwsh.exe -sshs -nologo"
        $SshdConfigContent | Set-Content "$env:ProgramData\ssh\sshd_config"
    }
    else
    {
        Write-Host "`nPowerShell subsystem config already exists"
    }

    Write-Host "`nDone"

} # SetupSshRemotingServer()


Function CleanupRemoting{

    Write-Host "Disabling PSRemoting on this computer..."

    Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value '' -Force
    Disable-PSRemoting

    winrm enumerate winrm/config/listener
    winrm delete winrm/config/listener?address=*+transport=HTTP

    Stop-Service winrm
    Set-Service -Name winrm -StartupType Disabled

    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name LocalAccountTokenFilterPolicy -Value 0 -Type DWord
    Remove-NetFirewallRule -DisplayGroup "Windows Remote Management" -ErrorAction Ignore
    netsh advfirewall firewall delete rule name="Windows Remote Management (HTTP-In)"

} # CleanupRemoting()

function main {
    try {
        if($Setup) {
            SetupRemoting
        } elseif($Cleanup) {
            CleanupRemoting
        } elseif($SetupSshRemotingClient) {
            SetupSshRemotingClient -PrivateKeyPath $PrivateKeyPath
        } elseif($SetupSshRemotingServer) {
            SetupSshRemotingServer -AuthorizedKey $AuthorizedKey
        }
    } #end try
    catch {
        Write-Host "Exception $($_.Exception.Message) in $($MyInvocation.MyCommand.Name)"
    }
}

#Entry point
main @PSBoundParameters