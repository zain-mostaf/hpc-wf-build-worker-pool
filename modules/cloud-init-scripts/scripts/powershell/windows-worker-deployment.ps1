
Function Write-Log {
    <#
    .SYNOPSIS
        Writes log message to log file.
    .DESCRIPTION
        This function accepts a log message and optional log level,
        then adds a timestamped log message to the log file.
    .PARAMETER $Message
        Message string that will be added to the log file.
    .PARAMETER $Level
        Optional log level parameter that must be "Error", "Warn", or "Info".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]
        $Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Error", "Warn", "Info")]
        [string]
        $Level
    )

    $LevelValue = @{Error = "Error"; Warn = "Warning"; Info = "Information"}[$Level]
    $LogFile = "$HOME\Desktop\WindowsWorker.log"
    $Stamp = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")
    ### The Desktop folder may not exist for the cloud-init user profile, so the log is also kept in the deployment folder
    Add-Content $LogFile -Value "$Stamp $LevelValue $Message" -ErrorAction SilentlyContinue
    Add-Content "c:\symphony-deployment-scripts\WindowsWorker.log" -Value "$Stamp $LevelValue $Message" -ErrorAction SilentlyContinue
}


<#################################################################
## Register cluster administrator password.
##################################################################>
Function RegisterPassword-ForWindowsExecutionUser($SymphonyPass) {
    try {
        #Check if LIM Service is Started, Start if Stopped
        $LIMServiceStatus = (Get-Service -Name "LIM").Status

        if ($LIMServiceStatus -eq "Stopped") {
            Start-Service -Name "LIM"
        }

        ### LIM may not be able to contact the primary host right after start (DNS/network), retry the logon
        $LoggedOn = $false
        for ($i = 1; $i -le 10 -and -not $LoggedOn; $i++) {
            egosh user logon -u Admin -x $SymphonyPass
            if ($LASTEXITCODE -eq 0) {
                $LoggedOn = $true
            } else {
                Write-Log -Level Warn "(RegisterPassword-ForWindowsExecutionUser) egosh logon failed (attempt $i of 10), retrying in 15 seconds"
                Start-Sleep -Seconds 15
            }
        }

        Write-Log -Level Info "(RegisterPassword-ForWindowsExecutionUser) Registering Password for windows execution user"

        egosh ego execpasswd -u .\egoadmin -x Symphony@123 -noverify

        Write-Log -Level Info "(RegisterPassword-ForWindowsExecutionUser) Registered Password for windows execution user"
    } catch {
        Write-Log -Level Error $_
    }
}

<#################################################################
## Restart LIM Service.
##################################################################>
Function Restart-LIMService {
    try {
        Write-Log -Level Info "(Restart-LIMService) Restarting LIM Service"

        Restart-Service -Name "LIM"

        Write-Log -Level Info "(Restart-LIMService) LIM Service Restarted"
    } catch {
        Write-Log -Level Error $_
    }
}

<#################################################################
## Rename the computer name from the original name in the image.
##################################################################>
Function Modify-ComputerName {
    [CmdletBinding()]
        param(
            [Parameter(Mandatory = $true)]
            [string]$ComputerName
        )
    try {
        $CurrentComputerName = hostname
        Write-Log -Level Info "(Modify-ComputerName) Modifying the Computer Name to $ComputerName"
        $Output = ECHO Y | NETDOM RENAMECOMPUTER $CurrentComputerName /NewName:$ComputerName
        $OutputString = Out-String -InputObject $Output
        Write-Log -Level Info $OutputString
    } catch {
        Write-Log -Level Error $_
    }
}

<#
########################################################################
# SMB mounting is implemented in mountsmb.ps1.
# cloud-init runs this script in an impersonated session where New-SmbGlobalMapping fails with
# "A specified logon session does not exist" (error 1312), so mountsmb.ps1 is executed as SYSTEM
# through a temporary scheduled task. The global mapping is then visible to every session (RDP included)
# and persists after reboot. A mount failure is logged but does not stop the worker deployment.
########################################################################
#>
Function ConvertTo-PsLiteral([string]$Value) {
    return "'" + ($Value -replace "'", "''") + "'"
}

