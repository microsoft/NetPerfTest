<#
.SYNOPSIS
    Set up (or clean up) PSRemoting on this computer. Setup up option will Enable-PSRemoting and setup the machine to be able to run ps commands programmatically
    Cleanup up option will Disable-PSRemoting and perform other tasks that were done during setup like disable WinRM service, delete remoting specific firewall rules, etc.

.PARAMETER Setup
    This Switch will trigger the setup calls which ends up enabling PS Remoting (and which in turn starts the WinRM service and opens up remoting via the firewall

.PARAMETER Cleanup
    This switch triggers the cleanup path which disables WinRM service, removes the firewall rules that were created earlier for remoting, and also Disables PSRemoting

.DESCRIPTION
    Run this script to setup your machine for PS Remoting so that you can leverage the functionality of runPerfTool.psm1
    Run this script at the end of the tool runs to restore state on the machines.
    Ex: SetupTearDown.ps1 -Setup or SetupTearDown.ps1 -Cleanup
#>
Param(
    [switch] $Setup,
    [switch] $Cleanup,
    [switch] $SetupHost,
    [switch] $SetupContainer,
    [string] $AuthorizedKey
)

Function SetupRemoting{

    Write-Host "Enabling PSRemoting on this computer..."

    netsh advfirewall firewall add rule name="Windows Remote Management (HTTP-In)" dir=in action=allow service=any enable=yes profile=any localport=5985 protocol=tcp
    Enable-PSRemoting -SkipNetworkProfileCheck -Force -ErrorAction Ignore
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value '*' -Force

} # SetupRemoting()

Function SetupSshRemotingOnHost{

    Write-Host "Enabling SSH Remoting on host computer..."

    #TODO: Don't run setup steps if they've already been run before

    Write-Host "`nGenerating SSH Public Key"
    ssh-keygen -t ed25519
    $authorizedKey = Get-Content -Path $env:USERPROFILE\.ssh\id_ed25519.pub

    Write-Host "`nConfigure SSH-Agent with Private Key"
    Get-Service ssh-agent | Set-Service -StartupType Automatic
    Start-Service ssh-agent
    ssh-add $env:USERPROFILE\.ssh\id_ed25519

    Write-Host "`nInstall PowerShell"
    Invoke-WebRequest https://github.com/PowerShell/PowerShell/releases/download/v7.4.0/PowerShell-7.4.0-win-x64.msi -OutFile "$env:Temp\PowerShell-7.4.0-win-x64.msi"
    msiexec.exe /package "$env:Temp\PowerShell-7.4.0-win-x64.msi" /quiet ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1 USE_MU=1 ENABLE_MU=1 ADD_PATH=1

    Write-Host "`nDone"
    
    Write-Host "`n`nRun the following command in each of the containers"
    Write-Host ".\SetUpTearDown.ps1 -SetupContainer -AuthorizedKey '$authorizedKey'"

} # SetupSshRemotingOnHost()


Function SetupSshRemotingOnContainer{
param(
    [Parameter(Mandatory=$True)] [string]$AuthorizedKey
)

    Write-Host "Enabling SSH Remoting on container..."

    #TODO: Don't run setup steps if they've already been run before

    Write-Host "`nInstall OpenSSH Server"
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

    # Start the SSHD service to create all the default config files
    Write-Host "`nCreate SSHD default config files"
    start-service sshd
    stop-service sshd

    Write-Host "`nAdd the AuthorizedKey as a trusted admin key"
    Add-Content -Force -Path "$env:ProgramData\ssh\administrators_authorized_keys" -Value "$authorizedKey"
    icacls.exe "$env:ProgramData\ssh\administrators_authorized_keys" /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"

    Write-Host "`nInstall PowerShell"
    Invoke-WebRequest https://github.com/PowerShell/PowerShell/releases/download/v7.4.0/PowerShell-7.4.0-win-x64.msi -OutFile "$env:Temp\PowerShell-7.4.0-win-x64.msi"
    msiexec.exe /package "$env:Temp\PowerShell-7.4.0-win-x64.msi" /quiet ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1 USE_MU=1 ENABLE_MU=1 ADD_PATH=1

    Write-Host "`nCreate the symlink for the Program Files folder and update the powershell subsystem config"
    cmd /C mklink /J 'C:\Progra~1' 'C:\Program Files\'
    $SshdConfigContent = get-content C:\ProgramData\ssh\sshd_config
    $SshdConfigContent[78] = "Subsystem powershell C:\Progra~1\powershell\7\pwsh.exe -sshs -nologo"
    $SshdConfigContent | set-content C:\ProgramData\ssh\sshd_config

    Write-Host "`nDone"

} # SetupSshRemotingOnContainer()


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

try {
    if($Setup.IsPresent) {
        SetupRemoting
    } elseif($Cleanup.IsPresent) {
        CleanupRemoting
    } elseif($SetupHost) {
        SetupSshRemotingOnHost
    } elseif($SetupContainer) {
        SetupSshRemotingOnContainer -AuthorizedKey $AuthorizedKey
    } else {
        Write-Host "Exiting.. as neither the setup nor cleanup flag was passed"
    }
} # end try
catch {
    Write-Host "Exception $($_.Exception.Message) in $($MyInvocation.MyCommand.Name)"
}
