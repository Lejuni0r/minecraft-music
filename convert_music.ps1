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

$GitIgnorePath = Join-Path $Root ".gitignore"
if (-not (Test-Path $GitIgnorePath)) {
    [IO.File]::WriteAllText($GitIgnorePath, "input/`r`n", (New-Object System.Text.UTF8Encoding($false)))
} else {
    $gitignore = Get-Content $GitIgnorePath -Raw
    if ($gitignore -notmatch '(?m)^input/$') {
        Add-Content -Path $GitIgnorePath -Value "input/"
    }
}


if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Host ""
    Write-Host "ERREUR: FFmpeg n'est pas disponible dans le PATH."
    Write-Host "Installe-le puis rouvre PowerShell."
    Write-Host "Commande Windows: winget install --id Gyan.FFmpeg -e"
    exit 1
}

New-Item -ItemType Directory -Force -Path $InputPath | Out-Null
New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null

$extensions = @(".mp3", ".wav", ".flac", ".m4a", ".aac", ".ogg", ".opus", ".wma")

$files = Get-ChildItem -Path $InputPath -File |
    Where-Object { $extensions -contains $_.Extension.ToLowerInvariant() } |
    Sort-Object Name

if ($files.Count -eq 0) {
    Write-Host ""
    Write-Host "Aucun morceau trouve dans:"
    Write-Host "  $InputPath"
    Write-Host ""
    Write-Host "Mets tes MP3/FLAC/etc. dans le dossier input puis relance ce script."
    exit 0
}

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

$playlist = @()
$index = 1

Write-Host ""
Write-Host "Conversion de $($files.Count) morceau(x) en DFPWM..."
Write-Host ""

foreach ($file in $files) {
    $title = [IO.Path]::GetFileNameWithoutExtension($file.Name)
    $slug = Convert-ToSlug $title
    $outputName = ("{0:D3}-{1}.dfpwm" -f $index, $slug)
    $outputFile = Join-Path $OutputPath $outputName

    Write-Host ("[{0}/{1}] {2}" -f $index, $files.Count, $title)

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

    if ($LASTEXITCODE -ne 0) {
        throw "FFmpeg a echoue sur: $($file.Name)"
    }

    $encodedName = [Uri]::EscapeDataString($outputName)

    $playlist += [PSCustomObject]@{
        title = $title
        file  = $outputName
        url   = "https://raw.githubusercontent.com/$GitHubUser/$GitHubRepo/$GitHubBranch/songs/$encodedName"
    }

    $index++
}

$json = $playlist | ConvertTo-Json -Depth 4
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($PlaylistPath, $json, $utf8NoBom)

Write-Host ""
Write-Host "TERMINE."
Write-Host "DFPWM : $OutputPath"
Write-Host "Playlist : $PlaylistPath"
Write-Host ""
Write-Host "Ensuite commit/push le dossier songs/ + playlist.json sur GitHub."
