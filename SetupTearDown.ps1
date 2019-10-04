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
    [switch] $Cleanup
)

Function SetupRemoting{

    Write-Host "Enabling PSRemoting on this computer..."

    netsh advfirewall firewall add rule name="Windows Remote Management (HTTP-In)" dir=in action=allow service=any enable=yes profile=any localport=5985 protocol=tcp
    Enable-PSRemoting -SkipNetworkProfileCheck -Force -ErrorAction Ignore
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value '*' -Force

} # SetupRemoting()


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

#Main-function
function main {
    try {
        if($Setup.IsPresent) {
            SetupRemoting
        } elseif($Cleanup.IsPresent) {
            CleanupRemoting
        } else {
            Write-Host "Exiting.. as neither the setup nor cleanup flag was passed"
        }
    } # end try
    catch {
       Write-Host "Exception $($_.Exception.Message) in $($MyInvocation.MyCommand.Name)"
    }    
}

#Entry point
main @PSBoundParameters
