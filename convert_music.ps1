param(
    [string]$InputFolder = "input",
    [string]$OutputFolder = "songs"
)

$ErrorActionPreference = "Stop"

$GitHubUser = "Lejuni0r"
$GitHubRepo = "minecraft-music"
$GitHubBranch = "main"

$Root = $PSScriptRoot
$InputPath = Join-Path $Root $InputFolder
$OutputPath = Join-Path $Root $OutputFolder
$PlaylistPath = Join-Path $Root "playlist.json"
$PlaylistBackupPath = Join-Path $Root "playlist.backup.json"
$GitIgnorePath = Join-Path $Root ".gitignore"

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# ------------------------------------------------------------
# .gitignore: never upload source audio from input/
# ------------------------------------------------------------
if (-not (Test-Path $GitIgnorePath)) {
    [IO.File]::WriteAllText($GitIgnorePath, "input/`r`n", $utf8NoBom)
} else {
    $gitignore = Get-Content $GitIgnorePath -Raw
    if ($gitignore -notmatch '(?m)^input/$') {
        Add-Content -Path $GitIgnorePath -Value "input/"
    }
}

# ------------------------------------------------------------
# Requirements / folders
# ------------------------------------------------------------
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Host ""
    Write-Host "ERREUR: FFmpeg n'est pas disponible dans le PATH." -ForegroundColor Red
    Write-Host "Installe-le puis rouvre PowerShell."
    Write-Host "Commande Windows: winget install --id Gyan.FFmpeg -e"
    exit 1
}

New-Item -ItemType Directory -Force -Path $InputPath | Out-Null
New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null

$extensions = @(".mp3", ".wav", ".flac", ".m4a", ".aac", ".ogg", ".opus", ".wma")

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
function Convert-ToSlug([string]$Text) {
    $normalized = $Text.Normalize([Text.NormalizationForm]::FormD)
    $builder = New-Object System.Text.StringBuilder

    foreach ($char in $normalized.ToCharArray()) {
        $category = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($char)
        if ($category -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$builder.Append($char)
        }
    }

    $slug = $builder.ToString()
    $slug = $slug -replace '[^A-Za-z0-9._-]+', '-'
    $slug = $slug.Trim('-', '.', '_').ToLowerInvariant()

    if ([string]::IsNullOrWhiteSpace($slug)) {
        $slug = "track"
    }

    return $slug
}

function Get-TrackNumber([string]$FileName) {
    if ($FileName -match '^(\d+)-') {
        return [int]$Matches[1]
    }
    return 0
}

function New-PlaylistEntry(
    [string]$Title,
    [string]$FileName,
    [long]$Bytes
) {
    $encodedName = [Uri]::EscapeDataString($FileName)

    return [PSCustomObject]@{
        title    = $Title
        file     = $FileName
        url      = "https://raw.githubusercontent.com/$GitHubUser/$GitHubRepo/$GitHubBranch/songs/$encodedName"
        bytes    = $Bytes
        duration = [math]::Round($Bytes / 6000.0, 3)
    }
}

# ------------------------------------------------------------
# Load the EXISTING playlist instead of replacing it
# ------------------------------------------------------------
$playlist = @()

if (Test-Path $PlaylistPath) {
    $raw = Get-Content $PlaylistPath -Raw

    if (-not [string]::IsNullOrWhiteSpace($raw)) {
        try {
            $loaded = $raw | ConvertFrom-Json

            if ($null -ne $loaded) {
                $playlist = @($loaded)
            }
        }
        catch {
            Write-Host ""
            Write-Host "ERREUR: playlist.json existe mais son JSON est invalide." -ForegroundColor Red
            Write-Host "Le script s'arrete pour ne PAS ecraser ta bibliotheque."
            Write-Host "Fichier: $PlaylistPath"
            exit 1
        }
    }

    Copy-Item $PlaylistPath $PlaylistBackupPath -Force
}

# Rebuild useful metadata for old entries when the DFPWM is locally available.
# This also makes TRMK Music OS know durations immediately.
$normalizedPlaylist = @()

foreach ($entry in $playlist) {
    if ($null -eq $entry) {
        continue
    }

    $title = [string]$entry.title
    $fileName = [string]$entry.file
    $url = [string]$entry.url

    if ([string]::IsNullOrWhiteSpace($fileName)) {
        continue
    }

    if ([string]::IsNullOrWhiteSpace($title)) {
        $title = [IO.Path]::GetFileNameWithoutExtension($fileName)
    }

    if ([string]::IsNullOrWhiteSpace($url)) {
        $encodedName = [Uri]::EscapeDataString($fileName)
        $url = "https://raw.githubusercontent.com/$GitHubUser/$GitHubRepo/$GitHubBranch/songs/$encodedName"
    }

    $localSong = Join-Path $OutputPath $fileName
    $bytes = 0L

    if (Test-Path $localSong) {
        $bytes = (Get-Item $localSong).Length
    }
    elseif ($null -ne $entry.bytes) {
        $bytes = [long]$entry.bytes
    }

    $duration = $null
    if ($bytes -gt 0) {
        $duration = [math]::Round($bytes / 6000.0, 3)
    }
    elseif ($null -ne $entry.duration) {
        $duration = [double]$entry.duration
    }

    $normalizedPlaylist += [PSCustomObject]@{
        title    = $title
        file     = $fileName
        url      = $url
        bytes    = $(if ($bytes -gt 0) { $bytes } else { $null })
        duration = $duration
    }
}

