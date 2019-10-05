#===============================================
# Scriptblock Util functions
#===============================================

# Creates firewall rules on the machine to allow send/recv of data from/to the machine
$ScriptBlockEnableFirewallRules = {
param ($RuleName, $PathToExe)
    New-NetFirewallRule -DisplayName ($RuleName+"Out") -Direction "Out" -Action "Allow" -Program "$PathToExe"
    New-NetFirewallRule -DisplayName ($RuleName+"In") -Direction "In" -Action "Allow" -Program "$PathToExe"
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
    Write-Host "Running Command: Remove-Item -Force -Path $Arg -Recurse -ErrorAction SilentlyContinue"
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
    Start-Process -FilePath "cmd.exe" -ArgumentList ("/C $Line")
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

    Write-Host "Invoking Cmd - [io.compression.zipfile]::CreateFromDirectory($Src, $Out) "

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
    The IpAddr of the destination machine that's going to receive data for the duration of the throughput tests

.PARAMETER SrcIp
    The IpAddr of the source machine that's going to be sending data for the duration of the throughput tests

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
    The location of the folder that's going to have the auto generated commands needing to be run.

.DESCRIPTION
    Please run SetupTearDown.ps1 -Setup on the DestIp and SrcIp machines independently to help with PSRemoting setup
    This function is dependent on the output of PERFTEST.PS1 function
    for example, PERFTEST.PS1 is invoked with DestIp, SrcIp and OutDir.
    to invoke the commands that were generated above, we pass the same parameters to ProcessCommands function
    Note that we expect the directory to be pointing to the folder that was generated by perftest.ps1 under the outpurDir path supplied by the user
    Ex: ProcessCommands -DestIp "$DestIp" -SrcIp "$SrcIp" -CommandsDir "C:\temp\msdbg.Machine1.perftest"
    You may chose to run SetupTearDown.ps1 -Cleanup if you wish to clean up any config changes from the Setup step
#>
Function ProcessCommands{
    param(
    [Parameter(Mandatory=$True)]  [string]$DestIp,
    [Parameter(Mandatory=$True)] [string]$SrcIp,
    [Parameter(Mandatory=$True)]  [string]$CommandsDir,
    [Parameter(Mandatory=$True, Position=0, HelpMessage="Dest Machine Username?")]
    [string] $DestIpUserName,
    [Parameter(Mandatory=$true, Position=0, HelpMessage="Dest Machine Password?")]
    [SecureString]$DestIpPassword,
    [Parameter(Mandatory=$True, Position=0, HelpMessage="Src Machine Username?")]
    [string] $SrcIpUserName,
    [Parameter(Mandatory=$true, Position=0, HelpMessage="Src Machine Password?")]
    [SecureString]$SrcIpPassword
    )

    $recvComputerName = $DestIp
    $sendComputerName = $SrcIp

    [PSCredential] $sendIPCreds = New-Object System.Management.Automation.PSCredential($SrcIpUserName, $SrcIpPassword)

    [PSCredential] $recvIPCreds = New-Object System.Management.Automation.PSCredential($DestIpUserName, $DestIpPassword)

    Write-Host "Processing ntttcp commands"
    ProcessToolCommands -Toolname "ntttcp" -RecvComputerName $recvComputerName -RecvComputerCreds $recvIPCreds -SendComputerName $sendComputerName -SendComputerCreds $sendIPCreds -CommandsDir $CommandsDir

    Write-Host "Processing latte commands"
    ProcessToolCommands -Toolname "latte" -RecvComputerName $recvComputerName -RecvComputerCreds $recvIPCreds -SendComputerName $sendComputerName -SendComputerCreds $sendIPCreds -CommandsDir $CommandsDir

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
    Default value: $False. The function creates folders and subfolders on remote machines to house the result files of the individual commands. bCleanup param decides 
    if the folders should be left as is, or if they should be cleaned up

.PARAMETER SendComputerCreds
    Optional PSCredentials to connect to the Sender machine

.PARAMETER RecvComputerCreds
    Optional PSCredentials to connect to the Receiver machine
#>
Function ProcessToolCommands{
param(
    [Parameter(Mandatory=$True)] [string]$RecvComputerName,
    [Parameter(Mandatory=$True)] [string]$SendComputerName,
    [Parameter(Mandatory=$True)] [string]$CommandsDir,
    [Parameter(Mandatory=$False)] [string]$Bcleanup = $False, 
    [Parameter(Mandatory=$False)] [string]$Toolname = "ntttcp", 
    [Parameter(Mandatory=$False)] [PSCredential] $SendComputerCreds = [System.Management.Automation.PSCredential]::Empty,
    [Parameter(Mandatory=$False)] [PSCredential] $RecvComputerCreds = [System.Management.Automation.PSCredential]::Empty
    )
    [bool] $gracefulCleanup = $False

    [System.IO.TextReader] $recvCommands = $null
    [System.IO.TextReader] $sendCommands = $null

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
            Write-Host "Error connecting to Host: $($RecvComputerName)"
            return
        }

        # Establish the Remote PS session with Sender
        $sendPSSession = New-PSSession -ComputerName $SendComputerName @sendCredSplat

        if($sendPSsession -eq $null) {
            Write-Host "Error connecting to Host: $($SendComputerName)"
            return
        }

        # Construct the input file to read for commands.
        $sendCmdFile = Join-Path -Path $CommandsDir -ChildPath "\$Toolname\$Toolname.Commands.Send.txt"
        $recvCmdFile = Join-Path -Path $CommandsDir -ChildPath "\$Toolname\$Toolname.Commands.Recv.txt"

        # Ensure that remote machines have the directory created for results gathering. 
        $recvFolderExists = Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir)
        $sendFolderExists = Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir)

        # Clean up the Receiver/Sender folders on remote machines, if they exist so that we dont capture any stale logs
        Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockRemoveFileFolder -ArgumentList "$CommandsDir\Receiver"
        Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockRemoveFileFolder -ArgumentList "$CommandsDir\Sender"

        #Create dirs and subdirs for each of the supported tools
        Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir+"\Receiver\ntttcp\tcp")
        Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir+"\Sender\ntttcp\tcp")
        Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir+"\Receiver\ntttcp\udp")
        Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir+"\Sender\ntttcp\udp")
        Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir+"\Receiver\latte")
        Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir+"\Sender\latte")

        #copy the tool exe to the remote machines
        Copy-Item -Path "$toolpath\$toolexe" -Destination "$CommandsDir\Receiver" -ToSession $recvPSSession
        Copy-Item -Path "$toolpath\$toolexe" -Destination "$CommandsDir\Sender" -ToSession $sendPSSession

        # Setup firewall rules so that traffic can go through
        Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockEnableFirewallRules -ArgumentList ("Allow$Toolname", "$CommandsDir\Receiver\$toolexe")
        Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockEnableFirewallRules -ArgumentList ("Allow$Toolname", "$CommandsDir\Sender\$toolexe")

        $recvCommands = [System.IO.File]::OpenText($recvCmdFile)
        $sendCommands = [System.IO.File]::OpenText($sendCmdFile)

        while(($null -ne ($recvCmd = $recvCommands.ReadLine())) -and ($null -ne ($sendCmd = $sendCommands.ReadLine()))) {

            #change the command to add path to tool
            $recvCmd =  $recvCmd -ireplace [regex]::Escape("$toolexe"), "$CommandsDir\$toolexe"
            $sendCmd =  $sendCmd -ireplace [regex]::Escape("$toolexe"), "$CommandsDir\$toolexe"

            # Work here to invoke recv commands
            # Since we want the files to get generated under a subfolder, we replace the path to include the subfolder
            $recvCmd =  $recvCmd -ireplace [regex]::Escape($CommandsDir), "$CommandsDir\Receiver"
            Write-Host "Invoking Cmd - Machine: $recvComputerName Command: $recvCmd"
            Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockRunToolCmd -ArgumentList $recvCmd

            # Work here to invoke send commands
            # Since we want the files to get generated under a subfolder, we replace the path to include the subfolder
            $sendCmd =  $sendCmd -ireplace [regex]::Escape($CommandsDir), "$CommandsDir\Sender"
            Write-Host "Invoking Cmd - Machine: $sendComputerName Command: $sendCmd"
            Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockRunToolCmd -ArgumentList $sendCmd

            # non blocking loop to check if the process
            # TODO : replace 30 second sleep with the value from tool.config file
            $timeout = new-timespan -Seconds 30
            $sw = [diagnostics.stopwatch]::StartNew()
            while ($sw.elapsed -lt $timeout){
                $checkRecvProcessExit = Invoke-Command -Session $recvPSSession -ScriptBlock $CheckProcessExitScriptBlock -ArgumentList "$Toolname"
                $checkSendProcessExit = Invoke-Command -Session $sendPSSession -ScriptBlock $CheckProcessExitScriptBlock -ArgumentList "$Toolname"

                if (($checkRecvProcessExit -eq $null)-and ($checkRecvProcessExit -eq $null)){
                    write-host "$Toolname exited on both Src and Dest machines"
                    break
                }
                start-sleep -seconds 5
            }

        #Since time is up, clean up any processes that failed to exit gracefully so that the new commands can be issued
        Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockTaskKill -ArgumentList $toolexe
        Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockTaskKill -ArgumentList $toolexe

        }

        $recvCommands.close()
        $sendCommands.close()

        Write-Host "Test runs completed. Collecting results..."

        #Zip the files on remote machines
        Invoke-Command -Session $recvPSSession -ScriptBlock $CreateZipScriptBlock -ArgumentList ("$CommandsDir\Receiver\$Toolname", "$CommandsDir\Recv.zip")
        Invoke-Command -Session $sendPSSession -ScriptBlock $CreateZipScriptBlock -ArgumentList ("$CommandsDir\Sender\$Toolname", "$CommandsDir\Send.zip")

        #copy the zip files from remote machines to the current (orchestrator) machines
        Copy-Item -Path "$CommandsDir\Recv.zip" -Destination ("{0}\{1}_Receiver.zip" -f $CommandsDir, $Toolname) -FromSession $recvPSSession
        Copy-Item -Path "$CommandsDir\Send.zip" -Destination ("{0}\{1}_Sender.zip" -f $CommandsDir, $Toolname) -FromSession $sendPSSession

        Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockRemoveFileFolder -ArgumentList "$CommandsDir\Recv.zip"
        Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockRemoveFileFolder -ArgumentList "$CommandsDir\Send.zip"

        if ($Bcleanup -eq $True) { 
            Write-Host "Cleaning up folders on Machine: $recvComputerName"

            #clean up the folders and files we created
            if($recvFolderExists -eq $false) {
                 # The folder never existed in the first place. we need to clean up the directories we created
                 Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockRemoveFolderTree -ArgumentList "$CommandsDir"
            } else {
                # this folder existed earlier on the machine. Leave the directory alone
                # Remove just the child directories and the files we created. 
                Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockRemoveFileFolder -ArgumentList "$CommandsDir\Receiver"
                Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockRemoveFileFolder -ArgumentList "$CommandsDir\Receiver.zip"
            }

            Write-Host "Cleaning up folders on Machine: $sendComputerName"

            if($sendFolderExists -eq $false) {
                 Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockRemoveFolderTree -ArgumentList "$CommandsDir"
            } else {
                # this folder existed earlier on the machine. Leave the directory alone
                # Remove just the child directories and the files we created. Leave the directory alone
                Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockRemoveFileFolder -ArgumentList "$CommandsDir\Sender"
                Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockRemoveFileFolder -ArgumentList "$CommandsDir\Sender.zip"
            }
        } # if ($Bcleanup -eq $true)
        $gracefulCleanup = $True
    } # end try
    catch {
       Write-Host "Exception $($_.Exception.Message) in $($MyInvocation.MyCommand.Name)"
    }
    finally {
        if($gracefulCleanup -eq $False)
        {
            if ($recvCommands -ne $null) {$recvCommands.close()}
            if ($sendCommands -ne $null) {$sendCommands.close()}

            Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockTaskKill -ArgumentList $toolexe
            Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockTaskKill -ArgumentList $toolexe

        }

        Write-Host "Cleaning up the firewall rules that were created as part of script run..."
        # Clean up the firewall rules that this script created
        Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockCleanupFirewallRules -ArgumentList (("Allow{0}In" -f $Toolname))
        Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockCleanupFirewallRules -ArgumentList (("Allow{0}Out" -f $Toolname))

        Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCleanupFirewallRules -ArgumentList (("Allow{0}In" -f $Toolname))
        Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCleanupFirewallRules -ArgumentList (("Allow{0}Out" -f $Toolname))

        Write-Host "Cleaning up Remote PS Sessions"
        # Clean up the PS Sessions
        Remove-PSSession $sendPSSession  -ErrorAction Ignore
        Remove-PSSession $recvPSSession  -ErrorAction Ignore

    } #finally
} # ProcessToolCommands()
