# TinaIDE PRoot 构建模式

本子模块用于给 TinaIDE 提供 Android 版 PRoot 源码构建能力，同时保留旧的 Docker 产物构建链路。

## 构建模式

### 1. Docker 产物模式（默认稳定链路）

TinaIDE 主仓库仍保留 `docker/proot-build`：

```powershell
.\docker\proot-build\build-proot.ps1 -Arch arm64 -CopyToJniLibs
.\docker\proot-build\build-proot.ps1 -Arch x86_64 -CopyToJniLibs
```

此模式在 Linux 容器内使用 Android NDK 交叉编译，产物复制到主仓库的预编译 PRoot source set。

适用场景：

- 发布前需要固定、可复现的二进制产物。
- 本机没有完整 Android CMake/Ninja 环境。
- 需要继续沿用历史 Docker 调试脚本。

### 2. CMake 直接编译模式（实验链路）

本子模块根目录提供 Android NDK CMake 构建入口，可直接生成：

```text
libproot.so
libproot-loader.so
libproot-loader32.so（仅需要 32 位兼容构建时）
```

TinaIDE 主仓库通过 Gradle 属性启用：

```powershell
.\gradlew.bat :app:assembleArm64Debug '-Ptina.buildProotFromSource=true'
```

也可以独立调用 Android SDK 自带 CMake/Ninja：

```powershell
$SDK = "D:\Programs\Android\Sdk"
$NDK = "$SDK\ndk\27.2.12479018"
$CMAKE = "$SDK\cmake\3.22.1\bin\cmake.exe"
$NINJA = "$SDK\cmake\3.22.1\bin\ninja.exe"

& $CMAKE -S . -B build-arm64 -G Ninja `
  "-DCMAKE_MAKE_PROGRAM=$NINJA" `
  "-DCMAKE_TOOLCHAIN_FILE=$NDK\build\cmake\android.toolchain.cmake" `
  -DANDROID_ABI=arm64-v8a `
  -DANDROID_PLATFORM=android-28 `
  -DCMAKE_BUILD_TYPE=Release

& $CMAKE --build build-arm64 --target proot proot-loader -j 4
```

## TinaIDE 定制点

- `TINA_PROOT_16KB_PAGE_ALIGNMENT=ON`：默认开启 16 KB 页面对齐，适配 Android 15+。
- ARM64 loader 链接时保留 `pokedata_workaround` 符号，确保 `loader-info.c` 可从最终 loader 二进制计算偏移。
- 输出仍命名为 `libproot*.so`，便于 Android Gradle Plugin 打包到 `nativeLibraryDir`。

## 子模块发布规则

如果修改本子模块并让主仓库指向新提交，必须遵守顺序：

1. 先提交并推送本子模块分支。
2. 再回到 TinaIDE 主仓库提交子模块指针。
3. 发布前运行 `git submodule status --recursive`，确认主仓库记录的提交在远端可达。

未推送的子模块提交不能进入主仓库发布提交，否则 CI 执行 `git submodule update --recursive` 时可能出现 `not our ref`。
