<#
.SYNOPSIS
    Build PRoot and proot-loader for Android

.DESCRIPTION
    Build PRoot from Termux source using Docker.
    Produces libproot.so, libproot-loader.so, libproot-loader32.so, libtalloc.so.2

    特性：
    - 源码持久化：使用 Docker volume，避免每次重新克隆
    - 增量编译：只重新编译修改过的文件
    - 包名无关：不做包名替换

.PARAMETER Arch
    Target architecture: arm64, x86_64, or all (default: all).

.PARAMETER Mode
    Build mode:
    - incremental: reuse existing images/containers and source code (default)
    - rebuild: rebuild the image (keep source code)
    - clean: remove everything including source code

.PARAMETER OutputPath
    Output directory (default: ./output).

.PARAMETER AndroidProjectRoot
    When -CopyToJniLibs / -CopyToAssets is set, specify the Android project root path.

.PARAMETER CopyToJniLibs
    Copy artifacts to <AndroidProjectRoot>/app/src/main/jniLibs after a successful build.

.PARAMETER CopyToAssets
    Copy libtalloc.so.2 to <AndroidProjectRoot>/app/src/<flavor>/assets/proot after a successful build.

.PARAMETER ResetSource
    Force re-clone source code (useful when package name changes).

.PARAMETER TallocLink
    How to link talloc into proot:
    - shared: keep libtalloc.so.2 as runtime dependency (default)
    - static: statically link talloc into libproot.so (still may output libtalloc.so.2)

.EXAMPLE
    .\build-proot.ps1                           # build all arch
    .\build-proot.ps1 -Arch arm64               # build arm64 only
    .\build-proot.ps1 -CopyToJniLibs            # build and copy to jniLibs
    .\build-proot.ps1 -Mode rebuild             # rebuild the image
    .\build-proot.ps1 -ResetSource              # re-clone source code
#>

Param(
    [ValidateSet('arm64', 'x86_64', 'all')]
    [string]$Arch = 'all',

    [ValidateSet('incremental', 'rebuild', 'clean')]
    [string]$Mode = 'incremental',

    [string]$OutputPath = '',

    [string]$AndroidProjectRoot = '',

    [switch]$CopyToJniLibs,
    
    [switch]$CopyToAssets,

    [switch]$ResetSource

    ,

    [ValidateSet('shared', 'static')]
    [string]$TallocLink = 'shared'
)

$ErrorActionPreference = 'Stop'

# ============ Helpers ============

