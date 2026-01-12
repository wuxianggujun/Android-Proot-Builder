# PRoot 编译指南

本文档说明如何从 Termux 源码编译 PRoot 及其依赖，用于 Android PRoot Builder 的 Linux 环境支持。

## 概述

Android PRoot Builder 使用 PRoot 在 Android 上提供 Linux 环境支持。PRoot 是一个用户空间实现的 `chroot` 和 `mount --bind` 替代方案，无需 root 权限即可在 Android 上运行 Linux 程序。

### 组件说明

| 组件 | 文件名 | 用途 |
|------|--------|------|
| PRoot 主程序 | `libproot.so` | 核心程序，提供 rootfs 隔离和系统调用翻译 |
| ELF Loader (64-bit) | `libproot-loader.so` | 加载和执行 ELF 可执行文件 |
| ELF Loader (32-bit) | `libproot-loader32.so` | 在 64 位系统上运行 32 位程序 |
| talloc 库 | `libtalloc.so.2` | 内存分配库（`TallocLink=shared` 时为运行时依赖并输出；`TallocLink=static` 默认不输出也不需要分发） |

### 为什么需要自己编译？

1. **Android 兼容性修复**: Android 16+ 存在 seccomp/clone3 兼容性问题
2. **问题调试**: 可以添加日志和调试符号
3. **版本同步**: 随时获取 Termux 上游的 bug 修复
4. **自定义修改**: 根据需求定制 proot 行为

## 编译环境

### 前置要求

- Docker Desktop（Windows/macOS）或 Docker Engine（Linux）
- PowerShell 5.1+ 或 PowerShell 7+
- 约 5GB 磁盘空间（NDK + 构建缓存）
- 网络连接（下载 NDK 和源码）

### 目标平台

| 架构 | Android ABI | 说明 |
|------|-------------|------|
| aarch64 | arm64-v8a | 大多数 Android 手机/平板 |
| x86_64 | x86_64 | 模拟器和部分 Chromebook |

### Android API 级别

编译目标为 **API 28 (Android 9.0)**，确保广泛的设备兼容性。

## 快速编译

### 一键构建

```powershell
# 构建所有架构（首次运行会克隆源码，后续复用）
\.\\build-proot.ps1

# 只构建 arm64（真机）
\.\\build-proot.ps1 -Arch arm64

# 将 talloc 静态链接进 libproot.so（运行时不再依赖 libtalloc.so.2）
\.\\build-proot.ps1 -Arch arm64 -TallocLink static

# 构建并自动集成到项目
\.\\build-proot.ps1 -CopyToJniLibs -CopyToAssets
```

### 增量构建

构建系统支持增量编译，源码通过 Docker volume 持久化：

```powershell
# 首次构建：克隆源码 + 编译（约 5-10 分钟）
\.\\build-proot.ps1

# 后续构建：复用源码 + 增量编译（约 1-2 分钟）
\.\\build-proot.ps1
```

### 构建产物

```
    output/
├── arm64/
│   ├── libproot.so           # 约 500KB
│   ├── libproot-loader.so    # 约 50KB
│   ├── libproot-loader32.so  # 约 40KB
│   └── libtalloc.so.2        # 约 100KB（仅 TallocLink=shared 时输出）
└── x86_64/
    ├── libproot.so
    ├── libproot-loader.so
    └── libtalloc.so.2        # 仅 TallocLink=shared 时输出
```

## 详细编译步骤

### 1. 准备 Docker 环境

```powershell
# 确保 Docker 正在运行
docker version

# 确保有多架构支持（用于交叉编译）
docker buildx create --name proot-builder-multiarch --use
docker buildx inspect --bootstrap
```

### 2. 构建 Docker 镜像

Docker 镜像包含：
- Ubuntu 24.04 基础系统
- Android NDK r27c（优先使用国内镜像）
- 构建工具链（make, cmake, autoconf 等）

```powershell
# 镜像会自动在首次构建时创建
\.\\build-proot.ps1
```

### 3. 源码准备

