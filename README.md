# NetPerfTest Tool(s)

## Description

NetPerfTest is a collection of tools used to generate tests, run tests and collect network configuration, and performance statistics for diagnosis of networking performance issues.

## Pre-Requisites
The goal here is to collect networking perf stats involving the Source and Destination machines that are needing diagnosis.
To accomplish this, we will leverage multiple Powershell scripts.
In order to be able to run Powershell scripts, we must set the 

## Commands Generation
Now that our pre-requisites have been met, we can start the testing process. 
First, we must generate a bunch of relevant networking tests between these machines.
Create a folder that will hold the output of these scripts, say: C:\Temp\MyDirectoryForTesting
Now that the folder is created, we’re ready to generate the commands using the PERFTEST cmdlet : 

```PowerShell 
.\PERFTEST.PS1 -DestIp DestinationMachineIP -SrcIP SourceMachineIP -OutDir "C:\Temp\MyDirectoryForTesting"
```

Note that the PERFTEST cmdlet generate the commands under a subdirectory msdbg.CurrentMachineName.perftest

## Setup
Before proceeding to run the commands/tests that were generated above, we must enable Powershell Remoting. 
Don’t worry, we have a script that can do all of this for you.
We also have a cleanup script that we recommend you run after collecting the results (more on that below, in the Cleanup section)

To setup the machine(s), please run the following command on each machine you wish to test (example: Destination and Source machine)
```PowerShell 
SetupTearDown.ps1 -Setup
```

## Running the tool, collecting results
We are now at the phase where we will run the tests against the Source and Destination Machines and collect results for offline troubleshooting.
The scripts use Powershell Remoting to kick off commands on the two machines to perform the networking tests.
You will need to provide the same Source and Destination IPs as you did for commands generation. In addition you must provide the path to the 
directory of commands that was generated in the Commands Generation phase above. Ex: msdbg.CurrentMachineName.perftest

RunPerfTool was created as a powershell module with the idea of flexibility with its invocation (invoking from another script versus standalone invocations, etc)

We will thus need to import the Module like this: ```Import-Module -Force .\runPerftool.psm1```
We will then invoke a single function in this module that will process all the commands and run them and gather the results. 
For further help with this function, run ```Get-Help ProcessCommands```

The command to run tests is:
```
ProcessCommands -DestIp DestinationMachineIP -SrcIp SourceMachineIP -CommandsDir C:\Temp\MyDirectoryForTesting\msdbg.CurrentMachineName.perftest -SrcIpUserName SrcDomain\SrcUserName -DestIpUserName DestDomain\DestUserName
```

You will be prompted for password for both credentials. Don’t worry, it’s a Secure-string so your password will not be displayed or stored in clear text at any point.

```PowerShell commands
Import-Module -Force .\runPerftool.psm1
ProcessCommands -DestIp DestinationMachineIP -SrcIp SourceMachineIP -CommandsDir C:\Temp\MyDirectoryForTesting\msdbg.CurrentMachineName.perftest -SrcIpUserName SrcDomain\SrcUserName -DestIpUserName DestDomain\DestUserName
For further help run 
Get-Help ProcessCommands
```

That’s it. Now sit back and wait for the script to complete. You should see the zip files from DestinationMachineIp and SourceMachineIP machines under the 
CommandsDir folder you specified (ex: C:\Temp\MyDirectoryForTesting\msdbg.CurrentMachineName.perftest)

At this point you are done! Just don’t forget to share the folder contents and please do move on to the Cleanup step below.

## Cleanup
Now that you’re done running the relevant tests, we recommend you run the cleanup script to undo the steps that were done in the Setup stage.
To cleanup the machine(s), please run the following command on each machine you leveraged for testing (Destination and Source machine)

```PowerShell 
SetupTearDown.ps1 -Cleanup
```

## Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.microsoft.com.

When you submit a pull request, a CLA-bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., label, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.
