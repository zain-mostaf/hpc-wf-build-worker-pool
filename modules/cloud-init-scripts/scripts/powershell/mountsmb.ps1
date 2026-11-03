# Terraform selects the share before invoking this script:
# odd worker suffix -> first share; even worker suffix -> second share.
# A global mapping is required for worker services and interactive sessions.
#
# All SMB values come from Terraform:
#   -SharePath   \\10.136.64.26\wf_scale_share
#   -User        smb_user       (bare local account, e.g. wfuser)
#   -Password    smb_password
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\\\\[^\\]+\\[^\\]+')]
    [string]$SharePath,
    [string]$DriveLetter = 'Z:',
    [string]$User,
    [string]$Password,
    [ValidateRange(1, 20)]
    [int]$Attempts = 5,
    [ValidateRange(0, 300)]
    [int]$WaitSeconds = 15
)

$ErrorActionPreference = 'Stop'
$DriveLetter = $DriveLetter.TrimEnd(':') + ':'
if ($DriveLetter -notmatch '^[A-Za-z]:$') {
    throw 'DriveLetter must be a single drive letter, for example Z:.'
}

function Write-MountLog([string]$Message) {
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log -Level Info "(mountsmb) $Message"
    } else {
        Write-Host "$(Get-Date -Format 'yyyy/MM/dd HH:mm:ss') (mountsmb) $Message"
    }
}

if ([string]::IsNullOrWhiteSpace($User) -or [string]::IsNullOrEmpty($Password)) {
    throw 'SMB global mapping requires smb_user and smb_password.'
}

$Server = ($SharePath.TrimStart('\') -split '\\')[0]
$User = $User.Trim()
$Candidates = @($User)
Write-MountLog "Using configured SMB account $User without hostname discovery"

$SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force

# --- Pre-checks on the drive letter -----------------------------------------
$Existing = Get-SmbGlobalMapping -ErrorAction Stop |
    Where-Object { $_.LocalPath -eq $DriveLetter }
if ($Existing -and $Existing.RemotePath -ne $SharePath) {
    throw "$DriveLetter is mapped to another share; refusing to replace it."
}
if ($Existing -and $Existing.Status -eq 'OK' -and (Test-Path "$DriveLetter\")) {
    Write-MountLog "$SharePath is already accessible as $DriveLetter"
    return
}
if (-not $Existing -and (Test-Path "$DriveLetter\")) {
    # Replace only a session mapping at the requested letter to the same share.
    $SessionMapping = Get-SmbMapping -ErrorAction Stop |
        Where-Object { $_.LocalPath -eq $DriveLetter }
    if ($SessionMapping -and $SessionMapping.RemotePath -eq $SharePath) {
        Remove-SmbMapping -LocalPath $DriveLetter -Force -UpdateProfile -ErrorAction Stop
    } else {
        throw "$DriveLetter is already in use by another volume or share."
    }
}

# --- Mount with retries ------------------------------------------------------
$LastFailure = 'No mapping attempt completed.'
for ($Attempt = 1; $Attempt -le $Attempts; $Attempt++) {
    Write-MountLog "Attempt $Attempt of ${Attempts}: mounting $SharePath as $DriveLetter"

    if (-not (Test-NetConnection -ComputerName $Server -Port 445 -InformationLevel Quiet -WarningAction SilentlyContinue)) {
        $LastFailure = "TCP 445 to $Server not reachable."
        Write-MountLog $LastFailure
        if ($Attempt -lt $Attempts) { Start-Sleep -Seconds $WaitSeconds }
        continue
    }

    foreach ($Account in $Candidates) {
        $CreatedMapping = $false
        try {
            $Mapping = Get-SmbGlobalMapping -ErrorAction Stop |
                Where-Object { $_.LocalPath -eq $DriveLetter }
            if ($Mapping -and $Mapping.RemotePath -ne $SharePath) {
                throw "$DriveLetter is globally mapped to another share."
            }
            if ($Mapping) {
                # Stale or unhealthy mapping from an earlier failed try: recreate.
                Remove-SmbGlobalMapping -LocalPath $DriveLetter -Force -ErrorAction Stop
            }

            $Credential = New-Object System.Management.Automation.PSCredential ($Account, $SecurePassword)
            New-SmbGlobalMapping -RemotePath $SharePath -LocalPath $DriveLetter `
                -Credential $Credential -Persistent $true -ErrorAction Stop | Out-Null
            $CreatedMapping = $true

            $Verified = Get-SmbGlobalMapping -ErrorAction Stop |
                Where-Object { $_.LocalPath -eq $DriveLetter -and $_.RemotePath -eq $SharePath -and $_.Status -eq 'OK' }
            if (-not $Verified -or -not (Test-Path "$DriveLetter\")) {
                throw 'Global mapping was not accessible after creation.'
            }
            Write-MountLog "$SharePath globally mapped as $DriveLetter using account format '$Account'"
            return
        } catch {
            $LastFailure = "[$Account] $($_.Exception.Message) [$($_.FullyQualifiedErrorId)]"
            Write-MountLog "Global mount failed: $LastFailure"
            if ($CreatedMapping) {
                $FailedMapping = Get-SmbGlobalMapping -ErrorAction SilentlyContinue |
                    Where-Object { $_.LocalPath -eq $DriveLetter -and $_.RemotePath -eq $SharePath }
                if ($FailedMapping) {
                    Remove-SmbGlobalMapping -LocalPath $DriveLetter -Force -ErrorAction SilentlyContinue
                }
            }
            # Repeating a rejected identity can lock the account. Retry network
            # availability, but stop on authentication/session or credential conflicts.
            if ($_.FullyQualifiedErrorId -match '(^|\D)(86|1326|1330|1331|1909|1219|1312)(\D|$)') {
                throw "SMB authentication/session setup failed for $Account. Verify the configured SMB account and server-side authentication logs. $LastFailure"
            }
        }
    }
    if ($Attempt -lt $Attempts) { Start-Sleep -Seconds $WaitSeconds }
}

throw "Could not globally mount $SharePath as $DriveLetter after $Attempts attempts. Last error: $LastFailure"