function Write-Info($msg) { Write-Host "[i] $msg" -ForegroundColor Cyan }
function Write-Success($msg) { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-Err($msg) { Write-Host "[x] $msg" -ForegroundColor Red }

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path $scriptRoot

# Resolve output directory
if (-not $OutputPath -or [string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $scriptRoot 'output'
}
New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
$outputBase = (Resolve-Path $OutputPath).Path

# Source code volume name (persistent across builds)
$SourceVolumeName = "proot-builder-source"

# ============ Docker Checks ============

function Test-Docker {
    try {
        $null = docker version 2>&1
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

function Test-BuildxMultiArch {
    $info = docker buildx inspect 2>$null
    return $info -match 'linux/arm64'
}

function Ensure-Buildx {
    if (-not (Test-BuildxMultiArch)) {
        Write-Info "Configuring Docker buildx multi-arch support..."
        docker buildx create --name proot-builder-multiarch --use 2>$null | Out-Null
        docker buildx inspect --bootstrap 2>$null | Out-Null
    }
}

# ============ Image Management ============

$ImageBaseName = "proot-builder"

function Get-ImageName($arch) {
    return "${ImageBaseName}:${arch}"
}

function Get-ContainerName($arch) {
    return "proot-builder-build-${arch}"
}

function Test-ImageExists($arch) {
    $imageName = Get-ImageName $arch
    $exists = docker images -q $imageName 2>$null
    return [bool]$exists
}

function Test-ContainerExists($arch) {
    $containerName = Get-ContainerName $arch
    $exists = docker ps -aq --filter "name=^${containerName}$" 2>$null
    return [bool]$exists
}

function Remove-ExistingContainer($arch) {
    $containerName = Get-ContainerName $arch
    if (Test-ContainerExists $arch) {
        Write-Info "Removing existing container: $containerName"
        docker rm -f $containerName 2>$null | Out-Null
    }
}

function Remove-ExistingImage($arch) {
    $imageName = Get-ImageName $arch
    if (Test-ImageExists $arch) {
        Write-Info "Removing existing image: $imageName"
        docker rmi -f $imageName 2>$null | Out-Null
    }
}

function Test-VolumeExists($volumeName) {
    $exists = docker volume ls -q --filter "name=^${volumeName}$" 2>$null
    return [bool]$exists
}

function Remove-SourceVolume {
    if (Test-VolumeExists $SourceVolumeName) {
        Write-Info "Removing source volume: $SourceVolumeName"
        docker volume rm -f $SourceVolumeName 2>$null | Out-Null
    }
}

# ============ Build Logic ============

function Build-Image($arch) {
    $imageName = Get-ImageName $arch
    # 使用 linux/amd64 构建，因为我们使用 Android NDK 交叉编译
    $platform = 'linux/amd64'

    $dockerfile = Join-Path $scriptRoot "Dockerfile"

    # 确定目标架构参数
    $targetArch = switch ($arch) {
        'arm64' { 'aarch64' }
        'x86_64' { 'x86_64' }
    }

    Write-Info "Building image: $imageName (target: $targetArch)"
    Write-Info "  Platform: $platform"
    Write-Info "  Dockerfile: $dockerfile"

    # Build the image with progress output
    $buildArgs = @(
        'build',
        '--progress', 'plain',  # 显示详细构建进度
        '--platform', $platform,
        '--build-arg', "TARGET_ARCH=$targetArch",
        '-t', $imageName,
        '-f', $dockerfile,
        $scriptRoot
    )

    & docker @buildArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Image build failed: $imageName"
        return $false
    }

    Write-Success "Image built: $imageName"
    return $true
}

function Ensure-SourceVolume {
    if (-not (Test-VolumeExists $SourceVolumeName)) {
        Write-Info "Creating source volume: $SourceVolumeName"
        docker volume create $SourceVolumeName | Out-Null
    } else {
        Write-Info "Using existing source volume: $SourceVolumeName"
    }
}

function Build-PRoot($arch, $outputDir) {
    $imageName = Get-ImageName $arch
    $containerName = Get-ContainerName $arch

    # 确定目标架构参数
    $targetArch = switch ($arch) {
        'arm64' { 'aarch64' }
        'x86_64' { 'x86_64' }
    }

    # Ensure output directory exists
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

    # Ensure source volume exists
    Ensure-SourceVolume

    # Remove existing container
    Remove-ExistingContainer $arch

    Write-Info "Building PRoot ($arch)..."
    Write-Info "  Source volume: $SourceVolumeName (persistent)"
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  容器日志（实时输出）" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    # Run build container with volume mounts
    # 使用 Start-Process 确保实时输出
    $dockerCmd = "docker"
    $scriptsPath = (Resolve-Path $scriptRoot).Path
    $dockerArgs = @(
        'run',
        '--name', $containerName,
        '-v', "${SourceVolumeName}:/build/src",
        # Bind-mount scripts so tweaking *.sh doesn't force rebuilding the image (avoids re-downloading NDK)
        '-v', "${scriptsPath}:/build/scripts:ro",
        '-v', "${outputDir}:/output",
        '-e', "TARGET_ARCH=$targetArch",
        '-e', "TALLOC_LINK=$TallocLink",
        $imageName
    )

    # 直接运行，不使用 -it（避免 PowerShell 缓冲问题）
    $process = Start-Process -FilePath $dockerCmd -ArgumentList $dockerArgs -NoNewWindow -Wait -PassThru
    $buildExitCode = $process.ExitCode
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    
    # 构建完成后清理容器
    if (Test-ContainerExists $arch) {
        docker rm $containerName 2>$null | Out-Null
    }
    
    if ($buildExitCode -ne 0) {
        Write-Err "Build failed!"
        return $false
    }

    # Verify outputs
    $requiredFiles = @('libproot.so')
    $missingFiles = @()
    
    foreach ($file in $requiredFiles) {
        if (-not (Test-Path (Join-Path $outputDir $file))) {
            $missingFiles += $file
        }
    }

    if ($missingFiles.Count -gt 0) {
        Write-Err "Missing required files: $($missingFiles -join ', ')"
        return $false
    }

    Write-Success "Build completed: $outputDir"
    return $true
}

function Build-Architecture($arch) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor White
    Write-Info "Start build: $arch"
    Write-Host "========================================" -ForegroundColor White

    $outputDir = Join-Path $outputBase $arch

    # Apply mode behavior
    switch ($Mode) {
        'clean' {
            Remove-ExistingContainer $arch
            Remove-ExistingImage $arch
            Remove-SourceVolume
        }
        'rebuild' {
            Remove-ExistingContainer $arch
            # Rebuild image but keep existing image/layers to maximize Docker cache hit rate
            # (avoids re-downloading large artifacts like NDK when Dockerfile hasn't changed).
            # Keep source volume for rebuild mode.
        }
    }

    # Reset source if requested
    if ($ResetSource) {
        Remove-SourceVolume
    }

    # Determine whether image needs building
    $needBuild = -not (Test-ImageExists $arch)
    if ($Mode -eq 'rebuild' -or $Mode -eq 'clean') {
        $needBuild = $true
    }

    if ($needBuild) {
        if (-not (Build-Image $arch)) {
            return $false
        }
    } else {
        Write-Info "Reusing existing image: $(Get-ImageName $arch)"
    }

    # Build PRoot
    if (-not (Build-PRoot $arch $outputDir)) {
        return $false
    }

    return $true
}

# ============ Main ============

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Android PRoot Builder" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Docker)) {
    Write-Err "Docker is not running or not installed. Please start Docker Desktop first."
    exit 1
}

Write-Info "Output dir: $outputBase"
Write-Info "Build mode: $Mode"
Write-Info "Source volume: $SourceVolumeName"
if ($ResetSource) {
    Write-Warn "Source reset requested - will re-clone repositories"
}

# Decide architectures to build
$archList = switch ($Arch) {
    'all' { @('arm64', 'x86_64') }
    default { @($Arch) }
}

# Build each arch
$allSuccess = $true
foreach ($arch in $archList) {
    if (-not (Build-Architecture $arch)) {
        $allSuccess = $false
    }
}

# Copy to jniLibs
if ($allSuccess -and $CopyToJniLibs) {
    Write-Host ""
    Write-Info "Copying to jniLibs..."

    if (-not $AndroidProjectRoot -or [string]::IsNullOrWhiteSpace($AndroidProjectRoot)) {
        Write-Err "Missing -AndroidProjectRoot. It is required when using -CopyToJniLibs."
        exit 1
    }
    $jniLibsBase = Join-Path (Resolve-Path $AndroidProjectRoot).Path 'app\src\main\jniLibs'

    foreach ($arch in $archList) {
        $sourceDir = Join-Path $outputBase $arch
        $targetDir = switch ($arch) {
            'arm64' { Join-Path $jniLibsBase 'arm64-v8a' }
            'x86_64' { Join-Path $jniLibsBase 'x86_64' }
        }

        New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

        # Copy proot binaries
        @('libproot.so', 'libproot-loader.so', 'libproot-loader32.so') | ForEach-Object {
            $sourceFile = Join-Path $sourceDir $_
            if (Test-Path $sourceFile) {
                Copy-Item -Force $sourceFile $targetDir
                Write-Success "Copied: $targetDir\$_"
            }
        }
    }
}

# Copy libtalloc to assets
if ($allSuccess -and $CopyToAssets) {
    Write-Host ""
    Write-Info "Copying libtalloc.so.2 to assets..."
    if ($TallocLink -eq 'static') {
        Write-Warn "TallocLink=static 时 libproot.so 不再依赖 libtalloc.so.2，通常不需要 -CopyToAssets（可忽略该提示继续复制）。"
    }
    if (-not $AndroidProjectRoot -or [string]::IsNullOrWhiteSpace($AndroidProjectRoot)) {
        Write-Err "Missing -AndroidProjectRoot. It is required when using -CopyToAssets."
        exit 1
    }

    foreach ($arch in $archList) {
        $sourceFile = Join-Path $outputBase "$arch\libtalloc.so.2"
        $flavorDir = switch ($arch) {
            'arm64' { 'arm64' }
            'x86_64' { 'x86_64' }
        }
        $targetDir = Join-Path (Resolve-Path $AndroidProjectRoot).Path "app\src\$flavorDir\assets\proot\$(switch ($arch) { 'arm64' { 'arm64-v8a' } 'x86_64' { 'x86_64' } })"

        if (Test-Path $sourceFile) {
            New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
            Copy-Item -Force $sourceFile $targetDir
            Write-Success "Copied: $targetDir\libtalloc.so.2"
        }
    }
}

# Done
Write-Host ""
if ($allSuccess) {
    Write-Success "Build completed!"
    Write-Host ""
    Write-Info "Artifacts:"
    foreach ($arch in $archList) {
        $dir = Join-Path $outputBase $arch
        if (Test-Path $dir) {
            Write-Host "  $arch/" -ForegroundColor White
            Get-ChildItem $dir -Filter "*.so*" | ForEach-Object {
                $size = [math]::Round($_.Length / 1KB, 2)
                Write-Host "    - $($_.Name) ($size KB)" -ForegroundColor Gray
            }
        }
    }

    if (-not $CopyToJniLibs) {
        Write-Host ""
        Write-Info "Next: use -CopyToJniLibs to copy into jniLibs automatically."
    }
} else {
    Write-Err "Build failed. Check the errors above."
    exit 1
}
