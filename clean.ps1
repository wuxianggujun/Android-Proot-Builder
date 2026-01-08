<#
.SYNOPSIS
    Clean up PRoot build artifacts and Docker resources

.PARAMETER RemoveContainers
    Remove build containers

.PARAMETER RemoveImages
    Remove build images

.PARAMETER RemoveOutput
    Remove output directory

.PARAMETER RemoveSource
    Remove source code volume (will require re-clone on next build)

.PARAMETER All
    Remove everything including source code

.EXAMPLE
    .\clean.ps1 -RemoveOutput           # Only remove output files
    .\clean.ps1 -RemoveImages           # Remove Docker images
    .\clean.ps1 -RemoveSource           # Remove source code (re-clone next time)
    .\clean.ps1 -All                    # Remove everything
#>

Param(
    [switch]$RemoveContainers,
    [switch]$RemoveImages,
    [switch]$RemoveOutput,
    [switch]$RemoveSource,
    [switch]$All
)

$ErrorActionPreference = 'Stop'

function Write-Info($msg) { Write-Host "[i] $msg" -ForegroundColor Cyan }
function Write-Success($msg) { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$outputPath = Join-Path $scriptRoot 'output'
$ImageBaseName = "proot-builder"
$SourceVolumeName = "proot-builder-source"

if ($All) {
    $RemoveContainers = $true
    $RemoveImages = $true
    $RemoveOutput = $true
    $RemoveSource = $true
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Android PRoot Builder Cleanup" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

if ($RemoveContainers) {
    Write-Info "Removing containers..."
    @('arm64', 'x86_64') | ForEach-Object {
        $name = "proot-builder-build-$_"
        $exists = docker ps -aq --filter "name=^${name}$" 2>$null
        if ($exists) {
            docker rm -f $name 2>$null | Out-Null
            Write-Success "Removed container: $name"
        }
    }
}

if ($RemoveImages) {
    Write-Info "Removing images..."
    @('arm64', 'x86_64') | ForEach-Object {
        $name = "${ImageBaseName}:$_"
        $exists = docker images -q $name 2>$null
        if ($exists) {
            docker rmi -f $name 2>$null | Out-Null
            Write-Success "Removed image: $name"
        }
    }
}

if ($RemoveOutput) {
    Write-Info "Removing output..."
    if (Test-Path $outputPath) {
        Remove-Item -Recurse -Force $outputPath
        Write-Success "Removed: $outputPath"
    }
}

if ($RemoveSource) {
    Write-Warn "Removing source code volume (will require re-clone on next build)..."
    $exists = docker volume ls -q --filter "name=^${SourceVolumeName}$" 2>$null
    if ($exists) {
        docker volume rm -f $SourceVolumeName 2>$null | Out-Null
        Write-Success "Removed volume: $SourceVolumeName"
    } else {
        Write-Info "Source volume not found: $SourceVolumeName"
    }
}

Write-Host ""
Write-Success "Cleanup done."

# Show remaining resources
$remainingImages = @('arm64', 'x86_64') | ForEach-Object {
    $name = "${ImageBaseName}:$_"
    if (docker images -q $name 2>$null) { $name }
}
$remainingVolume = docker volume ls -q --filter "name=^${SourceVolumeName}$" 2>$null

if ($remainingImages -or $remainingVolume) {
    Write-Host ""
    Write-Info "Remaining resources:"
    if ($remainingImages) {
        Write-Host "  Images: $($remainingImages -join ', ')" -ForegroundColor Gray
    }
    if ($remainingVolume) {
        Write-Host "  Volume: $SourceVolumeName (source code)" -ForegroundColor Gray
    }
}
