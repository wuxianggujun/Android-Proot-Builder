# Android PRoot Builder
# 从 Termux proot 源码编译 proot 和 proot-loader
#
# 特性：
# - 不做包名替换
# - 源码持久化（挂载 volume，避免重复克隆）
# - 增量编译支持
#
# 参考：https://github.com/termux/proot

FROM ubuntu:24.04

# 设置非交互模式
ENV DEBIAN_FRONTEND=noninteractive

# 使用清华大学镜像源（中国大陆加速）
# 注意：这里使用 http，避免极少数环境中 HTTPS 证书链不可用导致 apt 无法更新。
RUN set -e; \
    file=/etc/apt/sources.list.d/ubuntu.sources; \
    sed -i 's|URIs: http://archive.ubuntu.com/ubuntu/|URIs: http://mirrors.tuna.tsinghua.edu.cn/ubuntu/|g' "$file"; \
    sed -i 's|URIs: http://security.ubuntu.com/ubuntu/|URIs: http://mirrors.tuna.tsinghua.edu.cn/ubuntu/|g' "$file"

# ============================================
# 第一层：安装最基础的工具（用于下载 NDK）
# 这一层几乎不会变化
# ============================================
RUN set -e; \
    file=/etc/apt/sources.list.d/ubuntu.sources; \
    write_official_sources() { \
      printf '%s\n' \
        'Types: deb' \
        'URIs: http://archive.ubuntu.com/ubuntu/' \
        'Suites: noble noble-updates noble-backports' \
        'Components: main universe restricted multiverse' \
        'Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg' \
        '' \
        'Types: deb' \
        'URIs: http://security.ubuntu.com/ubuntu/' \
        'Suites: noble-security' \
        'Components: main universe restricted multiverse' \
        'Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg' \
        > "$file"; \
    }; \
    apt_get_update() { apt-get -o Acquire::Retries=5 update; }; \
    apt_get_install() { apt-get -o Acquire::Retries=5 install -y --no-install-recommends "$@"; }; \
    apt_get_update || ( \
      echo "[WARN] apt update failed, fallback to official mirror..."; \
      write_official_sources; \
      apt_get_update \
    ); \
    apt_get_install ca-certificates curl unzip || ( \
      echo "[WARN] apt install failed, retry with official mirror..."; \
      write_official_sources; \
      apt_get_update; \
      apt_get_install ca-certificates curl unzip \
    ); \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# ============================================
# 第二层：下载 Android NDK（最大的文件，放在前面）
# 这一层几乎不会变化，避免重复下载
# ============================================
ARG NDK_VERSION=r27c
ARG NDK_PLATFORM=linux
ENV ANDROID_NDK_ROOT=/opt/android-ndk
ENV ANDROID_NDK_HOME=/opt/android-ndk

# 使用阿里云镜像下载 Android NDK（国内加速）
RUN mkdir -p /opt && cd /opt && \
    echo "[INFO] 下载 Android NDK ${NDK_VERSION}..." && \
    echo "[INFO] 使用阿里云镜像..." && \
    ( \
      set -e; \
      download() { \
        url="$1"; \
        echo "[INFO] 下载: $url"; \
        i=0; \
        while [ $i -lt 5 ]; do \
          i=$((i+1)); \
          rm -f ndk.zip; \
          if curl -fL --connect-timeout 30 --max-time 1200 --retry 3 --retry-delay 2 --retry-all-errors -o ndk.zip "$url"; then \
            return 0; \
          fi; \
          echo "[WARN] 下载失败，重试 $i/5 ..."; \
          sleep 2; \
        done; \
        return 1; \
      }; \
      download "https://mirrors.aliyun.com/android/repository/android-ndk-${NDK_VERSION}-${NDK_PLATFORM}.zip" || \
      (echo "[WARN] 阿里云失败，使用官方源..." && download "https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-${NDK_PLATFORM}.zip"); \
    ) && \
    echo "[INFO] 解压 NDK..." && \
    unzip -q ndk.zip && \
    mv android-ndk-* android-ndk && \
    rm ndk.zip && \
    echo "[OK] NDK 安装完成"

# ============================================
# 第三层：安装其他构建依赖
# 这一层可能会调整，但不会影响 NDK 缓存
# ============================================
RUN set -e; \
    file=/etc/apt/sources.list.d/ubuntu.sources; \
    write_official_sources() { \
      printf '%s\n' \
        'Types: deb' \
        'URIs: http://archive.ubuntu.com/ubuntu/' \
        'Suites: noble noble-updates noble-backports' \
        'Components: main universe restricted multiverse' \
        'Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg' \
        '' \
        'Types: deb' \
        'URIs: http://security.ubuntu.com/ubuntu/' \
        'Suites: noble-security' \
        'Components: main universe restricted multiverse' \
        'Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg' \
        > "$file"; \
    }; \
    apt_get_update() { apt-get -o Acquire::Retries=5 update; }; \
    apt_get_install() { apt-get -o Acquire::Retries=5 install -y --no-install-recommends "$@"; }; \
    apt_get_update || ( \
      echo "[WARN] apt update failed, fallback to official mirror..."; \
      write_official_sources; \
      apt_get_update \
    ); \
    apt_get_install \
    # 基础工具
    wget \
    git \
    file \
    binutils \
    gawk \
    xz-utils \
    sed \
    # 编译工具
    build-essential \
    make \
    cmake \
    autoconf \
    automake \
    libtool \
    pkg-config \
    python3 \
    # talloc 依赖
    docbook-xsl \
    xsltproc \
    # proot 依赖
    libarchive-dev \
    || ( \
      echo "[WARN] apt install failed, retry with official mirror..."; \
      write_official_sources; \
      apt_get_update; \
      apt_get_install wget git file binutils gawk xz-utils sed build-essential make cmake autoconf automake libtool pkg-config python3 docbook-xsl xsltproc libarchive-dev \
    ); \
    update-alternatives --set awk /usr/bin/gawk 2>/dev/null || true; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 配置 Git 全局设置（避免认证问题）
RUN git config --global http.sslVerify false && \
    git config --global credential.helper store && \
    git config --global url."https://".insteadOf git://

# ============================================
# 第四层：设置工作目录和复制脚本
# 这一层经常变化，但不会影响前面的缓存
# ============================================

# 设置工作目录
# /build/src 会作为 volume 挂载，持久化源码
WORKDIR /build

# 创建目录结构
RUN mkdir -p /build/src /build/scripts

# 复制构建脚本
COPY build-android.sh /build/scripts/build-android.sh
COPY prepare-source.sh /build/scripts/prepare-source.sh
RUN chmod +x /build/scripts/*.sh

# 默认架构参数
ARG TARGET_ARCH=aarch64
ENV TARGET_ARCH=${TARGET_ARCH}

# 源码目录作为 volume（持久化）
VOLUME ["/build/src"]

# 输出目录
VOLUME ["/output"]

# 入口脚本：先准备源码，再编译
CMD ["/bin/bash", "-c", "/build/scripts/prepare-source.sh && /build/scripts/build-android.sh"]
