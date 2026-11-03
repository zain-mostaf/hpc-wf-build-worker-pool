# Terraform selects the share before invoking this script:
# odd worker suffix -> first share; even worker suffix -> second share.
# A global mapping is required for worker services and interactive sessions.
#
# All SMB values come from Terraform:
#   -SharePath   \\10.136.64.26\wf_scale_share
#   -User        smb_user       (bare local account, e.g. wfuser)
#   -Password    smb_password
#   -ServerName  smb_server_name (file server computer name, e.g. WFFILESRV) - recommended
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\\\\[^\\]+\\[^\\]+')]
    [string]$SharePath,
    [string]$DriveLetter = 'Z:',
    [string]$User,
    [string]$Password,
    [string]$ServerName,
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
$IsIp = $Server -match '^\d{1,3}(\.\d{1,3}){3}$'

# --- Build the list of account formats to try -------------------------------
# Workgroup (no domain): a bare account or "<IP>\user" often yields error 1312
# with global mappings. The reliable form is "<server computer name>\user".
function Get-ServerComputerName {
    param([string]$Name, [bool]$IsIpAddress)
    if (-not [string]::IsNullOrWhiteSpace($Name)) { return $Name.Trim().Split('.')[0] }
    if (-not $IsIpAddress) { return $Server.Split('.')[0] }
    try {   # reverse DNS
        $h = [System.Net.Dns]::GetHostEntry($Server).HostName
        if ($h) { return $h.Split('.')[0] }
    } catch { }
    try {   # NetBIOS name table
        $line = nbtstat -A $Server 2>$null | Where-Object { $_ -match '<00>\s+UNIQUE' } | Select-Object -First 1
        if ($line) { return ($line.Trim() -split '\s+')[0] }
    } catch { }
    return $null
}

$Candidates = New-Object System.Collections.Generic.List[string]
if ($User -match '[\\@]') {
    $Candidates.Add($User)                      # caller gave a qualified name: use as-is
} else {
    $ResolvedName = Get-ServerComputerName -Name $ServerName -IsIpAddress $IsIp
    if ($ResolvedName) { $Candidates.Add("$ResolvedName\$User") }
    $Candidates.Add("$Server\$User")            # IP or host \ user
    $Candidates.Add($User)                      # bare account
}
$Candidates = [string[]]($Candidates | Select-Object -Unique)
Write-MountLog ("Account formats to try: " + ($Candidates -join ', '))

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

# Stale SYSTEM connections to this server with other credentials cause 1219/1312.
# Only touches connections to the selected server, never other servers.
& net.exe use "\\$Server" /delete /y 2>&1 | Out-Null
& cmdkey.exe /delete:$Server 2>&1 | Out-Null

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
            Remove-SmbGlobalMapping -LocalPath $DriveLetter -Force -ErrorAction SilentlyContinue
        }
    }
    if ($Attempt -lt $Attempts) { Start-Sleep -Seconds $WaitSeconds }
}

# --- Diagnostics: error 1312 hides the real reason; net use shows it ---------
foreach ($Account in $Candidates) {
    $Out = & net.exe use $SharePath $Password "/user:$Account" 2>&1 | Out-String
    Write-MountLog "Diagnostic net use as '$Account': $($Out.Trim())"
    & net.exe use $SharePath /delete /y 2>&1 | Out-Null
}

throw "Could not globally mount $SharePath as $DriveLetter after $Attempts attempts. Last error: $LastFailure"