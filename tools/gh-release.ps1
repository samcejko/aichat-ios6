# Creates (or updates) a GitHub release for a tag and uploads packages as release assets.
# An asset with the same file name is replaced.
# Usage: .\tools\gh-release.ps1 -Repo owner/name -Token ghp_xxx -Tag v0.2.4 [-Name "AI Chat 0.2.4"] [-NotesFile notes.md]
#                               [-Commit <sha or branch>] [-AssetDir packages\run-123] [-Assets a.ipa,b.deb] [-Draft] [-Prerelease]
param(
    [Parameter(Mandatory = $true)][string]$Repo,
    [string]$Token = $env:GH_TOKEN,
    [Parameter(Mandatory = $true)][string]$Tag,
    [string]$Name = '',
    [string]$NotesFile = '',
    [string]$Commit = '',
    [string]$AssetDir = '',
    [string[]]$Assets = @(),
    [switch]$Draft,
    [switch]$Prerelease
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if (-not $Token) { throw "Missing token: pass -Token or set GH_TOKEN" }
if (-not $Name) { $Name = $Tag }

$Headers = @{
    Authorization          = "Bearer $Token"
    Accept                 = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
    'User-Agent'           = 'aichat-ios6-release'
}
$Api = "https://api.github.com/repos/$Repo"

function Invoke-GH {
    param([string]$Method, [string]$Path, $Body)
    $params = @{ Method = $Method; Uri = "$Api$Path"; Headers = $Headers; ContentType = 'application/json; charset=utf-8' }
    if ($null -ne $Body) { $params.Body = [Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 10 -Compress)) }
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            return Invoke-RestMethod @params
        } catch {
            $status = 0
            try { $status = [int]$_.Exception.Response.StatusCode } catch {}
            $retryable = ($status -eq 403 -or $status -eq 502 -or $status -eq 503 -or $status -eq 0)
            if (-not $retryable -or $attempt -ge 8) { throw }
            Start-Sleep -Seconds ([Math]::Min(3 * $attempt, 20))
        }
    }
}

# Files to attach (-File passes "a,b" as one string, so split it here)
$files = @()
foreach ($a in $Assets) { foreach ($p in ($a -split ',')) { if ($p.Trim()) { $files += (Resolve-Path $p.Trim()).Path } } }
if ($AssetDir) {
    $files += Get-ChildItem -Path $AssetDir -File | Where-Object { $_.Extension -eq '.ipa' -or $_.Extension -eq '.deb' } | ForEach-Object { $_.FullName }
}
$files = @($files | Select-Object -Unique)

$notes = ''
if ($NotesFile) { $notes = [IO.File]::ReadAllText((Resolve-Path $NotesFile).Path, [Text.Encoding]::UTF8) }

# 1. Existing release for the tag, or a new one
$release = $null
try {
    $release = Invoke-GH GET "/releases/tags/$Tag"
} catch {
    $status = 0
    try { $status = [int]$_.Exception.Response.StatusCode } catch {}
    if ($status -ne 404) { throw }
}
if ($release) {
    Write-Host "Updating release $($release.id) for $Tag"
    $body = @{ name = $Name; draft = [bool]$Draft; prerelease = [bool]$Prerelease }
    if ($NotesFile) { $body.body = $notes }
    $release = Invoke-GH PATCH "/releases/$($release.id)" $body
} else {
    $body = @{ tag_name = $Tag; name = $Name; body = $notes; draft = [bool]$Draft; prerelease = [bool]$Prerelease }
    if ($Commit) { $body.target_commitish = $Commit }
    $release = Invoke-GH POST "/releases" $body
    Write-Host "Created release $($release.id) for $Tag"
}

# 2. Assets
foreach ($f in $files) {
    $fileName = [IO.Path]::GetFileName($f)
    $old = $release.assets | Where-Object { $_.name -eq $fileName } | Select-Object -First 1
    if ($old) {
        Invoke-GH DELETE "/releases/assets/$($old.id)" | Out-Null
        Write-Host "  replaced existing asset $fileName"
    }
    $uploadUrl = "https://uploads.github.com/repos/$Repo/releases/$($release.id)/assets?name=$([Uri]::EscapeDataString($fileName))"
    $asset = $null
    for ($i = 1; $i -le 5; $i++) {
        try {
            $asset = Invoke-RestMethod -Method POST -Uri $uploadUrl -Headers $Headers -ContentType 'application/octet-stream' -InFile $f
            break
        } catch {
            if ($i -eq 5) { throw }
            Start-Sleep -Seconds (3 * $i)
            # A failed upload can leave a stub asset behind that blocks the file name
            $stale = @(Invoke-GH GET "/releases/$($release.id)/assets") | Where-Object { $_.name -eq $fileName }
            foreach ($s in $stale) { Invoke-GH DELETE "/releases/assets/$($s.id)" | Out-Null }
        }
    }
    Write-Host "  + $fileName ($([math]::Round($asset.size / 1KB)) KB) $($asset.browser_download_url)"
}

Write-Host "Release: $($release.html_url)"
