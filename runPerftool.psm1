$Logfile = ".\$(gc env:computername).log"
Clear-content -Path $Logfile -Force -ErrorAction Ignore

#Function to write to log file
Function LogWrite
{
Param ([string]$logstring, [string] $echoToConsole=$false)
    $timeStampLogString = "[{0}] {1}"-f (Get-Date -Format "MM/dd/yyyy HH:mm"), $logstring
    if ($echoToConsole -eq $true) {
        Write-Host $timeStampLogString
    }
    Add-content $Logfile -value $timeStampLogString
}

# Certain tools like ntttcp have params that need to be added to the actual timeout value between command pairs
# to prevent premature termination of the send/recv processes
Function GetActualTimeOutValue
{
Param ([Int]$AdditionalTimeout, [string] $Line)

    [Int] $timeout = $AdditionalTimeout 
    # currently we only bloat the timeout value with additional params for ntttcp. 
    # as we onboard additional tools in the future, we will add tool specific logic here
    if ($Line -match "ntttcp")
    {
        try {
            [Int] $warmup = ($Line.Substring($Line.IndexOf("-wu")+("-wu".Length)+1).Split(' ')[0])
            [Int] $cooldown = ($Line.Substring($Line.IndexOf("-cd")+("-cd".Length)+1).Split(' ')[0])
            [Int] $rumtime = ($Line.Substring($Line.IndexOf("-t")+("-t".Length)+1).Split(' ')[0])
            $timeout += $warmup + $cooldown + $rumtime
        }
       catch {}
    } elseif ($Line -match "ctsTraffic") 
    {
        try {
            [Int] $runtime = [Int]($Line.Substring($Line.IndexOf("-timeLimit")).Split(" ")[0].Split(":")[1]) / 1000
        }
        catch {}
    }
    return $timeout
}

#===============================================
# Scriptblock Util functions
#===============================================

# Creates firewall rules on the machine to allow send/recv of data from/to the machine
$ScriptBlockEnableFirewallRules = {
param ($RuleName, $PathToExe)
    New-NetFirewallRule -DisplayName ($RuleName+"Out") -Direction "Out" -Action "Allow" -Program "$PathToExe" |Out-Null
    New-NetFirewallRule -DisplayName ($RuleName+"In") -Direction "In" -Action "Allow" -Program "$PathToExe" |Out-Null
}

# clean up any firewall rules that were created by the tool
$ScriptBlockCleanupFirewallRules = {
param ($RuleName)
    Remove-NetFirewallRule -DisplayName "$RuleName" -ErrorAction Ignore
}

# kill a task
$ScriptBlockTaskKill = {
param ($taskname)
    Start-Process -FilePath taskkill -ArgumentList "/f /im $taskname" -ErrorAction Ignore
}

# Set up a directory on the remote machines for results gathering.
$ScriptBlockCreateDirForResults = {
    param ($Cmddir)
    $Exists = test-path $Cmddir
    if (!$Exists) {
        New-Item -ItemType Directory -Force -Path "$Cmddir" |Out-Null
    }
    return $Exists
} # $ScriptBlockCreateDirForResults()


# Delete file/folder on the remote machines 
$ScriptBlockRemoveFileFolder = {
    param ($Arg)
    Remove-Item -Force -Path "$Arg" -Recurse -ErrorAction SilentlyContinue
} # $ScriptBlockRemoveFileFolder()


