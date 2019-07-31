#===============================================
# Scriptblock Util functions
#===============================================

# Allow the tools to send/recv traffic through the firewall
$scriptBlockEnableFirewallRules = {
param ($ruleName, $pathToExe)
    New-NetFirewallRule -DisplayName ($ruleName+"Out") -Direction "Out" -Action "Allow" -Program "$pathToExe"
    New-NetFirewallRule -DisplayName ($ruleName+"In") -Direction "In" -Action "Allow" -Program "$pathToExe"
}

# clean up any firewall rules that were created by the tool
$scriptBlockCleanupFirewallRules = {
param ($ruleName)
    Remove-NetFirewallRule -DisplayName "$ruleName"
}

# Set up a directory on the remote machines for results gathering.
$ScriptBlockCreateDirForResults = {
    param ($cmddir)
    $Exists = test-path $cmddir
    if (!$Exists) {
        New-Item -ItemType Directory -Force -Path "$cmddir" |Out-Null
    }
    return $Exists
} # $ScriptBlockCreateDirForResults()


# Delete file/folder on the remote machines 
$ScriptBlockRemoveFileFolder = {
    param ($arg)
    Write-Host "Running Command: Remove-Item -Force -Path $arg -Recurse -ErrorAction SilentlyContinue"
    Remove-Item -Force -Path "$arg" -Recurse -ErrorAction SilentlyContinue
} # $ScriptBlockRemoveFileFolder()


# Delete the entire folder (if empty) on the remote machines
$ScriptBlockRemoveFolderTree = {
    param ($arg)

    $parentfolder = (Get-Item $arg).Parent.FullName

    # First do as instructed. Remove-Item $arg.
    Remove-Item -Force -Path "$arg" -Recurse -ErrorAction SilentlyContinue

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
    param($line) 
    $filepath=$line.Split(' ',2)[0]
    $arg=$line.Split(' ',2)[1]
    Start-Process -FilePath "$filepath" -ArgumentList "$arg"
    Start-Sleep 10
} # $ScriptBlockRunToolCmd()


$CreateZipScriptBlock = {
    Param(
        [String] $Src,
        [String] $Out
    )
    if (Test-path $Out) {
        Remove-item $Out
    }

    Add-Type -assembly "system.io.compression.filesystem"
    [io.compression.zipfile]::CreateFromDirectory($Src, $Out)

} # $CreateZipScriptBlock()

#===============================================
# Main function
#===============================================

# ProcessCommands reads an input file of commands and orchestrates the execution of these commands on remote machines.
# This function is dependent on the output of PERFTEST.PS1 function
#for example, PERFTEST.PS1 is invoked with DestIp, SrcIp and OutDir.
# to invoke the commands that were generated above, we pass the same parameters to ProcessCommands function
# Note that we expect the directory to be pointing to the folder that was generated by perftest.ps1 under the outpurDir path supplied by the user
# Ex: ProcessCommands -RecvIpAddr "$DestIp" -SendIpAddr "$SrcIp" -CommandsDir "C:\temp\msdbg.Machine1.perftest"
Function ProcessCommands{
	param(
    [Parameter(Mandatory=$True)]  [string]$RecvIpAddr,
    [Parameter(Mandatory=$True)] [string]$SendIpAddr,
    [Parameter(Mandatory=$True)]  [string]$CommandsDir
    )

    # get the hostnames from IPAddrs:
    $RecvComputerName = [System.Net.Dns]::GetHostByAddress($RecvIpAddr).Hostname
    $SendComputerName = [System.Net.Dns]::GetHostByAddress($SendIpAddr).Hostname

    # process ntttcp commands 
    Write-Host "Processing ntttcp commands"
    ProcessNtttcpCommands -RecvComputerName $RecvComputerName -SendComputerName $SendComputerName -CommandsDir $CommandsDir

    Write-Host "Processing latte commands"
    ProcessLatteCommands -RecvComputerName $RecvComputerName -SendComputerName $SendComputerName -CommandsDir $CommandsDir

} # ProcessCommands()


#===============================================
# Internal Functions
#===============================================

