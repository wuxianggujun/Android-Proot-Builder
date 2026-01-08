# Dockerfile 层级优化说明

## 优化原理

Docker 使用**层缓存机制**：
- 每个 `RUN`、`COPY` 等指令都会创建一个层
- 当某一层发生变化时，这一层及之后的所有层都会失效
- 因此，应该把**不常变的放前面，常变的放后面**

## 优化后的层级结构

```dockerfile
# 第 1 层：基础镜像 + 换源
FROM ubuntu:24.04
RUN sed -i ... 换源

# 第 2 层：最基础的工具（curl, unzip）
RUN apt-get install curl unzip
# 原因：只安装下载 NDK 必需的工具，几乎不会变

# 第 3 层：下载 Android NDK（633MB）
RUN curl ... NDK ... && unzip
# 原因：最大的文件，放在前面避免重复下载

# 第 4 层：其他构建依赖
RUN apt-get install git cmake make ...
# 原因：可能会调整（比如加个新包），但不影响 NDK 缓存

# 第 5 层：复制构建脚本
COPY build-android.sh ...
# 原因：经常修改，放在最后
```

## 优化效果

### 优化前（旧版本）
```
修改依赖包（加 unzip）
  ↓
第 3 层失效：apt-get install（包含 unzip）
  ↓
第 4 层失效：下载 NDK ← 重新下载 633MB！
  ↓
第 5 层失效：复制脚本
```

### 优化后（新版本）
```
修改依赖包（加新包）
  ↓
第 2 层缓存：curl, unzip（不变）
  ↓
第 3 层缓存：NDK ← 复用缓存，不重新下载！
  ↓
第 4 层失效：apt-get install（重新安装依赖）
  ↓
第 5 层失效：复制脚本
```

## 常见场景

| 修改内容 | 是否重新下载 NDK | 耗时 |
|---------|-----------------|------|
| 修改构建脚本 | ❌ 否 | 1 分钟 |
| 添加/删除依赖包 | ❌ 否 | 3 分钟 |
| 更新 NDK 版本 | ✅ 是 | 15 分钟 |
| 更换 Ubuntu 镜像源 | ✅ 是 | 15 分钟 |

## 最佳实践

1. **不常变的放前面**
   - 基础镜像
   - 镜像源配置
   - 大文件下载（NDK）

2. **可能变的放中间**
   - 依赖包安装
   - 环境变量设置

3. **经常变的放后面**
   - 复制源码
   - 复制脚本
   - 应用配置

## 验证缓存是否生效

构建时看到 `CACHED` 表示使用了缓存：

```
#1 [1/5] FROM ubuntu:24.04
#1 CACHED

#2 [2/5] RUN sed -i ... 换源
#2 CACHED

#3 [3/5] RUN apt-get install curl unzip
#3 CACHED

#4 [4/5] RUN curl ... NDK ...
#4 CACHED  ← 看到这个就说明 NDK 没有重新下载！

#5 [5/5] RUN apt-get install git cmake ...
#5 0.234 Reading package lists...  ← 这一层重新执行
```

## 总结

通过合理安排 Dockerfile 层级顺序，可以：
- ✅ 避免重复下载大文件（NDK 633MB）
- ✅ 加快构建速度（从 15 分钟降到 3 分钟）
- ✅ 节省网络流量
- ✅ 提升开发体验
