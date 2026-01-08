# 测试脚本 - 验证进度显示是否正常
# 这个脚本会运行一个简单的 Docker 容器来测试输出

Write-Host "测试 Docker 输出..." -ForegroundColor Cyan

# 测试 1: 基本输出
Write-Host "`n[测试 1] 基本输出测试" -ForegroundColor Yellow
docker run --rm alpine sh -c 'for i in 1 2 3 4 5; do echo "进度: $i/5"; sleep 1; done'

# 测试 2: 带 TTY 的输出
Write-Host "`n[测试 2] TTY 输出测试" -ForegroundColor Yellow
docker run --rm -t alpine sh -c 'for i in 1 2 3 4 5; do echo "进度: $i/5"; sleep 1; done'

# 测试 3: Git 克隆进度
Write-Host "`n[测试 3] Git 克隆进度测试" -ForegroundColor Yellow
docker run --rm -t alpine sh -c 'apk add --no-cache git > /dev/null 2>&1 && git clone --progress --depth=1 https://github.com/termux/proot.git /tmp/test 2>&1 | head -20'

Write-Host "`n测试完成！" -ForegroundColor Green
Write-Host "如果你能看到实时输出，说明修改有效。" -ForegroundColor Cyan