# Delete the entire folder (if empty) on the remote machines
$ScriptBlockRemoveFolderTree = {
    param ($Arg)

    $parentfolder = (Get-Item $Arg).Parent.FullName

    # First do as instructed. Remove-Item $arg.
    Remove-Item -Force -Path "$Arg" -Recurse -ErrorAction SilentlyContinue

    # We dont know how many levels of parent folders were created so we will keep navigating upward till we find a non empty parent directory and then stop
    $folderCount = $parentfolder.Split('\').count 

    for ($i=1; $i -le $folderCount; $i++) {

        $folderToDelete = $parentfolder

        #Extract parent info before nuking the folder
        $parentfolder = (Get-Item $folderToDelete).Parent.FullName

           
        #check if the folder is empty and if so, delete it
        if ((dir -Directory $folderToDelete | Measure-Object).Count -eq 0) {
            Remove-Item -Force -Path "$folderToDelete" -Recurse -ErrorAction SilentlyContinue
        }
        else
        { 
            #Folder/subfolder wasnt found empty. so we stop here and exit
            break
        }

    }

} # $ScriptBlockRemoveFolderTree ()


$ScriptBlockRunToolCmd = {
    param($Line) 
    $logFileName = ""
    if ($Line -match "ntttcp")
    {
        try {
            $logFileName = ($Line.Substring($Line.IndexOf("-xml")+("-xml".Length)+1).Split(' ')[0]) -ireplace ".xml", ".txt"
        }
       catch {}
    }

    if (-Not [String]::IsNullOrWhiteSpace($logfileName))
    {
            Start-Process -RedirectStandardOutput $logfileName -FilePath "cmd.exe" -ArgumentList ("/C $Line")
    }
    else {
            Start-Process -FilePath "cmd.exe" -ArgumentList ("/C $Line")
    }

} # $ScriptBlockRunToolCmd()

$CheckProcessExitScriptBlock = {
    param($toolname) 
    return (Get-Process -Name $toolname -ErrorAction SilentlyContinue)
} # $CheckProcessExitScriptBlock()


$CreateZipScriptBlock = {
    Param(
        [String] $Src,
        [String] $Out
    )

    # Write-Host "Invoking Cmd - [io.compression.zipfile]::CreateFromDirectory($Src, $Out) "

    if (Test-path $Out) {
        Remove-item $Out
    }

    Add-Type -assembly "system.io.compression.filesystem"
    [io.compression.zipfile]::CreateFromDirectory($Src, $Out) 

} # $CreateZipScriptBlock()


<#
.SYNOPSIS
    This function reads an input file of commands and orchestrates the execution of these commands on remote machines.

.PARAMETER DestIp
    Required Parameter. The IpAddr of the destination machine that's going to receive data for the duration of the throughput tests

.PARAMETER SrcIp
    Required Parameter. The IpAddr of the source machine that's going to be sending data for the duration of the throughput tests

.PARAMETER DestIpUserName
    Required Parameter. Gets domain\username needed to connect to DestIp Machine

.PARAMETER DestIpPassword
    Required Parameter. Gets password needed to connect to DestIp Machine. 
    Password will be stored as Secure String and chars will not be displayed on the console.

.PARAMETER SrcIpUserName
    Required Parameter. Gets domain\username needed to connect to SrcIp Machine

.PARAMETER SrcIpPassword
    Required Parameter. Gets password needed to connect to SrcIp Machine. 
    Password will be stored as Secure String and chars will not be displayed on the console

.PARAMETER CommandsDir
    Required Parameter that specifies the location of the folder with the auto generated commands to run.

.PARAMETER BCleanup
    Optional parameter that will clean up the source and destination folders, after the test run, if set to true.
    If false, the folders that were created to store the results will be left untouched on both machines
    Default value: $True

.PARAMETER ZipResults
    Optional parameter that will compress the results folders before copying it over to the machine that's triggering the run.
    If false, the result folders from both Source and Destination machines will be copied over as is.
    Default value: $True

.PARAMETER TimeoutValueInSeconds
    Optional parameter to configure the amount of wait time (in seconds) to allow each command pair to gracefully exit 
    before cleaning up and moving to the next set of commands
    Default value: 90 seconds

.DESCRIPTION
    Please run SetupTearDown.ps1 -Setup on the DestIp and SrcIp machines independently to help with PSRemoting setup
    This function is dependent on the output of PERFTEST.PS1 function
    for example, PERFTEST.PS1 is invoked with DestIp, SrcIp and OutDir.
    to invoke the commands that were generated above, we pass the same parameters to ProcessCommands function
    Note that we expect the directory to be pointing to the folder that was generated by perftest.ps1 under the outpurDir path supplied by the user
    Ex: ProcessCommands -DestIp "$DestIp" -SrcIp "$SrcIp" -CommandsDir "C:\temp\msdbg.Machine1.perftest" -DestIpUserName "domain\username" -SrcIpUserName "domain\username"
    You may chose to run SetupTearDown.ps1 -Cleanup if you wish to clean up any config changes from the Setup step
#>
Function ProcessCommands{
    param(
    [Parameter(Mandatory=$True)]  [string]$DestIp,
    [Parameter(Mandatory=$True)] [string]$SrcIp,
    [Parameter(Mandatory=$True)]  [string]$CommandsDir,
    [Parameter(Mandatory=$True, Position=0, HelpMessage="Dest Machine Username?")]
    [string] $DestIpUserName,
    [Parameter(Mandatory=$True, Position=0, HelpMessage="Dest Machine Password?")]
    [SecureString]$DestIpPassword,
    [Parameter(Mandatory=$True, Position=0, HelpMessage="Src Machine Username?")]
    [string] $SrcIpUserName,
    [Parameter(Mandatory=$True, Position=0, HelpMessage="Src Machine Password?")]
    [SecureString]$SrcIpPassword,
    [Parameter(Mandatory=$False)] [string]$Bcleanup=$True,
    [Parameter(Mandatory=$False)]$ZipResults=$True,
    [Parameter(Mandatory=$False)]$TimeoutValueInSeconds=90,
    [Parameter(Mandatory=$False)]$PollTimeInSeconds=5,
    [Parameter(Mandatory=$False)] [Switch] $BroadcastEvents,
    [Parameter(Mandatory=$False)] [String] $BroadcastComputer
    )

    $recvComputerName = $DestIp
    $sendComputerName = $SrcIp

    [PSCredential] $sendIPCreds = New-Object System.Management.Automation.PSCredential($SrcIpUserName, $SrcIpPassword)

    [PSCredential] $recvIPCreds = New-Object System.Management.Automation.PSCredential($DestIpUserName, $DestIpPassword)

    [String] $workingDir = $CommandsDir.TrimEnd("\")

    LogWrite "Processing ctsTraffic commands" $true 
    ProcessToolCommands -Toolname "ctsTraffic" -RecvComputerName $recvComputerName -RecvComputerCreds $recvIPCreds -SendComputerName $sendComputerName -SendComputerCreds $sendIPCreds -CommandsDir $workingDir -Bcleanup $Bcleanup -BZip $ZipResults -TimeoutValueBetweenCommandPairs $TimeoutValueInSeconds -PollTimeInSeconds $PollTimeInSeconds -BroadcastEvents $BroadcastEvents -BroadcastComputer $BroadcastComputer

    LogWrite "Processing cps commands" $true
    ProcessToolCommands -Toolname "cps" -RecvComputerName $recvComputerName -RecvComputerCreds $recvIPCreds -SendComputerName $sendComputerName -SendComputerCreds $sendIPCreds -CommandsDir $workingDir -Bcleanup $Bcleanup -BZip $ZipResults -TimeoutValueBetweenCommandPairs $TimeoutValueInSeconds -PollTimeInSeconds $PollTimeInSeconds -BroadcastEvents $BroadcastEvents -BroadcastComputer $BroadcastComputer

    LogWrite "Processing ntttcp commands" $true
    ProcessToolCommands -Toolname "ntttcp" -RecvComputerName $recvComputerName -RecvComputerCreds $recvIPCreds -SendComputerName $sendComputerName -SendComputerCreds $sendIPCreds -CommandsDir $workingDir -Bcleanup $Bcleanup -BZip $ZipResults -TimeoutValueBetweenCommandPairs $TimeoutValueInSeconds -PollTimeInSeconds $PollTimeInSeconds -BroadcastEvents $BroadcastEvents -BroadcastComputer $BroadcastComputer

    LogWrite "Processing latte commands" $true
    ProcessToolCommands -Toolname "latte" -RecvComputerName $recvComputerName -RecvComputerCreds $recvIPCreds -SendComputerName $sendComputerName -SendComputerCreds $sendIPCreds -CommandsDir $workingDir -Bcleanup $Bcleanup -BZip $ZipResults -TimeoutValueBetweenCommandPairs $TimeoutValueInSeconds -PollTimeInSeconds $PollTimeInSeconds -BroadcastEvents $BroadcastEvents -BroadcastComputer $BroadcastComputer

    LogWrite "ProcessCommands Done!" $true
    Move-Item -Path $Logfile -Destination "$workingDir" -Force -ErrorAction Ignore

} # ProcessCommands()


#===============================================
# Internal Functions
#===============================================

<#
.SYNOPSIS
    This function reads an input file of commands and orchestrates the execution of these commands on remote machines.

.PARAMETER RecvComputerName
    The IpAddr of the destination machine that's going to play the Receiver role and wait to receive data for the duration of the throughput tests

.PARAMETER SendComputerName
    The IpAddr of the sender machine that's going to send data for the duration of the throughput tests

.PARAMETER CommandsDir
    The location of the folder that's going to have the auto generated commands for the tool.

.PARAMETER Toolname
    Default value: ntttcp. The function parses the Send and Recv files for the tool specified here
    and reads the commands and executes them on the SrcIp and DestIp machines

.PARAMETER bCleanup
    Required parameter. The function creates folders and subfolders on remote machines to house the result files of the individual commands. bCleanup param decides 
    if the folders should be left as is, or if they should be cleaned up

.PARAMETER SendComputerCreds
    Optional PSCredentials to connect to the Sender machine

.PARAMETER RecvComputerCreds
    Optional PSCredentials to connect to the Receiver machine

.PARAMETER BZip
    Required parameter. The function creates folders and subfolders on remote machines to house the result files of the individual commands. BZip param decides 
    if the folders should be compressed or left uncompressed before copying over.

.PARAMETER TimeoutValueBetweenCommandPairs
    Optional parameter to configure the amount of time the tool waits (in seconds) between command pairs before moving to the next set of commands
    Note that for certain commands this value will get bloated to account for tool params like runtime, warm up time, cool down time, etc.

.PARAMETER PollTimeInSeconds
    Optional parameter to configure the amount of time the tool waits (in seconds) before waking up to check if the TimeoutValueBetweenCommandPairs period has elapsed
#>
Function ProcessToolCommands{
param(
    [Parameter(Mandatory=$True)] [string]$RecvComputerName,
    [Parameter(Mandatory=$True)] [string]$SendComputerName,
    [Parameter(Mandatory=$True)] [string]$CommandsDir,
    [Parameter(Mandatory=$True)] [string]$Bcleanup, 
    [Parameter(Mandatory=$False)] [string]$Toolname = "ntttcp", 
    [Parameter(Mandatory=$False)] [PSCredential] $SendComputerCreds = [System.Management.Automation.PSCredential]::Empty,
    [Parameter(Mandatory=$False)] [PSCredential] $RecvComputerCreds = [System.Management.Automation.PSCredential]::Empty,
    [Parameter(Mandatory=$True)] [bool]$BZip,
    [Parameter(Mandatory=$False)] [int] $TimeoutValueBetweenCommandPairs = 60,
    [Parameter(Mandatory=$False)] [int] $PollTimeInSeconds = 5, 
    [Parameter(Mandatory=$False)] [Boolean] $BroadcastEvents = $false,
    [Parameter(Mandatory=$False)] [String] $BroadcastComputer
    )
    [bool] $gracefulCleanup = $False

    $toolpath = ".\{0}" -f $Toolname
    $toolexe = "{0}.exe" -f $Toolname

    $recvCredSplat = @{}
    if ($RecvComputerCreds -ne [System.Management.Automation.PSCredential]::Empty) {
        $recvCredSplat['Credential'] = $RecvComputerCreds
    }

    $sendCredSplat = @{}
    if ($SendComputerCreds -ne [System.Management.Automation.PSCredential]::Empty) {
        $sendCredSplat['Credential'] = $SendComputerCreds
    }

    try {
        # Establish the Remote PS session with Receiver
        $recvPSSession = New-PSSession -ComputerName $RecvComputerName @recvCredSplat

        if($recvPSsession -eq $null) {
            LogWrite "Error connecting to Host: $($RecvComputerName)"
            return
        }

        # Establish the Remote PS session with Sender
        $sendPSSession = New-PSSession -ComputerName $SendComputerName @sendCredSplat

        if($sendPSsession -eq $null) {
            LogWrite "Error connecting to Host: $($SendComputerName)"
            return
        }

        # Construct the input file to read for commands.
        $sendCmdFile = Join-Path -Path $CommandsDir -ChildPath "\$Toolname\$Toolname.Commands.Send.txt"
        $recvCmdFile = Join-Path -Path $CommandsDir -ChildPath "\$Toolname\$Toolname.Commands.Recv.txt"

        # Ensure that remote machines have the directory created for results gathering. 
        $recvFolderExists = Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir)
        $sendFolderExists = Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir)

        # Clean up the Receiver/Sender folders on remote machines, if they exist so that we dont capture any stale logs
        $null = Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockRemoveFileFolder -ArgumentList "$CommandsDir\Receiver" 
        $null = Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockRemoveFileFolder -ArgumentList "$CommandsDir\Sender"

        # Create dirs and subdirs for each of the supported tools
        # Invoke-Command calls set to null in order to suppress unwanted output
        $null = Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir+"\Sender\cps\Mode0") 
        $null = Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir+"\Receiver\cps\Mode0")
        $null = Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir+"\Sender\cps\Mode1")
        $null = Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir+"\Receiver\cps\Mode1")
        $null = Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir+"\Sender\cps\Mode2")
        $null = Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir+"\Receiver\cps\Mode2")
        $null = Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir+"\Receiver\ntttcp\tcp") 
        $null = Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir+"\Sender\ntttcp\tcp") 
        $null = Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir+"\Receiver\ntttcp\udp") 
        $null = Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir+"\Sender\ntttcp\udp") 
        $null = Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir+"\Receiver\latte\optimized")
        $null = Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir+"\Receiver\latte\default")
        $null = Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir+"\Sender\latte\optimized")
        $null = Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir+"\Sender\latte\default") 
        $null = Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir+"\Receiver\ctsTraffic\tcp") 
        $null = Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir+"\Receiver\ctsTraffic\udp")  
        $null = Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir+"\Sender\ctsTraffic\tcp")  
        $null = Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir+"\Sender\ctsTraffic\udp")  

        #copy the tool exe to the remote machines
        Copy-Item -Path "$toolpath\$toolexe" -Destination "$CommandsDir\Receiver" -ToSession $recvPSSession
        Copy-Item -Path "$toolpath\$toolexe" -Destination "$CommandsDir\Sender" -ToSession $sendPSSession

        # Setup firewall rules so that traffic can go through
        $null = Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockEnableFirewallRules -ArgumentList ("Allow$Toolname", "$CommandsDir\Receiver\$toolexe")
        $null = Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockEnableFirewallRules -ArgumentList ("Allow$Toolname", "$CommandsDir\Sender\$toolexe") 

        $recvCommandsReader = [System.IO.File]::OpenText($recvCmdFile)
        $sendCommandsReader = [System.IO.File]::OpenText($sendCmdFile)
        $recvCommands = [Array] @()

        while ($null -ne ($recvCmd = $recvCommandsReader.ReadLine()) ) {
            $recvCommands += ,$recvCmd
        }
        while ($null -ne ($sendCmd = $sendCommandsReader.ReadLine()) ) {
            $sendCommands += ,$sendCmd
        }
        $recvCommandsReader.close()
        $sendCommandsReader.close()

        $sw = [diagnostics.stopwatch]::StartNew()
        $numCmds = [math]::Min($recvCommands.Count, $sendCommands.Count)
        $i = 0
        while($i -lt $numCmds) {
            #change the command to add path to tool
            $recvCmd = $recvCommands[$i]
            $sendCmd = $sendCommands[$i]
            $unexpandedRecvCmd = $recvCmd

            $recvCmd =  $recvCmd -ireplace [regex]::Escape("$toolexe"), "$CommandsDir\$toolexe"
            $sendCmd =  $sendCmd -ireplace [regex]::Escape("$toolexe"), "$CommandsDir\$toolexe"
            $cmdPairCompleted = $false 
            # Work here to invoke recv commands
            # Since we want the files to get generated under a subfolder, we replace the path to include the subfolder
            $recvCmd =  $recvCmd -ireplace [regex]::Escape($CommandsDir), "$CommandsDir\Receiver"
            LogWrite "Invoking Cmd - Machine: $recvComputerName Command: $recvCmd"
            LogWrite "Invoking Cmd $($i + 1) / $numCmds ..." $true

            
            if ($BroadcastEvents) {
                try {
                    if ($BroadcastComputer) {
                        Write-EventLog -LogName "NPT" -Source "NPT" -EventID 1001 -Message $unexpandedRecvCmd -ComputerName $BroadcastComputer 
                    } else {
                        Write-EventLog -LogName "NPT" -Source "NPT" -EventID 1001 -Message $unexpandedRecvCmd
                    }
                } catch {
                    LogWrite "Error writing to event log" $true 
                }
            }
            
            $null = Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockRunToolCmd -ArgumentList $recvCmd 

            # Work here to invoke send commands
            # Since we want the files to get generated under a subfolder, we replace the path to include the subfolder
            $sendCmd =  $sendCmd -ireplace [regex]::Escape($CommandsDir), "$CommandsDir\Sender"
            LogWrite "Invoking Cmd - Machine: $sendComputerName Command: $sendCmd"  
            $null = Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockRunToolCmd -ArgumentList $sendCmd

            # non blocking loop to check if the process made a clean exit

            # Calculate actual timeout value.
            # For tools such as ntttcp, we may need to add additional #s for runtime, wu and cd times 
            [int] $timeout = GetActualTimeOutValue -AdditionalTimeout $TimeoutValueBetweenCommandPairs -Line $sendCmd
            LogWrite "Waiting for $timeout seconds ..."
            $sw.Reset()
            $sw.Start()

            while (([math]::Round($sw.Elapsed.TotalSeconds,0)) -lt $timeout){

                start-sleep -seconds $PollTimeInSeconds

                $checkRecvProcessExit = Invoke-Command -Session $recvPSSession -ScriptBlock $CheckProcessExitScriptBlock -ArgumentList "$Toolname"
                $checkSendProcessExit = Invoke-Command -Session $sendPSSession -ScriptBlock $CheckProcessExitScriptBlock -ArgumentList "$Toolname"

                if (($checkRecvProcessExit -eq $null)-and ($checkSendProcessExit -eq $null)){
                    $cmdPairCompleted = $true
                    LogWrite "$Toolname exited on both Src and Dest machines"
                    break
                }

                if(($Toolname -eq "ctsTraffic") -and ($checkSendProcessExit -eq $null) ) {
                    # There's no time-based shutoff with ctstraffic servers, so recv machine will remain running until
                    # we send it a task kill command
                    LogWrite "$Toolname exited on Src machine, proceeding to shut down on Dst machine"
                    $null = Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockTaskKill -ArgumentList $toolexe
                    break
                }
            }

            if ($BroadcastEvents) {
                try {
                    if ($BroadcastComputer) {
                        Write-EventLog -LogName "NPT" -Source "NPT" -EventID 1002 -Message $unexpandedRecvCmd -ComputerName $BroadcastComputer 
                    } else {
                        Write-EventLog -LogName "NPT" -Source "NPT" -EventID 1002 -Message $unexpandedRecvCmd
                    }
                } catch {
                    LogWrite "Error writing to event log" $true 
                }
            }


            LogWrite "Complete`n" $true
            $sw.Stop()
            
            #Wait for disk I/O to be completed
            Write-VolumeCache (get-location).Drive.Name

            # If command pair didnt gracefully exit, do the logging, cleanup here
            if(-Not $cmdPairCompleted) {
                $checkRecvProcessExit = Invoke-Command -Session $recvPSSession -ScriptBlock $CheckProcessExitScriptBlock -ArgumentList "$Toolname"
                $checkSendProcessExit = Invoke-Command -Session $sendPSSession -ScriptBlock $CheckProcessExitScriptBlock -ArgumentList "$Toolname"

                if ($checkRecvProcessExit -ne $null) {
                    LogWrite (" ++ {0} on Receiver did not exit cleanly... Timer Elapsed Value: {1}" -f $Toolname, ($sw.elapsed.TotalSeconds))
                }
                if ($checkSendProcessExit -ne $null) {
                    LogWrite (" ++ {0} on Sender did not exit cleanly...  Timer Elapsed Value: {1}" -f $Toolname, ($sw.elapsed.TotalSeconds))
                }
            }

            #Since time is up, clean up any processes that failed to exit gracefully so that the new commands can be issued
            $null = Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockTaskKill -ArgumentList $toolexe
            $null = Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockTaskKill -ArgumentList $toolexe

            #Add sleep between before running the next command pair
            start-sleep -seconds $PollTimeInSeconds
            $i += 1
        }

        LogWrite "Test runs completed. Collecting results..."

        if ($BZip -eq $true) {
            #Zip the files on remote machines

            $null = Invoke-Command -Session $recvPSSession -ScriptBlock $CreateZipScriptBlock -ArgumentList ("$CommandsDir\Receiver\$Toolname", "$CommandsDir\Recv.zip")
            $null = Invoke-Command -Session $sendPSSession -ScriptBlock $CreateZipScriptBlock -ArgumentList ("$CommandsDir\Sender\$Toolname", "$CommandsDir\Send.zip")

            Remove-Item -Force -Path ("{0}\{1}_Receiver.zip" -f $CommandsDir, $Toolname) -Recurse -ErrorAction SilentlyContinue
            Remove-Item -Force -Path ("{0}\{1}_Sender.zip" -f $CommandsDir, $Toolname) -Recurse -ErrorAction SilentlyContinue

            #copy the zip files from remote machines to the current (orchestrator) machines
            Copy-Item -Path "$CommandsDir\Recv.zip" -Destination ("{0}\{1}_Receiver.zip" -f $CommandsDir, $Toolname) -FromSession $recvPSSession -Force
            Copy-Item -Path "$CommandsDir\Send.zip" -Destination ("{0}\{1}_Sender.zip" -f $CommandsDir, $Toolname) -FromSession $sendPSSession -Force

            $null = Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockRemoveFileFolder -ArgumentList "$CommandsDir\Recv.zip"
            $null = Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockRemoveFileFolder -ArgumentList "$CommandsDir\Send.zip"
        } else {

            Remove-Item -Force -Path ("{0}\{1}_Receiver" -f $CommandsDir, $Toolname) -Recurse -ErrorAction SilentlyContinue
            Remove-Item -Force -Path ("{0}\{1}_Sender" -f $CommandsDir, $Toolname) -Recurse -ErrorAction SilentlyContinue

            #copy just the entire results folder from remote machines to the current (orchestrator) machine
            Copy-Item -Path "$CommandsDir\Receiver\$Toolname\." -Recurse -Destination ("{0}\{1}_Receiver" -f $CommandsDir, $Toolname) -FromSession $recvPSSession -Force
            Copy-Item -Path "$CommandsDir\Sender\$Toolname\." -Recurse -Destination ("{0}\{1}_Sender" -f $CommandsDir, $Toolname) -FromSession $sendPSSession -Force
        }

        if ($Bcleanup -eq $True) { 
            LogWrite "Cleaning up folders on Machine: $recvComputerName"

            #clean up the folders and files we created
            if($recvFolderExists -eq $false) {
                 # The folder never existed in the first place. we need to clean up the directories we created
                 $null = Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockRemoveFolderTree -ArgumentList "$CommandsDir"
            } else {
                # this folder existed earlier on the machine. Leave the directory alone
                # Remove just the child directories and the files we created. 
                $null = Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockRemoveFileFolder -ArgumentList "$CommandsDir\Receiver"
            }

            LogWrite "Cleaning up folders on Machine: $sendComputerName"

            if($sendFolderExists -eq $false) {
                $null = Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockRemoveFolderTree -ArgumentList "$CommandsDir"
            } else {
                # this folder existed earlier on the machine. Leave the directory alone
                # Remove just the child directories and the files we created. Leave the directory alone
                $null = Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockRemoveFileFolder -ArgumentList "$CommandsDir\Sender"
            }
        } # if ($Bcleanup -eq $true)
        $gracefulCleanup = $True
    } # end try
    catch {
       LogWrite "Exception $($_.Exception.Message) in $($MyInvocation.MyCommand.Name)"
    }
    finally {
        if($gracefulCleanup -eq $False)
        {

            $null = Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockTaskKill -ArgumentList $toolexe
            $null = Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockTaskKill -ArgumentList $toolexe

        }

        LogWrite "Cleaning up the firewall rules that were created as part of script run..."
        # Clean up the firewall rules that this script created
        $null = Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockCleanupFirewallRules -ArgumentList (("Allow{0}In" -f $Toolname))
        $null = Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockCleanupFirewallRules -ArgumentList (("Allow{0}Out" -f $Toolname))

        $null = Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCleanupFirewallRules -ArgumentList (("Allow{0}In" -f $Toolname))
        $null = Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCleanupFirewallRules -ArgumentList (("Allow{0}Out" -f $Toolname))

        LogWrite "Cleaning up Remote PS Sessions"
        # Clean up the PS Sessions
        Remove-PSSession $sendPSSession  -ErrorAction Ignore
        Remove-PSSession $recvPSSession  -ErrorAction Ignore

    } #finally
} # ProcessToolCommands()
