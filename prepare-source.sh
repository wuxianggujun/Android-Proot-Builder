#!/bin/bash
# Android PRoot 源码准备脚本
# 
# 功能：
# - 检查源码是否已存在（避免重复克隆）
# - 克隆 Termux proot 及其依赖
# - 应用必要的补丁

set -e

# 禁用输出缓冲，确保实时显示
export PYTHONUNBUFFERED=1
stty -icanon -echo 2>/dev/null || true

# 配置 Git 使用非交互模式
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/bin/echo

# ============ 配置 ============

SRC_DIR="/build/src"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ============ 源码仓库 ============

# Termux 官方 proot（包含 Android 补丁）
PROOT_REPO="https://github.com/termux/proot.git"
PROOT_BRANCH="master"

# ============ 检查源码 ============

check_source_exists() {
    local name="$1"
    local dir="$2"
    local marker="$3"
    
    if [ -d "$dir" ] && [ -f "$dir/$marker" ]; then
        return 0  # 存在
    fi
    return 1  # 不存在
}

# ============ 克隆源码 ============

clone_if_needed() {
    local name="$1"
    local repo="$2"
    local branch="$3"
    local dir="$4"
    local marker="$5"
    local repo_proxy="${6:-}"  # 可选的代理地址
    
    if check_source_exists "$name" "$dir" "$marker"; then
        log_info "$name 源码已存在，跳过克隆"
        return 0
    fi
    
    log_info "克隆 $name 源码..."
    rm -rf "$dir"
    
    # 优先尝试代理，失败则使用原始地址
    local clone_success=false
    
    if [ -n "$repo_proxy" ]; then
        log_info "  尝试加速代理: ghproxy.com"
        if timeout 60 git clone --progress --depth=1 --branch "$branch" "$repo_proxy" "$dir" 2>&1; then
            # 检查目录是否真的存在且有内容
            if [ -d "$dir" ] && [ "$(ls -A $dir 2>/dev/null)" ]; then
                clone_success=true
                log_success "$name 源码克隆完成（使用加速代理）"
            else
                log_warn "  代理克隆失败，目录为空"
                rm -rf "$dir"
            fi
        else
            log_warn "  代理失败或超时，使用 GitHub 官方源..."
            rm -rf "$dir"
        fi
    fi
    
    if [ "$clone_success" = false ]; then
        log_info "  仓库: $repo"
        log_info "  分支: $branch"
        if git clone --progress --depth=1 --branch "$branch" "$repo" "$dir" 2>&1; then
            if [ -d "$dir" ] && [ "$(ls -A $dir 2>/dev/null)" ]; then
                log_success "$name 源码克隆完成"
            else
                log_error "$name 克隆失败：目录为空"
                return 1
            fi
        else
            log_error "$name 克隆失败"
            return 1
        fi
    fi
}

# ============ 标记文件 ============

# 创建标记文件（用于增量构建）
create_marker() {
    local dir="$1"
    local marker="$dir/.proot-builder-prepared"
    
    cat > "$marker" << EOF
# Android PRoot Source Marker
# 此文件表示源码已准备完成
PREPARED_AT=$(date -Iseconds)
EOF
    log_success "标记文件已创建: $marker"
}

check_marker() {
    local dir="$1"
    local marker="$dir/.proot-builder-prepared"
    
    if [ -f "$marker" ]; then
        # 检查关键源码目录是否存在
        if [ -d "$dir/proot/src" ] && [ -d "$dir/talloc" ]; then
            return 0  # 已准备，源码完整
        fi
        log_warn "源码目录不完整，需要重新准备"
        return 1
    fi
    return 1
}

# ============ 补丁/修复（幂等） ============