$playlist = @($normalizedPlaylist)

# ------------------------------------------------------------
# Build indexes so old tracks are never overwritten
# ------------------------------------------------------------
$knownTitles = @{}
$knownFiles = @{}
$maxIndex = 0

foreach ($entry in $playlist) {
    if (-not [string]::IsNullOrWhiteSpace([string]$entry.title)) {
        $knownTitles[[string]$entry.title.ToLowerInvariant()] = $true
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$entry.file)) {
        $knownFiles[[string]$entry.file.ToLowerInvariant()] = $true
        $n = Get-TrackNumber ([string]$entry.file)
        if ($n -gt $maxIndex) {
            $maxIndex = $n
        }
    }
}

# Also inspect songs/ itself, in case files exist that are not in playlist.json.
$existingDfpwm = Get-ChildItem -Path $OutputPath -File -Filter "*.dfpwm" -ErrorAction SilentlyContinue

foreach ($song in $existingDfpwm) {
    $knownFiles[$song.Name.ToLowerInvariant()] = $true

    $n = Get-TrackNumber $song.Name
    if ($n -gt $maxIndex) {
        $maxIndex = $n
    }
}

$nextIndex = $maxIndex + 1

# ------------------------------------------------------------
# Convert ONLY what is currently in input/
# ------------------------------------------------------------
$files = @(
    Get-ChildItem -Path $InputPath -File |
        Where-Object { $extensions -contains $_.Extension.ToLowerInvariant() } |
        Sort-Object Name
)

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " Minecraft Music - mode incremental" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ("Bibliotheque actuelle : {0} morceau(x)" -f $playlist.Count)
Write-Host ("Fichiers trouves dans input : {0}" -f $files.Count)
Write-Host ""

$added = 0
$skipped = 0
$failed = 0

foreach ($file in $files) {
    $title = [IO.Path]::GetFileNameWithoutExtension($file.Name)
    $titleKey = $title.ToLowerInvariant()

    # Same title already exists -> don't reconvert it or duplicate the playlist.
    if ($knownTitles.ContainsKey($titleKey)) {
        Write-Host ("[SKIP] Deja dans la bibliotheque : {0}" -f $title) -ForegroundColor DarkGray
        $skipped++
        continue
    }

    $slug = Convert-ToSlug $title

    # Pick the next available number. Never overwrite an old DFPWM.
    do {
        $outputName = ("{0:D3}-{1}.dfpwm" -f $nextIndex, $slug)
        $outputFile = Join-Path $OutputPath $outputName
        $nextIndex++
    }
    while (
        $knownFiles.ContainsKey($outputName.ToLowerInvariant()) -or
        (Test-Path $outputFile)
    )

    Write-Host ("[ADD ] {0} -> {1}" -f $title, $outputName) -ForegroundColor Green

    & ffmpeg `
        -hide_banner `
        -loglevel error `
        -y `
        -i $file.FullName `
        -vn `
        -ac 1 `
        -ar 48000 `
        -c:a dfpwm `
        -f dfpwm `
        $outputFile

    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $outputFile)) {
        Write-Host ("[FAIL] FFmpeg a echoue : {0}" -f $file.Name) -ForegroundColor Red
        $failed++

        if (Test-Path $outputFile) {
            Remove-Item $outputFile -Force
        }

        continue
    }

    $bytes = (Get-Item $outputFile).Length
    $playlist += New-PlaylistEntry -Title $title -FileName $outputName -Bytes $bytes

    $knownTitles[$titleKey] = $true
    $knownFiles[$outputName.ToLowerInvariant()] = $true
    $added++
}

# ------------------------------------------------------------
# Save playlist safely.
# Old entries + new entries are all preserved.
# ------------------------------------------------------------
$json = @($playlist) | ConvertTo-Json -Depth 6

$tempPlaylist = "$PlaylistPath.tmp"
[IO.File]::WriteAllText($tempPlaylist, $json, $utf8NoBom)

if (Test-Path $PlaylistPath) {
    Remove-Item $PlaylistPath -Force
}

Move-Item $tempPlaylist $PlaylistPath -Force

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " TERMINE" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ("Ajoutes       : {0}" -f $added) -ForegroundColor Green
Write-Host ("Deja presents : {0}" -f $skipped)
Write-Host ("Echecs        : {0}" -f $failed)
Write-Host ("Total playlist: {0}" -f $playlist.Count)
Write-Host ""
Write-Host "Les anciennes musiques dans songs/ n'ont PAS ete supprimees."
Write-Host "playlist.json conserve les anciennes + ajoute les nouvelles."
Write-Host ""
Write-Host "Tu peux maintenant faire Commit puis Push dans GitHub Desktop."
Write-Host ""
