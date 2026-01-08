# 实时监控 PRoot 构建进度
# 用法：在另一个终端窗口运行此脚本

Param(
    [ValidateSet('arm64', 'x86_64')]
    [string]$Arch = 'arm64'
)

$containerName = "proot-builder-build-${Arch}"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  PRoot 构建进度监控" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "容器名称: $containerName" -ForegroundColor White
Write-Host "按 Ctrl+C 退出监控（不会停止构建）" -ForegroundColor Yellow
Write-Host ""
Write-Host "----------------------------------------" -ForegroundColor Gray

# 检查容器是否存在
$exists = docker ps -a --filter "name=^${containerName}$" --format "{{.Names}}" 2>$null

if (-not $exists) {
    Write-Host "[!] 容器不存在或已完成" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "可能的原因：" -ForegroundColor White
    Write-Host "  1. 构建还未开始" -ForegroundColor Gray
    Write-Host "  2. 构建已完成（容器自动删除）" -ForegroundColor Gray
    Write-Host "  3. 构建失败" -ForegroundColor Gray
    Write-Host ""
    Write-Host "检查输出文件：" -ForegroundColor White
    $outputDir = Join-Path $PSScriptRoot "output\${Arch}"
    if (Test-Path $outputDir) {
        Get-ChildItem $outputDir -Filter "*.so*" | ForEach-Object {
            $size = [math]::Round($_.Length / 1KB, 2)
            Write-Host "  ✓ $($_.Name) ($size KB)" -ForegroundColor Green
        }
    } else {
        Write-Host "  输出目录不存在" -ForegroundColor Gray
    }
    exit 0
}

# 检查容器状态
$status = docker ps --filter "name=^${containerName}$" --format "{{.Status}}" 2>$null

if ($status) {
    Write-Host "[i] 容器正在运行: $status" -ForegroundColor Cyan
} else {
    Write-Host "[!] 容器已停止" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "实时日志：" -ForegroundColor White
Write-Host "----------------------------------------" -ForegroundColor Gray

# 实时显示日志
docker logs -f $containerName 2>&1