源码通过 Docker volume (`proot-builder-source`) 持久化，`prepare-source.sh` 脚本负责：

1. **检查现有源码**: 如果源码已存在且完整，跳过下载/克隆
2. **克隆源码**: 从 GitHub 克隆 Termux proot 和依赖
3. **创建标记文件**: 记录准备完成状态

```powershell
# 查看源码 volume
docker volume inspect proot-builder-source

# 进入容器查看源码
docker run -it --rm -v proot-builder-source:/build/src ubuntu:24.04 ls -la /build/src
```

### 4. 编译过程

编译脚本 `build-android.sh` 依次执行：

1. **编译 talloc**
   ```bash
   ./configure --cross-compile --disable-python
   make -j$(nproc)
   ```

2. **编译 proot-loader**
   ```bash
   make CC=aarch64-linux-android28-clang
   ```

3. **编译 proot-loader32**（仅 arm64）
   ```bash
   make CC=armv7a-linux-androideabi28-clang
   ```

4. **编译 proot**
   ```bash
   make CC=aarch64-linux-android28-clang \
        CFLAGS="-DPROOT_UNBUNDLE_LOADER=1"
   ```

### 5. 集成到项目

#### 自动集成

```powershell
\.\\build-proot.ps1 -CopyToJniLibs -CopyToAssets

# 如果使用 -TallocLink static，一般不需要 -CopyToAssets（可减少 APK 体积）
\.\\build-proot.ps1 -CopyToJniLibs -TallocLink static
```

#### 手动集成

```powershell
# PRoot 二进制 → jniLibs（随 APK 分发）
Copy-Item output\arm64\libproot*.so app\src\main\jniLibs\arm64-v8a\
Copy-Item output\x86_64\libproot*.so app\src\main\jniLibs\x86_64\

# libtalloc → assets（运行时解压）
Copy-Item output\arm64\libtalloc.so.2 app\src\arm64\assets\proot\arm64-v8a\
Copy-Item output\x86_64\libtalloc.so.2 app\src\x86_64\assets\proot\x86_64\
```

## 项目文件结构

编译后的文件在项目中的位置：

```
Android PRoot Builder/
├── app/src/main/
│   └── jniLibs/
│       ├── arm64-v8a/
│       │   ├── libproot.so           # PRoot 主程序
│       │   ├── libproot-loader.so    # ELF loader
│       │   └── libproot-loader32.so  # 32-bit compat
│       └── x86_64/
│           ├── libproot.so
│           └── libproot-loader.so
├── app/src/arm64/assets/proot/
│   └── arm64-v8a/
│       └── libtalloc.so.2           # 运行时解压
└── app/src/x86_64/assets/proot/
    └── x86_64/
        └── libtalloc.so.2
```

### 为什么分开放置？

- **jniLibs**: Android 允许直接执行 `nativeLibraryDir` 中的 `.so` 文件
- **assets**: `libtalloc.so.2` 需要在运行时解压到可写目录，因为文件名带版本号

## 源码说明

### 使用的源码仓库

