# Description

NetPerfTest is a set of tools used to simplify the collection of network configuration information for diagnosis of networking performance issues on Windows.

## Running the tool
Running this tool is a two step process. First we want to generate the perf commands to run.
```PowerShell
.\PERFTEST.PS1 -DestIp DestinationMachineIP -SrcIP SourceMachineIP -OutDir "c:\temp\deleteme"

Note that the PERFTEST cmdlet generate the commands under a subdirectory msdbg.CurrentMachineName.perftest
```
Now onto the second step, aka running the perf commands.
Note that since we are running the commands on the DestIp and SrcIp machines from CurrentMachine, we will need to enable PS Remoting

```
To Enable PSRemoting, run the following on both DestIp and SrcIp machines
Enable-PSRemoting -SkipNetworkProfileCheck -Force

```PowerShell
Import-Module .\runPerftool.psm1
ProcessCommands -DestIp DestinationMachineIP -SrcIP SourceMachineIP -OutDir "c:\temp\deleteme\msdbg.CurrentMachineName.perftest"
Please enter creds for connecting to the source machine and then destination machine
```
For further help run 
Get-Help ProcessCommands
```
If blocked by execution policy:
```PowerShell
Powershell.exe -ExecutionPolicy Bypass -File .\PERFTEST.PS1 -OutputDir .\

```Cleanup
At the end of the script, if you wish, you could Disable PSRemoting by running the following on both DestIp and SrcIp machines
Disable-PSRemoting
winrm enumerate winrm/config/listener
winrm delete winrm/config/listener?address=*+transport=HTTP
Stop-Service winrm
Set-Service -Name winrm -StartupType Disabled
Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name LocalAccountTokenFilterPolicy -Value 0 -Type DWord
Remove-NetFirewallRule -DisplayGroup "Windows Remote Management"
```

# Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.microsoft.com.

When you submit a pull request, a CLA-bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., label, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.