Function Mount-SmbDriveAsSystem {
    [CmdletBinding()]
      param(
        [Parameter(Mandatory = $true)]
            [string]$SharePath,
        [Parameter(Mandatory = $true)]
            [string]$DriveLetter,
        [Parameter(Mandatory = $false)]
            [string]$User,
        [Parameter(Mandatory = $false)]
            [string]$Password,
        [Parameter(Mandatory = $false)]
            [string]$ServerName
      )

    $Folder = "c:\symphony-deployment-scripts"
    $TaskName = "MountSmbGlobalMapping"
    $Wrapper = "$Folder\mountsmb-task.ps1"
    $TaskLog = "$Folder\mountsmb.log"
    $ResultFile = "$Folder\mountsmb.result"

    try {
        $PassB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Password))
        $Lines = @(
            "`$ErrorActionPreference = 'Stop'",
            "try {",
            "  `$Pass = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$PassB64'))",
            "  & '$Folder\mountsmb.ps1' -SharePath $(ConvertTo-PsLiteral $SharePath) -DriveLetter $(ConvertTo-PsLiteral $DriveLetter) -User $(ConvertTo-PsLiteral $User) -Password `$Pass -ServerName $(ConvertTo-PsLiteral $ServerName) *>&1 | Out-File '$TaskLog' -Append -Encoding ascii",
            "  'OK' | Set-Content '$ResultFile'",
            "} catch {",
            "  ('FAILED: ' + `$_) | Out-File '$TaskLog' -Append -Encoding ascii",
            "  ('FAILED: ' + `$_) | Set-Content '$ResultFile'",
            "}"
        )
        Set-Content -Path $Wrapper -Value $Lines
        Remove-Item $ResultFile, $TaskLog -Force -ErrorAction SilentlyContinue

        Write-Log -Level Info "(Mount-SmbDriveAsSystem) Mounting $SharePath as $DriveLetter as SYSTEM (scheduled task $TaskName)"
        $Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$Wrapper`""
        $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        Register-ScheduledTask -TaskName $TaskName -Action $Action -Principal $Principal -Force | Out-Null
        Start-ScheduledTask -TaskName $TaskName

        ### mountsmb.ps1 retries 5 times with 15 seconds between attempts: wait up to ~7 minutes
        for ($w = 0; $w -lt 210 -and -not (Test-Path $ResultFile); $w++) { Start-Sleep -Seconds 2 }

        if (Test-Path $TaskLog) {
            foreach ($Line in (Get-Content $TaskLog)) { Write-Log -Level Info "(Mount-SmbDriveAsSystem) $Line" }
        }

        $TaskOutput = if (Test-Path $ResultFile) { (Get-Content $ResultFile -Raw).Trim() } else { "no result (timeout)" }
        $Mapping = Get-SmbGlobalMapping -ErrorAction SilentlyContinue | Where-Object { $_.LocalPath -eq $DriveLetter }
        if ($TaskOutput -eq "OK" -and $Mapping) {
            Write-Log -Level Info "(Mount-SmbDriveAsSystem) $($Mapping.RemotePath) mapped as $DriveLetter, status: $($Mapping.Status)"
        } else {
            Write-Log -Level Error "(Mount-SmbDriveAsSystem) Could not mount $SharePath as ${DriveLetter} - $TaskOutput"
        }
    } catch {
        Write-Log -Level Error "(Mount-SmbDriveAsSystem) $_"
    } finally {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item $Wrapper, $ResultFile -Force -ErrorAction SilentlyContinue
    }
}


<#
########################################################################
# SMB / performance tuning
#  - lists the SMB shares of the machine
#  - enables SMB Multichannel on the SMB client
#  - activates the High performance power plan
#  - sets LanmanWorkstation MaxCmds to 2048 (needs a reboot / workstation restart to take effect)
########################################################################
#>
Function Set-SmbPerformanceTuning {
    [CmdletBinding()]
      param()

    try {
        Write-Log -Level Info "(Set-SmbPerformanceTuning) Listing SMB shares"
        $Shares = Get-SmbShare | Select-Object Name, Path, CompressData, EnableMultiChannel | Out-String
        Write-Log -Level Info $Shares

        Write-Log -Level Info "(Set-SmbPerformanceTuning) Enabling SMB Multichannel"
        Set-SmbClientConfiguration -EnableMultiChannel $true -Force

        Write-Log -Level Info "(Set-SmbPerformanceTuning) Activating High performance power plan"
        $HighPerfGuid = powercfg /List | ForEach-Object { if ($_.Contains("High performance")) { $_.Split()[3] } }
        if (![String]::IsNullOrWhiteSpace($HighPerfGuid)) {
            powercfg /SetActive $HighPerfGuid
        } else {
            Write-Log -Level Warn "(Set-SmbPerformanceTuning) High performance power plan not found"
        }

        Write-Log -Level Info "(Set-SmbPerformanceTuning) Setting LanmanWorkstation MaxCmds to 2048"
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -Name "MaxCmds" -Value 2048 -Force
    } catch {
        Write-Log -Level Error $_
    }
}

<#
########################################################################
# Login and close resource
########################################################################
#>
Function Close-Resource {
    [CmdletBinding()]
      param(
        [Parameter(Mandatory = $true)]
            [string]$SymphonyPass  # Symphony password
      )
    
    $NumAttempts=0
    $Hostname=hostname

    while($NumAttempts -lt 15) {
        egosh user logon -u Admin -x $SymphonyPass
        $Result=egosh resource list -ll | findstr "$Hostname"

        if($Result.length -gt 0) {
            egosh resource close "$Hostname"
            break
        } else {
            $NumAttempts++
            Start-Sleep -Seconds 10
        }
    }
}

<#
#################################################################
## Main Script logic
## . win-worker.ps1
## Deploy-Worker -MasterList "<masterList>" -ComputerName "<workerName>" 
##    -DNSSuffix "<DNSSuffix>" -BasePort "<BasePort>" -SymphonyPass <Password>
##    -ScaleManagerServer <Scale_Manager> -ClusterID <clusterId> 
#################################################################
#>

Function Deploy-Worker {
     [CmdletBinding()]
       param (
        [Parameter(Mandatory = $true)]
            [string]$MasterList, # space-delimited FQDNs for the primary and secondary masters
        [Parameter(Mandatory = $true)]
            [string]$DNSSuffix,  # DNS search suffix(es), comma-separated (ex: us-east-1.wf.ibmcloud)
        [Parameter(Mandatory = $true)]
            [string]$ComputerName, # FQDN of this computer
        [Parameter(Mandatory = $true)]
            [string]$BasePort,   # Symphony Base port (i.e, 9100)
        [Parameter(Mandatory = $true)]
            [string]$SymphonyPass, # Symphony Password for egoadmin user registration
        [Parameter(Mandatory = $true)]
            [string]$SSLPort, ## SSL Port number or NO_SSL for no SSL setup
        [Parameter(Mandatory = $false)]
            [string]$ScaleManagerServer, ## Only required for SSL. FQDN of Scale Manager to download certificates from
        [Parameter(Mandatory = $false)]
            [string]$ClusterID, ## Only required for SSL. Cluster ID used in the GPFS file system (i.e. citi-wdcaz1)
        [Parameter(Mandatory = $false)]
            [string]$SmbSharePath,     # (Optional) UNC path of an SMB share to mount (ex: \\server\share)
        [Parameter(Mandatory = $false)]
            [string]$SmbDriveLetter,   # (Optional) Drive letter for the SMB share (default Z:)
        [Parameter(Mandatory = $false)]
            [string]$SmbServerName,    # Local account authority for the selected SMB server
        [Parameter(Mandatory = $false)]
            [string]$SmbUser,          # (Optional) User to connect to the SMB share
        [Parameter(Mandatory = $false)]
            [string]$SmbPassword,      # (Optional) Base64-encoded password of the SMB user
        [Parameter(Mandatory = $false)]
            [string]$ClosedResource,   # Checks if resource should be closed
        [Parameter(Mandatory = $false)]
            [string]$NoStartSymphonyConfig  # If this variable is true, Symphony setup will be skipped and cloud-init script will return 0
       )

    $DeploymentScriptsFolder = "c:\symphony-deployment-scripts"
    $EgoConfigFilePath = "C:\Program Files\IBM\SpectrumComputing\kernel\conf\ego.conf"
    $EgoBkpConfigFilePath = "C:\Program Files\IBM\SpectrumComputing\kernel\conf\ego.conf.bkp"
    $CACertLocation = "C:\Program Files\IBM\SpectrumComputing\wlp\usr\shared\resources\security\cacert.pem"

    $DecodedSymphonyPass=[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($SymphonyPass))
    ##### Set Ehternet interface MTU to 9000
    Set-NetAdapterAdvancedProperty -Name * -RegistryKeyword *JumboPacket -Registryvalue 9014
    netsh -f c:\symphony-deployment-scripts\netsh.txt

    $HostName = hostname
    if ($HostName -ne $ComputerName) {
        Rename-Computer -NewName $ComputerName
        Write-Log -Level Info "(Deploy-Worker) Modified the computer name, restart and execute the script again (exit 1003)"
        exit 1003
    } else {
        Write-Log -Level Info "(Deploy-Worker) Computer Name is $ComputerName, executing the remaining logic after the reboot"
        ### Search list: DNSSuffix is a comma-separated list of DNS search suffixes
        $SuffixSearchList = @($DNSSuffix -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
        Write-Log -Level Info "(Deploy-Worker) Adding DNS search suffixes: $($SuffixSearchList -join ', ')"
        Set-DnsClientGlobalSetting -SuffixSearchList $SuffixSearchList

        ### SMB / performance tuning
        Set-SmbPerformanceTuning

        ### Mount SMB share (only when a share path is informed)
        if (![String]::IsNullOrWhiteSpace($SmbSharePath)) {
            if ([String]::IsNullOrWhiteSpace($SmbDriveLetter)) { $SmbDriveLetter = "Z:" }
            $DecodedSmbPass = ""
            if (![String]::IsNullOrWhiteSpace($SmbPassword)) {
                $DecodedSmbPass = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($SmbPassword))
            }
            Mount-SmbDriveAsSystem -SharePath $SmbSharePath -DriveLetter $SmbDriveLetter -User $SmbUser -Password $DecodedSmbPass -ServerName $SmbServerName
        }

        ### Symphony setup will be skipped if flag is true
        if ($NoStartSymphonyConfig -eq $true) {
            # Ensure LIM service is stopped
            Write-Log -Level Info "(Deploy-Worker) NoStartSymphonyConfig is true, skipping Symphony config."
            Stop-Service LIM
            exit 0
        }

        #EditMasterList-EgoConfigFile -MasterList $MasterList -ContentToReplace $ContentToReplace
        #Enable-Compute-SSL -SSLPort $SSLPort -ManagerServer $ScaleManagerServer -ClusterID $ClusterID
        #Modify-EgoBasePort $BasePort

        ## Copy ego.conf to destination
        #copy $EgoConfigFilePath  $EgoBkpConfigFilePath
        copy "$DeploymentScriptsFolder\ego.conf" $EgoConfigFilePath

        ## Copy certificate only if not empty
        if (![String]::IsNullOrWhiteSpace((Get-content C:\symphony-deployment-scripts\cacert.pem))) {
             ## Keep compabitility with Linux path
            md 'C:\Program Files\IBM\SpectrumComputing\wlp\usr\shared\resources\security'
            copy "$DeploymentScriptsFolder\cacert.pem" $CACertLocation
        }
        
        RegisterPassword-ForWindowsExecutionUser -SymphonyPass $DecodedSymphonyPass
        Restart-LIMService

        if ( $ClosedResource -eq "true" ) {
            Close-Resource -SymphonyPass $DecodedSymphonyPass
        }
        Write-Log -Level Info "(Deploy-Worker) *** WORKER DEPLOYED! ***"
        . c:\symphony-deployment-scripts\windows-worker-postdeployment.ps1                                                              
        PostDeploymentTasks
        exit 0
    }
}