apply_patches() {
    # proot: extension/ashmem_memfd/ashmem_memfd.c 缺少 <string.h>，在 clang(C99) 下会因隐式声明报错
    local file="$SRC_DIR/proot/src/extension/ashmem_memfd/ashmem_memfd.c"
    if [ -f "$file" ] && ! grep -qE '^#include <string\.h>' "$file"; then
        log_info "应用补丁: proot ashmem_memfd.c 添加 <string.h>"
        sed -i '2i#include <string.h>' "$file"
        log_success "已修复: $file"
    fi

    # proot: loader/loader-info.awk 使用 gawk 的 strtonum，部分环境默认 awk(如 mawk) 不支持，导致构建失败
    local awk_file="$SRC_DIR/proot/src/loader/loader-info.awk"
    if [ -f "$awk_file" ] && grep -q "strtonum" "$awk_file"; then
        log_info "应用补丁: proot loader-info.awk 兼容非 gawk awk"
        cat > "$awk_file" << 'EOF'
# Note: This file is included only for targets which have pokedata workaround

function hextodec(h,    i, c, d, v) {
    v = 0
    for (i = 1; i <= length(h); i++) {
        c = tolower(substr(h, i, 1))
        d = index("0123456789abcdef", c) - 1
        if (d < 0) return 0
        v = v * 16 + d
    }
    return v
}

/\ypokedata_workaround\y/ { pokedata_workaround = hextodec($2) }
/\y_start\y/              { start = hextodec($2) }

END {
    print "#include <unistd.h>"
    print "const ssize_t offset_to_pokedata_workaround=" (pokedata_workaround - start) ";"
}
EOF
        log_success "已修复: $awk_file"
    fi
}

# ============ 主流程 ============

main() {
    echo ""
    echo "============================================"
    log_info "Android PRoot 源码准备"
    echo "============================================"
    echo "  源码目录: $SRC_DIR"
    echo "============================================"
    echo ""
    
    mkdir -p "$SRC_DIR"
    
    # 检查是否需要重新准备
    if check_marker "$SRC_DIR"; then
        log_success "源码已准备完成，无需重复操作"
        apply_patches
        echo ""
        return 0
    fi
    
    # 1. 克隆 proot 源码
    clone_if_needed "proot" "$PROOT_REPO" "$PROOT_BRANCH" "$SRC_DIR/proot" "src/proot.c"
    
    # 2. 下载 talloc 源码（从 Samba 官方 FTP）
    if [ ! -d "$SRC_DIR/talloc" ] || [ ! -f "$SRC_DIR/talloc/talloc.c" ]; then
        log_info "下载 talloc 源码..."
        local talloc_version="2.4.2"
        local talloc_url="https://www.samba.org/ftp/talloc/talloc-${talloc_version}.tar.gz"
        local talloc_tar="$SRC_DIR/talloc.tar.gz"

        cd "$SRC_DIR"
        rm -rf "$SRC_DIR/talloc"
        mkdir -p "$SRC_DIR/talloc"

        log_info "  URL: $talloc_url"
        curl -fL --retry 3 --retry-delay 2 -o "$talloc_tar" "$talloc_url"

        log_info "  解压到: $SRC_DIR/talloc（--strip-components=1）"
        if ! tar -xzf "$talloc_tar" -C "$SRC_DIR/talloc" --strip-components=1; then
            log_error "talloc 解压失败，归档目录预览（前 40 行）:"
            tar -tzf "$talloc_tar" | head -n 40 || true
            return 1
        fi

        if [ ! -f "$SRC_DIR/talloc/talloc.c" ]; then
            log_error "talloc 解压后未找到 talloc.c（归档结构可能变化），目录预览（前 40 行）:"
            tar -tzf "$talloc_tar" | head -n 40 || true
            return 1
        fi

        rm -f "$talloc_tar"
        log_success "talloc 源码下载完成"
    else
        log_info "talloc 源码已存在，跳过下载"
    fi
    
    # 3. talloc 交叉编译 cross-answers 文件由 build-android.sh 按架构生成（避免 aarch64/x86_64 冲突与不完整问题）
    
    # 5. 应用必要补丁（幂等）
    apply_patches

    # 6. 创建完成标记
    create_marker "$SRC_DIR"
    
    echo ""
    log_success "源码准备完成！"
    echo ""
}

main "$@"