| 组件 | 仓库 | 用途 |
|------|------|------|
| proot | [termux/proot](https://github.com/termux/proot) | Termux 官方 Android 优化版 |
| proot-loader | termux/proot（src/loader） | ELF 加载器 |
| talloc | 同上 | 内存分配库 |

### 官方 Termux 仓库

如需研究完整的 Termux 构建系统：

```bash
# proot 源码
git clone https://github.com/termux/proot.git

# proot-distro（包含额外工具）
git clone https://github.com/termux/proot-distro.git

# Termux 构建系统（包含所有补丁）
git clone https://github.com/termux/termux-packages.git
```

### 关键编译选项

| 选项 | 说明 |
|------|------|
| `PROOT_UNBUNDLE_LOADER=1` | 使用外部 loader 文件 |
| `-fPIE` / `-pie` | Position Independent Executable |
| `-O2` | 优化级别 |

## Android 兼容性

### Android 16+ (API 36+) 问题

Android 16 开始，部分设备上 PRoot 的 seccomp 加速与 guest libc 的 clone3 使用冲突，导致 `fork: Function not implemented` 错误。

#### 解决方案

1. **运行时禁用 seccomp**（当前方案）
   ```kotlin
   if (Build.VERSION.SDK_INT >= 36) {
       env["PROOT_NO_SECCOMP"] = "1"
       env["KERNEL_RELEASE"] = "4.14.0"
   }
   ```

2. **编译时禁用 seccomp**（可选）
   ```bash
   make CFLAGS="-DDISABLE_SECCOMP"
   ```

### 环境变量说明

| 变量 | 用途 |
|------|------|
| `PROOT_LOADER` | 指定 libproot-loader.so 路径 |
| `PROOT_LOADER32` | 指定 libproot-loader32.so 路径 |
| `PROOT_NO_SECCOMP` | 禁用 seccomp 加速 |
| `PROOT_TMP_DIR` | 临时文件目录 |
| `LD_LIBRARY_PATH` | 动态库搜索路径（包含 libtalloc） |

## 容器复用与清理

### Docker 资源

构建过程使用以下 Docker 资源：

| 资源类型 | 名称 | 用途 | 持久化 |
|----------|------|------|--------|
| 镜像 | `proot-builder:arm64` | arm64 构建环境 | 是 |
| 镜像 | `proot-builder:x86_64` | x86_64 构建环境 | 是 |
| Volume | `proot-builder-source` | 源码存储 | 是 |

### 查看资源

```powershell
# 查看镜像
docker images | Select-String "proot-builder"

# 查看 volume
docker volume ls | Select-String "proot-builder"

# 查看 volume 详情
docker volume inspect proot-builder-source
```

### 清理策略

| 场景 | 命令 | 影响 |
|------|------|------|
| 清理输出文件 | `clean.ps1 -RemoveOutput` | 删除编译产物 |
| 重建镜像 | `clean.ps1 -RemoveImages` | 需重新下载 NDK |
| 重新克隆源码 | `clean.ps1 -RemoveSource` | 需重新下载源码 |
| 完全清理 | `clean.ps1 -All` | 全部删除 |

## 故障排除

### Docker 构建失败

```powershell
# 检查 Docker 状态
docker version

# 清理后重试
\.\\clean.ps1 -All
\.\\build-proot.ps1 -Mode clean
```

### NDK 下载慢

Dockerfile 已配置自动尝试腾讯云镜像，如仍然慢：

```dockerfile
# 手动下载后放到 /opt/android-ndk
docker run -it --rm -v /path/to/local/ndk:/opt/android-ndk proot-builder:arm64 /bin/bash
```

### 编译错误

检查构建日志：

```powershell
# 查看完整日志
docker logs proot-builder-build-arm64 2>&1

# 进入容器调试
docker run -it --rm -v proot-builder-source:/build/src proot-builder:arm64 /bin/bash

# 在容器内手动运行
cd /build
/build/scripts/prepare-source.sh
/build/scripts/build-android.sh
```

### 运行时错误

常见错误及解决：

| 错误 | 原因 | 解决 |
|------|------|------|
| `cannot execute binary file` | ELF 格式不匹配 | 确认编译架构正确 |
| `fork: Function not implemented` | seccomp/兼容性问题 | **仅在老旧内核（Linux < 4.14 / 常见于 Android 9-）或确认 seccomp 崩溃时**，才临时设置 `PROOT_NO_SECCOMP=1` 兜底；Android 10+（Linux 4.14+）建议保持 unset |
| `libtalloc.so.2: cannot open` | 库文件缺失 | 确认 libtalloc 已解压 |

## 参考资料

- [Termux PRoot](https://github.com/termux/proot)
- [PRoot 官方文档](https://proot-me.github.io/)
- termux/proot（src/loader）
- [Android NDK](https://developer.android.com/ndk)

## 更新日志

- **2024-01**: 初始版本
  - 支持 arm64 和 x86_64 编译
  - 源码持久化（Docker volume）
  - 增量编译支持
  - 国内 NDK 镜像加速