#Function to process Ntttcp commands
Function ProcessNtttcpCommands{
param(
    [Parameter(Mandatory=$True)] [string]$RecvComputerName,
    [Parameter(Mandatory=$True)] [string]$SendComputerName,
    [Parameter(Mandatory=$True)] [string]$CommandsDir,
    [Parameter(Mandatory=$False)] [string]$bCleanup = $False
    )

    $toolpath = ".\ntttcp"

    # Establish the Remote PS session with Receiver
    $recvPSSession = New-PSSession -ComputerName $RecvComputerName

    if($recvPSsession -eq $null)
         {
               Write-Host "Error connecting to Host: $($RecvComputerName)"
               return
         }

    # Establish the Remote PS session with Sender
    $sendPSSession = New-PSSession -ComputerName $SendComputerName

    if($sendPSsession -eq $null)
         {
               Write-Host "Error connecting to Host: $($SendComputerName)"
               return
         }

    # Construct the input file to read for commands.
    $ntttcpCmdFile = Join-Path -Path $CommandsDir -ChildPath "\ntttcp\NTTTCP.Commands.txt"

    # Ensure that remote machines have the directory created for results gathering. 
    $recvFolderExists = Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir)
    $sendFolderExists = Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir)

    # Clean up the Receiver/Sender folders on remote machines, if they exist so that we dont capture any stale logs
    Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockRemoveFileFolder -ArgumentList "$CommandsDir\Receiver"
    Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockRemoveFileFolder -ArgumentList "$CommandsDir\Sender"

    Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir+"\Receiver\ntttcp\tcp")
    Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir+"\Sender\ntttcp\tcp")
    Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir+"\Receiver\ntttcp\udp")
    Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir+"\Sender\ntttcp\udp")
    
    #copy ntttcp to the remote machines
    Copy-Item -Path "$toolpath\ntttcp.exe" -Destination "$CommandsDir\Receiver" -ToSession $recvPSSession
    Copy-Item -Path "$toolpath\ntttcp.exe" -Destination "$CommandsDir\Sender" -ToSession $sendPSSession

    # Setup firewall rules so that traffic can go through
    Invoke-Command -Session $recvPSSession -ScriptBlock $scriptBlockEnableFirewallRules -ArgumentList ("AllowNtttcp", "$CommandsDir\Receiver\ntttcp.exe")
    Invoke-Command -Session $sendPSSession -ScriptBlock $scriptBlockEnableFirewallRules -ArgumentList ("AllowNtttcp", "$CommandsDir\Sender\ntttcp.exe")

    foreach($line in Get-Content $ntttcpCmdFile) {

        #change the command to add path to ntttcp tool
        $line =  $line -ireplace [regex]::Escape("ntttcp.exe"), "$CommandsDir\ntttcp.exe"

        # We need to check if the command is for recv or send. In either case the command will be run via remote sessions
        $sendRegex="ntttcp.exe -s"
        $recvRegex="ntttcp.exe -r"

        try
         {
            if($line -match $recvRegex){
                # Work here to invoke recv commands
                # Since we want the files to get generated under a subfolder, we replace the path to include the subfolder
                $line =  $line -ireplace [regex]::Escape($CommandsDir), "$CommandsDir\Receiver"
                Write-Host "Invoking Cmd - Machine: $recvComputerName Command: $line"
                Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockRunToolCmd -ArgumentList $line
            }
            elseif($line -match $sendRegex){
                # Since we want the files to get generated under a subfolder, we replace the path to include the subfolder
                $line =  $line -ireplace [regex]::Escape($CommandsDir), "$CommandsDir\Sender"
                Write-Host "Invoking Cmd - Machine: $sendComputerName Command: $line"
                Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockRunToolCmd -ArgumentList $line
            }
        }
        catch
        {
           Write-Host "Exception $($_.Exception.Message) in $($MyInvocation.MyCommand.Name)"
        }
    }

    # Wait for any remaining processes to exit
    Write-Host "Wait for any remaining processes to exit....."
    Start-Sleep 10

    #Time to cleanup jobs
    Invoke-Command -Session $recvPSSession -ScriptBlock {Start-Process -FilePath taskkill -ArgumentList "/f /im ntttcp.exe" -ErrorAction SilentlyContinue}
    Invoke-Command -Session $sendPSSession -ScriptBlock {Start-Process -FilePath taskkill -ArgumentList "/f /im ntttcp.exe" -ErrorAction SilentlyContinue}

    #Zip the files on remote machines
    Invoke-Command -Session $recvPSSession -ScriptBlock $CreateZipScriptBlock -ArgumentList ("$CommandsDir\Receiver", "$CommandsDir\Recv.zip")
    Invoke-Command -Session $sendPSSession -ScriptBlock $CreateZipScriptBlock -ArgumentList ("$CommandsDir\Sender", "$CommandsDir\Send.zip")

    Start-Sleep 10

    #copy the zip files from remote machines to the current (orchestrator) machines
    Copy-Item -Path "$CommandsDir\Recv.zip" -Destination "$CommandsDir\Receiver.zip" -FromSession $recvPSSession
    Copy-Item -Path "$CommandsDir\Send.zip" -Destination "$CommandsDir\Sender.zip" -FromSession $sendPSSession

    Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockRemoveFileFolder -ArgumentList "$CommandsDir\Recv.zip"
    Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockRemoveFileFolder -ArgumentList "$CommandsDir\Send.zip"

    if ($bCleanup -eq $True)
    { 
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
    } # if ($bCleanup -eq $true)

    # Clean up the firewall rules that this script created
    Invoke-Command -Session $recvPSSession -ScriptBlock $scriptBlockCleanupFirewallRules -ArgumentList ("AllowNtttcpIn")
    Invoke-Command -Session $recvPSSession -ScriptBlock $scriptBlockCleanupFirewallRules -ArgumentList ("AllowNtttcpOut")

    Invoke-Command -Session $sendPSSession -ScriptBlock $scriptBlockCleanupFirewallRules -ArgumentList ("AllowNtttcpIn")
    Invoke-Command -Session $sendPSSession -ScriptBlock $scriptBlockCleanupFirewallRules -ArgumentList ("AllowNtttcpOut")

    # Clean up the PS Sessions
    Remove-PSSession $sendPSSession  -ErrorAction Ignore
    Remove-PSSession $recvPSSession  -ErrorAction Ignore

} # ProcessNtttcpCommands()


