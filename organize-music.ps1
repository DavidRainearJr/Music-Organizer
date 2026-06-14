<#
.SYNOPSIS
Organizes album folders into Artist\Album folders.

.DESCRIPTION
Menu-first by default. Looks for top-level folders named like:

  Artist 1984 - Album Title

It moves them to:

  Artist\Album Title

It also handles random wrapper folders when the wrapper contains exactly one
recognizable album folder, for example:

  RandomDownloadFolder\Artist Name 1982 - Album Title

becomes:

  Artist Name\Album Title

No destination folders are overwritten. Empty wrapper folders are removed only
in apply mode, after their album folder was moved.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Path = $(if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }),

    [switch]$Apply,

    [switch]$NoPrompt,

    [switch]$KeepWrappers
)

$script:InteractiveReview = (-not $Apply -and -not $NoPrompt)

function Pause-BeforeExit {
    if ($script:InteractiveReview) {
        ""
        Read-Host 'Press Enter to close this window' | Out-Null
    }
}

function Read-StartChoice {
    while ($true) {
        Write-Host ''
        Write-Host 'Choose an option:'
        Write-Host '1 - Organize library'
        Write-Host '2 - Dry run'

        Write-Host 'Enter 1 or 2: ' -NoNewline
        $choice = (Read-Host).Trim()

        if ($choice -eq '1' -or $choice -eq '2') {
            return $choice
        }

        Write-Host 'Please enter 1 or 2.'
    }
}

function Read-DryRunChoice {
    while ($true) {
        Write-Host ''
        Write-Host 'Choose an option:'
        Write-Host '1 - Apply these changes'
        Write-Host '2 - Exit without changes'

        Write-Host 'Enter 1 or 2: ' -NoNewline
        $choice = (Read-Host).Trim()

        if ($choice -eq '1' -or $choice -eq '2') {
            return $choice
        }

        Write-Host 'Please enter 1 or 2.'
    }
}

trap {
    ""
    "Error: $($_.Exception.Message)"
    Pause-BeforeExit
    exit 1
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$IgnoredWrapperFiles = @(
    '.DS_Store',
    'desktop.ini',
    'Thumbs.db'
)

function Resolve-ExistingDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath
    )

    $resolved = Resolve-Path -LiteralPath $InputPath -ErrorAction Stop
    $item = Get-Item -LiteralPath $resolved.ProviderPath -ErrorAction Stop

    if (-not $item.PSIsContainer) {
        throw "Path is not a folder: $InputPath"
    }

    return $item.FullName
}

function Normalize-AlbumTitle {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title
    )

    $normalized = ($Title -replace '\s+', ' ').Trim()
    $normalized = $normalized.TrimEnd([char[]]@('_', ' '))

    return $normalized
}

function Get-AlbumInfoFromFolderName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $candidate = $Name.Trim()
    $match = [regex]::Match($candidate, '^(?<Artist>.+?)\s+(?<Year>(?:19|20)\d{2})\s+-\s+(?<Album>.+?)\s*$')

    if (-not $match.Success) {
        return $null
    }

    $artist = (($match.Groups['Artist'].Value) -replace '\s+', ' ').Trim()
    $album = Normalize-AlbumTitle -Title $match.Groups['Album'].Value

    if ([string]::IsNullOrWhiteSpace($artist) -or [string]::IsNullOrWhiteSpace($album)) {
        return $null
    }

    return [pscustomobject]@{
        Artist = $artist
        Year   = [int]$match.Groups['Year'].Value
        Album  = $album
    }
}

function Get-UsefulDirectFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Directory
    )

    return @(
        Get-ChildItem -LiteralPath $Directory -File -Force |
            Where-Object { $IgnoredWrapperFiles -notcontains $_.Name }
    )
}

function Get-UsefulChildren {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Directory
    )

    return @(
        Get-ChildItem -LiteralPath $Directory -Force |
            Where-Object { $_.PSIsContainer -or ($IgnoredWrapperFiles -notcontains $_.Name) }
    )
}

function Get-RelativeDisplayPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FullPath
    )

    $root = [System.IO.Path]::GetFullPath($script:RootPath)
    $path = [System.IO.Path]::GetFullPath($FullPath)
    $separators = [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $rootPrefix = $root.TrimEnd($separators) + [System.IO.Path]::DirectorySeparatorChar

    if ($path.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $path.Substring($rootPrefix.Length)
    }

    return $FullPath
}

function New-PlanItem {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$Artist,

        [Parameter(Mandatory = $true)]
        [string]$Album,

        [Parameter(Mandatory = $true)]
        [string]$Kind,

        [string]$WrapperPath
    )

    $artistPath = Join-Path -Path $script:RootPath -ChildPath $Artist
    $destinationPath = Join-Path -Path $artistPath -ChildPath $Album

    return [pscustomobject]@{
        SourcePath      = $SourcePath
        Artist          = $Artist
        Album           = $Album
        ArtistPath      = $artistPath
        DestinationPath = $destinationPath
        Kind            = $Kind
        WrapperPath     = $WrapperPath
    }
}

$script:RootPath = Resolve-ExistingDirectory -InputPath $Path
$shouldApply = [bool]$Apply

if ($script:InteractiveReview) {
    "Music Library Organizer"
    "Root: $script:RootPath"

    $startChoice = Read-StartChoice

    if ($startChoice -eq '1') {
        $shouldApply = $true
    }
}

$plan = [System.Collections.Generic.List[object]]::new()
$skipped = [System.Collections.Generic.List[object]]::new()

