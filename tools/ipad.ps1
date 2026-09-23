# Helpers for talking to the jailbroken iPad over SSH (dot-source this file).
#   . .\tools\ipad.ps1
#   Invoke-IPad 'uname -a'
#   Install-IPadPackage -IpaPath .\packages\AIChat-0.1.0.ipa -DebPath .\packages\com.samcejko.aichat_0.1.0_iphoneos-arm.deb
#   Get-IPadCrashLogs
#   Get-IPadSyslog

$script:IPadKey = Join-Path $env:USERPROFILE '.ssh\ipad_ios6'
$script:IPadDefaultHost = '192.168.137.17'

function Get-IPadSshArgs {
    @('-i', $script:IPadKey, '-oHostKeyAlgorithms=+ssh-rsa', '-oStrictHostKeyChecking=accept-new', '-oConnectTimeout=10', '-oBatchMode=yes', '-oLogLevel=ERROR')
}

function Invoke-IPad {
    param([Parameter(Mandatory = $true)][string]$Command, [string]$IPadHost = $script:IPadDefaultHost)
    $sshArgs = Get-IPadSshArgs
    & ssh.exe @sshArgs "root@$IPadHost" $Command
}

function Copy-ToIPad {
    param([Parameter(Mandatory = $true)][string]$LocalPath, [Parameter(Mandatory = $true)][string]$RemotePath, [string]$IPadHost = $script:IPadDefaultHost)
    $sshArgs = Get-IPadSshArgs
    & scp.exe @sshArgs $LocalPath "root@${IPadHost}:$RemotePath"
    if ($LASTEXITCODE -ne 0) { throw "scp failed for $LocalPath" }
}

function Copy-FromIPad {
    param([Parameter(Mandatory = $true)][string]$RemotePath, [Parameter(Mandatory = $true)][string]$LocalPath, [string]$IPadHost = $script:IPadDefaultHost)
    $sshArgs = Get-IPadSshArgs
    & scp.exe @sshArgs -r "root@${IPadHost}:$RemotePath" $LocalPath
}

function Install-IPadPackage {
    param([string]$IpaPath, [string]$DebPath, [string]$IPadHost = $script:IPadDefaultHost)
    $installed = $false
    if ($IpaPath -and (Test-Path $IpaPath)) {
        Write-Host "Installing IPA $IpaPath ..."
        Copy-ToIPad -LocalPath $IpaPath -RemotePath '/tmp/aichat.ipa' -IPadHost $IPadHost
        $out = Invoke-IPad -IPadHost $IPadHost -Command 'if command -v ipainstaller >/dev/null 2>&1; then ipainstaller -f /tmp/aichat.ipa && echo IPA_OK; elif command -v appinst >/dev/null 2>&1; then appinst /tmp/aichat.ipa && echo IPA_OK; else echo NO_INSTALLER; fi' 2>&1 | Out-String
        Write-Host $out
        if ($out -match 'IPA_OK') { $installed = $true }
    }
    if (-not $installed -and $DebPath -and (Test-Path $DebPath)) {
        Write-Host "Installing DEB $DebPath (falls back to /Applications) ..."
        Copy-ToIPad -LocalPath $DebPath -RemotePath '/tmp/aichat.deb' -IPadHost $IPadHost
        $out = Invoke-IPad -IPadHost $IPadHost -Command 'dpkg -i /tmp/aichat.deb 2>&1; uicache 2>/dev/null; echo DEB_DONE' 2>&1 | Out-String
        Write-Host $out
        if ($out -match 'DEB_DONE') { $installed = $true }
    }
    if (-not $installed) { throw "Nothing installed" }
    Write-Host "Done. Tap the AI Chat icon on the iPad."
}

function Get-IPadCrashLogs {
    param([string]$IPadHost = $script:IPadDefaultHost, [string]$OutDir = '')
    if (-not $OutDir) { $OutDir = Join-Path (Get-Location) 'packages\crashlogs' }
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $list = Invoke-IPad -IPadHost $IPadHost -Command 'ls -t /var/mobile/Library/Logs/CrashReporter/ 2>/dev/null | grep -i aichat | head -n 5'
    foreach ($f in ($list -split "`n" | Where-Object { $_.Trim() })) {
        $name = $f.Trim()
        Copy-FromIPad -IPadHost $IPadHost -RemotePath "/var/mobile/Library/Logs/CrashReporter/$name" -LocalPath (Join-Path $OutDir $name)
        Write-Host "Fetched $name"
    }
    Get-ChildItem $OutDir -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

function Get-IPadSyslog {
    param([string]$IPadHost = $script:IPadDefaultHost, [int]$Lines = 200)
    Invoke-IPad -IPadHost $IPadHost -Command "if [ -f /var/log/syslog ]; then grep -i aichat /var/log/syslog | tail -n $Lines; else echo 'no /var/log/syslog (install the syslogd package from Cydia)'; fi"
}