#Function to process Latte commands
Function ProcessLatteCommands{
param(
    [Parameter(Mandatory=$True)] [string]$RecvComputerName,
    [Parameter(Mandatory=$True)] [string]$SendComputerName,
    [Parameter(Mandatory=$True)] [string]$CommandsDir,
    [Parameter(Mandatory=$False)] [string]$bCleanup = $False
    )

    $toolpath = ".\latte"


    # Establish the Remote PS session with Receiver
    $recvPSSession = New-PSSession -ComputerName $RecvComputerName

    if($recvPSsession -eq $null)
         {
               Write-Host "Error connecting to Host: $($RecvComputerName)"
               return
         }

    # Establish the Remote PS session with Sender
    $sendPSSession = New-PSSession -ComputerName $SendComputerName

    if($sendPSsession -eq $null)
         {
               Write-Host "Error connecting to Host: $($SendComputerName)"
               return
         }

    # Construct the input file to read for commands.
    $latteCmdFile = Join-Path -Path $CommandsDir -ChildPath "\latte\LATTE.Commands.txt"

    # Ensure that remote machines have the directory created for results gathering. 
    $recvFolderExists = Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir)
    $sendFolderExists = Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir)

    # Clean up the Client/Server folders on remote machines, if they exist so that we dont capture any stale logs
    Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockRemoveFileFolder -ArgumentList "$CommandsDir\Server"
    Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockRemoveFileFolder -ArgumentList "$CommandsDir\Client"

    Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir+"\Server\latte")
    Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockCreateDirForResults -ArgumentList ($CommandsDir+"\Client\latte")

    
    #copy latte.exe to the remote machines 
    Copy-Item -Path "$toolpath\latte.exe" -Destination "$CommandsDir\Server" -ToSession $recvPSSession
    Copy-Item -Path "$toolpath\latte.exe" -Destination "$CommandsDir\Client" -ToSession $sendPSSession

    # Setup firewall rules so that traffic can go through
    Invoke-Command -Session $recvPSSession -ScriptBlock $scriptBlockEnableFirewallRules -ArgumentList ("AllowLatte", "$CommandsDir\Server\latte.exe")
    Invoke-Command -Session $sendPSSession -ScriptBlock $scriptBlockEnableFirewallRules -ArgumentList ("AllowLatte", "$CommandsDir\Client\latte.exe")


    foreach($line in Get-Content $latteCmdFile) {
        #Change the command to run the latte tool locally
        $line =  $line -ireplace [regex]::Escape("latte.exe"), "$CommandsDir\latte.exe"

        # We need to check if the command is for recv or send. In either case the command will be run via remote sessions
        $clientRegex="latte.exe -c"
        $servRegex="latte.exe -s"

        try
        {
            if($line -match $servRegex){
                # Work here to invoke latte server commands
                # Since we want the files to get generated under a subfolder, we replace the path to include the subfolder
                $line =  $line -ireplace [regex]::Escape($CommandsDir), "$CommandsDir\Server"
                Write-Host "Invoking Cmd - Machine: $recvComputerName Command: $line"
                Invoke-Command -Session $recvPSSession -ScriptBlock {param($line) &cmd /C "$line"} -ArgumentList $line
            }
            elseif($line -match $clientRegex){
                # Since we want the files to get generated under a subfolder, we replace the path to include the subfolder
                $line =  $line -ireplace [regex]::Escape($CommandsDir), "$CommandsDir\Client"
                Write-Host "Invoking Cmd - Machine: $sendComputerName Command: $line"
                Invoke-Command -Session $sendPSSession -ScriptBlock {param($line) &cmd /C "$line"} -ArgumentList $line
            }
            Start-Sleep 5
        }
        catch
        {
           Write-Host "Exception $($_.Exception.Message) in $($MyInvocation.MyCommand.Name)"
        }

    } # foreach()

    # Wait for any remaining processes to exit
    Start-Sleep 10

    #Time to cleanup jobs
    Invoke-Command -Session $recvPSSession -ScriptBlock {Start-Process -FilePath taskkill -ArgumentList "/f /im latte.exe" -ErrorAction SilentlyContinue}
    Invoke-Command -Session $sendPSSession -ScriptBlock {Start-Process -FilePath taskkill -ArgumentList "/f /im latte.exe" -ErrorAction SilentlyContinue}


    #Zip the files on remote machines
    Invoke-Command -Session $recvPSSession -ScriptBlock $CreateZipScriptBlock -ArgumentList ("$CommandsDir\Server", "$CommandsDir\_server.zip")
    Invoke-Command -Session $sendPSSession -ScriptBlock $CreateZipScriptBlock -ArgumentList ("$CommandsDir\Client", "$CommandsDir\_client.zip")

    #copy the zip files from remote machines to the current (orchestrator) machines
    Copy-Item -Path "$CommandsDir\_server.zip" -Destination "$CommandsDir\Server.zip" -FromSession $recvPSSession
    Copy-Item -Path "$CommandsDir\_client.zip" -Destination "$CommandsDir\Client.zip" -FromSession $sendPSSession

    Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockRemoveFileFolder -ArgumentList "$CommandsDir\_server.zip"
    Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockRemoveFileFolder -ArgumentList "$CommandsDir\_client.zip"


    if ($bCleanup -eq $True)
    { 
        Write-Host "Cleaning up folders on Machine: $recvComputerName"

        #clean up the folders and files we created
        if($recvFolderExists -eq $false) {
             # The folder never existed in the first place. we need to clean up the directories we created
             Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockRemoveFolderTree -ArgumentList "$CommandsDir"
        } else {
            # this folder existed earlier on the machine. Leave the directory alone
            # Remove just the child directories and the files we created. 
            Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockRemoveFileFolder -ArgumentList "$CommandsDir\Server"
            Invoke-Command -Session $recvPSSession -ScriptBlock $ScriptBlockRemoveFileFolder -ArgumentList "$CommandsDir\_server.zip"
        }

        Write-Host "Cleaning up folders on Machine: $sendComputerName"

        if($sendFolderExists -eq $false) {
             Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockRemoveFolderTree -ArgumentList "$CommandsDir"
        } else {
            # this folder existed earlier on the machine. Leave the directory alone
            # Remove just the child directories and the files we created. Leave the directory alone
            Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockRemoveFileFolder -ArgumentList "$CommandsDir\Client"
            Invoke-Command -Session $sendPSSession -ScriptBlock $ScriptBlockRemoveFileFolder -ArgumentList "$CommandsDir\_client.zip"
        }
    } # if ($bCleanup -eq $true)


    # Clean up the firewall rules that this script created
    Invoke-Command -Session $recvPSSession -ScriptBlock $scriptBlockCleanupFirewallRules -ArgumentList ("AllowLatteIn")
    Invoke-Command -Session $recvPSSession -ScriptBlock $scriptBlockCleanupFirewallRules -ArgumentList ("AllowLatteOut")

    Invoke-Command -Session $sendPSSession -ScriptBlock $scriptBlockCleanupFirewallRules -ArgumentList ("AllowLatteIn")
    Invoke-Command -Session $sendPSSession -ScriptBlock $scriptBlockCleanupFirewallRules -ArgumentList ("AllowLatteOut")

    # Clean up the PS Sessions
    Remove-PSSession $sendPSSession  -ErrorAction Ignore
    Remove-PSSession $recvPSSession  -ErrorAction Ignore

    Write-Host "Done!" 

} # ProcessLatteCommands()