foreach ($directory in @(Get-ChildItem -LiteralPath $script:RootPath -Directory -Force)) {
    $childDirectories = @(Get-ChildItem -LiteralPath $directory.FullName -Directory -Force)
    $usefulDirectFiles = @(Get-UsefulDirectFiles -Directory $directory.FullName)
    $plannedAsWrapper = $false

    if ($childDirectories.Count -eq 1 -and $usefulDirectFiles.Count -eq 0) {
        $innerInfo = Get-AlbumInfoFromFolderName -Name $childDirectories[0].Name

        if ($null -ne $innerInfo) {
            $plan.Add((New-PlanItem `
                -SourcePath $childDirectories[0].FullName `
                -Artist $innerInfo.Artist `
                -Album $innerInfo.Album `
                -Kind 'wrapper' `
                -WrapperPath $directory.FullName))

            $plannedAsWrapper = $true
        }
        else {
            $directInfo = Get-AlbumInfoFromFolderName -Name $directory.Name

            if ($null -eq $directInfo) {
                $skipped.Add([pscustomobject]@{
                    Path   = $directory.FullName
                    Reason = "Possible wrapper, but inner folder is not named 'Artist YYYY - Album'."
                })
            }
        }
    }

    if ($plannedAsWrapper) {
        continue
    }

    $info = Get-AlbumInfoFromFolderName -Name $directory.Name

    if ($null -ne $info) {
        $plan.Add((New-PlanItem `
            -SourcePath $directory.FullName `
            -Artist $info.Artist `
            -Album $info.Album `
            -Kind 'direct'))
    }
}

$mode = if ($shouldApply) { 'APPLY' } else { 'DRY RUN' }

if ($script:InteractiveReview) {
    ""
    "Mode: $mode"
}
else {
    "Mode: $mode"
    "Root: $script:RootPath"
}

if ($plan.Count -eq 0) {
    "No album folders found to organize."

    if ($skipped.Count -gt 0) {
        ""
        "Skipped possible wrappers:"
        foreach ($item in $skipped) {
            "- $(Get-RelativeDisplayPath -FullPath $item.Path): $($item.Reason)"
        }
    }

    Pause-BeforeExit
    exit 0
}

$errors = [System.Collections.Generic.List[string]]::new()
$seenDestinations = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

foreach ($item in $plan) {
    if (-not (Test-Path -LiteralPath $item.SourcePath -PathType Container)) {
        $errors.Add("Missing source: $($item.SourcePath)")
    }

    if (-not $seenDestinations.Add($item.DestinationPath)) {
        $errors.Add("Multiple folders would move to the same destination: $($item.DestinationPath)")
    }

    if (Test-Path -LiteralPath $item.DestinationPath) {
        $errors.Add("Destination already exists: $($item.DestinationPath)")
    }

    if (Test-Path -LiteralPath $item.ArtistPath) {
        $artistItem = Get-Item -LiteralPath $item.ArtistPath -Force
        if (-not $artistItem.PSIsContainer) {
            $errors.Add("Artist path exists but is not a folder: $($item.ArtistPath)")
        }
    }
}

if ($errors.Count -gt 0) {
    ""
    "Preflight failed. No folders were moved."
    foreach ($errorMessage in $errors) {
        "- $errorMessage"
    }
    Pause-BeforeExit
    exit 1
}

if (-not $shouldApply -or -not $script:InteractiveReview) {
    ""
    "Planned moves:"
    foreach ($item in $plan | Sort-Object Artist, Album) {
        $source = Get-RelativeDisplayPath -FullPath $item.SourcePath
        $destination = Get-RelativeDisplayPath -FullPath $item.DestinationPath
        $label = if ($item.Kind -eq 'wrapper') { 'wrapper' } else { 'direct' }

        "- [$label] $source -> $destination"
    }

    if ($skipped.Count -gt 0) {
        ""
        "Skipped possible wrappers:"
        foreach ($item in $skipped) {
            "- $(Get-RelativeDisplayPath -FullPath $item.Path): $($item.Reason)"
        }
    }
}

if (-not $shouldApply) {
    if ($script:InteractiveReview) {
        $choice = Read-DryRunChoice

        if ($choice -eq '1') {
            $shouldApply = $true
        }
        else {
            ""
            "Dry run only. No changes were made."
            Pause-BeforeExit
            exit 0
        }
    }
    else {
        ""
        "Dry run only. Re-run with -Apply to move folders."
        exit 0
    }
}

""
"Applying changes..."

foreach ($artistPath in @($plan | Select-Object -ExpandProperty ArtistPath -Unique)) {
    if (-not (Test-Path -LiteralPath $artistPath -PathType Container)) {
        New-Item -ItemType Directory -Path $artistPath | Out-Null
        "Created artist folder: $(Get-RelativeDisplayPath -FullPath $artistPath)"
    }
}

foreach ($item in $plan) {
    Move-Item -LiteralPath $item.SourcePath -Destination $item.DestinationPath
    "Moved: $(Get-RelativeDisplayPath -FullPath $item.DestinationPath)"
}

if (-not $KeepWrappers) {
    foreach ($wrapperPath in @($plan | Where-Object { -not [string]::IsNullOrWhiteSpace($_.WrapperPath) } | Select-Object -ExpandProperty WrapperPath -Unique)) {
        if (Test-Path -LiteralPath $wrapperPath -PathType Container) {
            $usefulChildren = @(Get-UsefulChildren -Directory $wrapperPath)

            if ($usefulChildren.Count -eq 0) {
                Remove-Item -LiteralPath $wrapperPath -Recurse -Force
                "Removed empty wrapper: $(Get-RelativeDisplayPath -FullPath $wrapperPath)"
            }
            else {
                "Left non-empty wrapper: $(Get-RelativeDisplayPath -FullPath $wrapperPath)"
            }
        }
    }
}

"Done."
Pause-BeforeExit
