
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
    Add-Content $LogFile -Value "$Stamp $LevelValue $Message"
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

        egosh user logon -u Admin -x $SymphonyPass

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
####################################################################
## Join a machine into an AD Domain
###################################################################
#>
Function Join-Ad-Domain {
    [CmdletBinding()]
       param (
        [Parameter(Mandatory = $true)]
            [string]$ADDNSServer, # IP Address of DNS Server.
        [Parameter(Mandatory = $true)]
            [string]$DomainName, # Domain name to join
        [Parameter(Mandatory = $false)]
            [string]$JoinUser,  # Domain user to join machines into a domain
        [Parameter(Mandatory = $false)]
            [string]$JoinUserPassword # Password of the join user
       )
   
    ### Set DNS Client for alternative aliases
    Set-DnsClientServerAddress -InterfaceAlias "Ethernet*" -ServerAddresses ($ADDNSServer)

    $password = ConvertTo-SecureString $JoinUserPassword -AsPlainText -Force
    $Cred = New-Object System.Management.Automation.PSCredential ($JoinUser, $password)
    Add-Computer -DomainName $DomainName -Credential $Cred -Force

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
            $NumAttemps++
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
##    -ADDNSServer "172.200.2.13" -DomainName "citihpc.com" -JoinUser <user> -JoinUserPassword <password>
#################################################################
#>

Function Deploy-Worker {
     [CmdletBinding()]
       param (
        [Parameter(Mandatory = $true)]
            [string]$MasterList, # space-delimited FQDNs for the primary and secondary masters
        [Parameter(Mandatory = $true)]
            [string]$DNSSuffix,  # DNS Zone name (us-east-1.eqt.citi.ibmcloud)
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
            [string]$ADDNSServer, # AD DNS IP Server (if we want to join this worker into a domain)
        [Parameter(Mandatory = $false)]
            [string]$DomainName, # Domain name to join
        [Parameter(Mandatory = $false)]
            [string]$JoinUser,  # Domain user to join machines into a domain
        [Parameter(Mandatory = $false)]
            [string]$JoinUserPassword, # Password of the join user
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
    $DecodedJoinUserPass=[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($JoinUserPassword))

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

        if ($ADDNSServer -ne "") {
            Write-Log -Level Info "(Deploy-Worker) Checking if this machine is part of domain"
            $partOfDomain=(Get-WmiObject -Class Win32_ComputerSystem).PartOfDomain

            if ($partOfDomain -eq $false) {
                Join-Ad-Domain -ADDNSServer $ADDNSServer -DomainName $DomainName -JoinUser $JoinUser -JoinUserPassword $DecodedJoinUserPass
                Write-Log -Level Info "(Deploy-Worker) Machine added to domain $DomainName, restart and execute the script again (exit 1003)"
                exit 1003
            } else {
                Write-Log -Level Info "(Deploy-Worker) Machine is part of domain $DomainName"
            }
        }
        Write-Log -Level Info "(Deploy-Worker) Adding DNS search suffix to $DNSSuffix"
        Set-DnsClientGlobalSetting -SuffixSearchList @($DNSSuffix)

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


