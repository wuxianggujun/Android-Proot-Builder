# ==========================================================================
# PRoot + libarchive — Android NDK CMake 构建脚本
#
# 产出:
#   1. proot        — PRoot 主程序（可执行文件）
#   2. proot-loader — PRoot Loader（特殊静态可执行文件）
#   3. archive      — libarchive 静态库
#
# 构建模式: PROOT_UNBUNDLE_LOADER
#   loader 作为独立可执行文件部署，运行时通过
#   PROOT_LOADER 环境变量指定 loader 路径。
# ==========================================================================
cmake_minimum_required(VERSION 3.22.1)
project("proot-termux" C ASM)

set(CMAKE_C_STANDARD 11)

# ==========================================================================
# 目录定义
# ==========================================================================
set(PROOT_SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/src)
set(TALLOC_DIR    ${CMAKE_CURRENT_SOURCE_DIR}/talloc)

# PRoot loader 的默认查找目录
# 运行时优先读取 PROOT_LOADER 环境变量，找不到才用此默认值
set(PROOT_LOADER_DIR "/data/local/tmp" CACHE STRING
    "PRoot loader 默认安装目录（运行时可通过 PROOT_LOADER 环境变量覆盖）")
option(TINA_PROOT_16KB_PAGE_ALIGNMENT
    "Link PRoot binaries with 16 KB max page size for Android 15+ devices"
    ON
)

# ==========================================================================
# 架构检测 — 根据 Android ABI 设置 loader 加载地址及特性开关
# ==========================================================================
if(CMAKE_ANDROID_ARCH_ABI STREQUAL "arm64-v8a")
    set(LOADER_ADDRESS "0x2000000000")
    set(PROOT_HAS_POKEDATA_WORKAROUND TRUE)
elseif(CMAKE_ANDROID_ARCH_ABI STREQUAL "armeabi-v7a")
    set(LOADER_ADDRESS "0x20000000")
    set(PROOT_HAS_POKEDATA_WORKAROUND FALSE)
elseif(CMAKE_ANDROID_ARCH_ABI STREQUAL "x86_64")
    set(LOADER_ADDRESS "0x600000000000")
    set(PROOT_HAS_POKEDATA_WORKAROUND FALSE)
elseif(CMAKE_ANDROID_ARCH_ABI STREQUAL "x86")
    set(LOADER_ADDRESS "0xa0000000")
    set(PROOT_HAS_POKEDATA_WORKAROUND FALSE)
else()
    message(FATAL_ERROR "不支持的 ABI: ${CMAKE_ANDROID_ARCH_ABI}")
endif()

message(STATUS "PRoot 目标 ABI: ${CMAKE_ANDROID_ARCH_ABI}")
message(STATUS "Loader 加载地址: ${LOADER_ADDRESS}")

# ==========================================================================
# 生成 build.h — PRoot 特性检测头文件
# ==========================================================================
# Android API 26+ 支持:
#   - process_vm_readv/writev (API 23+)
#   - seccomp filter (内核级支持)
file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/build.h
"/* 由 CMake 自动生成，请勿手动编辑 */
#ifndef BUILD_H
#define BUILD_H
#define VERSION \"proot-android-ndk\"
#define HAVE_PROCESS_VM
#define HAVE_SECCOMP_FILTER
#endif /* BUILD_H */
")

# ==========================================================================
# 生成 Android 兼容的 talloc config.h
#
# 原始 talloc config.h 是为 Linux x86_64 桌面环境生成的，
# 包含 Android 不存在的头文件（shadow.h, crypt.h, utmp.h 等）。
# 这里生成一份 Android 兼容版本。
# ==========================================================================
set(TALLOC_CONFIG_DIR ${CMAKE_CURRENT_BINARY_DIR}/talloc-config)
file(MAKE_DIRECTORY ${TALLOC_CONFIG_DIR})
file(WRITE ${TALLOC_CONFIG_DIR}/config.h
"/* Android NDK 兼容的 talloc 配置 — 由 CMake 自动生成 */
#ifndef _CONFIG_H_WAF
#define _CONFIG_H_WAF

#define _GNU_SOURCE 1
#define _XOPEN_SOURCE_EXTENDED 1
#define STDC_HEADERS 1
#define SYSTEM_UNAME_SYSNAME \"Linux\"
#define BUILD_SYSTEM \"Android\"
#define SHLIBEXT \"so\"

/* ---- 标准头文件 ---- */
#define HAVE_STDIO_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_STRINGS_H 1
#define HAVE_UNISTD_H 1
#define HAVE_STDINT_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_STDBOOL_H 1
#define HAVE_STDARG_H 1
#define HAVE_STDDEF_H 1
#define HAVE_LIMITS_H 1
#define HAVE_ERRNO_H 1
#define HAVE_CTYPE_H 1
#define HAVE_SIGNAL_H 1
#define HAVE_MEMORY_H 1
#define HAVE_MALLOC_H 1
#define HAVE_ASSERT_H 1
#define HAVE_FLOAT_H 1
#define HAVE_ALLOCA_H 1
#define HAVE_LOCALE_H 1
#define HAVE_FCNTL_H 1
#define HAVE_DIRENT_H 1
#define HAVE_DLFCN_H 1
#define HAVE_GRP_H 1
#define HAVE_PWD_H 1
#define HAVE_PTHREAD_H 1
#define HAVE_GETOPT_H 1
#define HAVE_SETJMP_H 1
#define HAVE_UTIME_H 1
#define HAVE_FNMATCH_H 1
#define HAVE_GLOB_H 1
#define HAVE_TERMIOS_H 1
#define HAVE_LIBGEN_H 1
#define HAVE_SYSLOG_H 1
#define HAVE_SYS_SYSLOG_H 1
#define HAVE_ENDIAN_H 1

/* ---- 系统头文件 ---- */
#define HAVE_SYS_TYPES_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_TIME_H 1
#define HAVE_TIME_H 1
#define TIME_WITH_SYS_TIME 1
#define HAVE_SYS_UTSNAME_H 1
#define HAVE_SYS_MMAN_H 1
#define HAVE_SYS_WAIT_H 1
#define HAVE_SYS_PARAM_H 1
#define HAVE_SYS_SELECT_H 1
#define HAVE_SYS_FILE_H 1
#define HAVE_SYS_IOCTL_H 1
#define HAVE_SYS_RESOURCE_H 1
#define HAVE_SYS_IPC_H 1
#define HAVE_SYS_SHM_H 1
#define HAVE_SYS_EPOLL_H 1
#define HAVE_SYS_XATTR_H 1
#define HAVE_SYS_UN_H 1
#define HAVE_SYS_UIO_H 1
#define HAVE_SYS_SOCKET_H 1
#define HAVE_SYS_MOUNT_H 1
#define HAVE_SYS_STATFS_H 1
#define HAVE_SYS_STATVFS_H 1
#define HAVE_SYS_VFS_H 1
#define HAVE_SYS_CDEFS_H 1
#define HAVE_SYS_SYSMACROS_H 1
#define HAVE_SYS_PRCTL_H 1
#define HAVE_SYS_AUXV_H 1
#define HAVE_SYS_SYSCALL_H 1
#define HAVE_SYS_EPOLL_H 1
#define HAVE_SYS_FCNTL_H 1
#define HAVE_LINUX_TYPES_H 1
#define HAVE_ASM_UNISTD_H 1
#define HAVE_NETINET_IN_H 1
#define HAVE_NETINET_TCP_H 1
#define HAVE_NETDB_H 1
#define HAVE_ARPA_INET_H 1
#define HAVE_IFADDRS_H 1
#define HAVE_NET_IF_H 1
#define HAVE_POLL_H 1

/* ---- 编译器特性 ---- */
#define HAVE___ATTRIBUTE__ 1
#define HAVE_VISIBILITY_ATTR 1
#define HAVE_CONSTRUCTOR_ATTRIBUTE 1
#define HAVE_DESTRUCTOR_ATTRIBUTE 1
#define HAVE_FUNCTION_MACRO 1
#define HAVE_VA_COPY 1
#define HAVE__VA_ARGS__MACRO 1
#define INLINE_MACRO 1
#define RETSIGTYPE void
#define HAVE_VOLATILE 1
#define HAVE_IMMEDIATE_STRUCTURES 1
#define HAVE___SYNC_FETCH_AND_ADD 1

/* ---- 整数类型 ---- */
#define HAVE_LONG_LONG 1
#define HAVE_INTPTR_T 1
#define HAVE_UINTPTR_T 1
#define HAVE_PTRDIFF_T 1
#define HAVE__Bool 1
#define HAVE_BOOL 1
#define HAVE_INT8_T 1
#define HAVE_UINT8_T 1
#define HAVE_INT16_T 1
#define HAVE_UINT16_T 1
#define HAVE_INT32_T 1
#define HAVE_UINT32_T 1
#define HAVE_INT64_T 1
#define HAVE_UINT64_T 1
#define HAVE_SIZE_T 1
#define HAVE_SSIZE_T 1
#define HAVE_INO_T 1
#define HAVE_LOFF_T 1
#define offset_t loff_t
#define HAVE_BLKSIZE_T 1
#define HAVE_BLKCNT_T 1
#define HAVE_SOCKLEN_T 1
#define HAVE_SA_FAMILY_T 1
#define HAVE_SIG_ATOMIC_T_TYPE 1

/* ---- 大小定义（自动适配 32/64 位） ---- */
#define SIZEOF_BOOL 1
#define SIZEOF_CHAR 1
#define SIZEOF_SHORT 2
#define SIZEOF_INT 4
#define SIZEOF_LONG_LONG 8
#define SIZEOF_INT8_T 1
#define SIZEOF_UINT8_T 1
#define SIZEOF_INT16_T 2
#define SIZEOF_UINT16_T 2
#define SIZEOF_INT32_T 4
#define SIZEOF_UINT32_T 4
#define SIZEOF_INT64_T 8
#define SIZEOF_UINT64_T 8
#if defined(__LP64__)
#  define SIZEOF_LONG 8
#  define SIZEOF_SIZE_T 8
#  define SIZEOF_SSIZE_T 8
#  define SIZEOF_VOID_P 8
#  define SIZEOF_OFF_T 8
#  define SIZEOF_DEV_T 8
#  define SIZEOF_INO_T 8
#  define SIZEOF_TIME_T 8
#else
#  define SIZEOF_LONG 4
#  define SIZEOF_SIZE_T 4
#  define SIZEOF_SSIZE_T 4
#  define SIZEOF_VOID_P 4
#  define SIZEOF_OFF_T 4
#  define SIZEOF_DEV_T 4
#  define SIZEOF_INO_T 4
#  define SIZEOF_TIME_T 4
#endif

/* ---- 函数支持 ---- */
#define HAVE_STRDUP 1
#define HAVE_STRNDUP 1
#define HAVE_STRNLEN 1
#define HAVE_MEMMEM 1
#define HAVE_MEMSET 1
#define HAVE_MEMCPY 1
#define HAVE_MEMMOVE 1
#define HAVE_BZERO 1
#define HAVE_PRINTF 1
#define HAVE_SNPRINTF 1
#define HAVE_VSNPRINTF 1
#define HAVE_ASPRINTF 1
#define HAVE_VASPRINTF 1
#define HAVE_C99_VSNPRINTF 1
#define HAVE_PIPE 1
#define HAVE_LSTAT 1
#define HAVE_DUP2 1
#define HAVE_DPRINTF 1
#define HAVE_VDPRINTF 1
#define HAVE_ISATTY 1
#define HAVE_CHOWN 1
#define HAVE_LCHOWN 1
#define HAVE_LINK 1
#define HAVE_READLINK 1
#define HAVE_SYMLINK 1
#define HAVE_REALPATH 1
#define HAVE_SETENV 1
#define HAVE_UNSETENV 1
#define HAVE_STRTOULL 1
#define HAVE_STRTOLL 1
#define HAVE_STRTOUQ 1
#define HAVE_STRTOQ 1
#define HAVE_MEMALIGN 1
#define HAVE_POSIX_MEMALIGN 1
#define HAVE_BASENAME 1
#define HAVE_DIRNAME 1
#define HAVE_STRFTIME 1
#define HAVE_SRANDOM 1
#define HAVE_RANDOM 1
#define HAVE_SRAND 1
#define HAVE_RAND 1
#define HAVE_USLEEP 1
#define HAVE_UTIME 1
#define HAVE_UTIMES 1
#define HAVE_MKTIME 1
#define HAVE_FTRUNCATE 1
#define HAVE_RENAME 1
#define HAVE_WAITPID 1
#define HAVE_WAIT4 1
#define HAVE_INITGROUPS 1
#define HAVE_PREAD 1
#define HAVE_PWRITE 1
#define HAVE_STRCASESTR 1
#define HAVE_STRSEP 1
#define HAVE_STRTOK_R 1
#define HAVE_STRERROR 1
#define HAVE_STRERROR_R 1
#define HAVE_MKDTEMP 1
#define HAVE_SETUID 1
#define HAVE_SETEUID 1
#define HAVE_SETREUID 1
#define HAVE_SETRESUID 1
#define HAVE_SETGID 1
#define HAVE_SETEGID 1
#define HAVE_SETREGID 1
#define HAVE_SETRESGID 1
#define HAVE_CHROOT 1
#define HAVE_SETSID 1
#define HAVE_SETGROUPS 1
#define HAVE_SYSCALL 1
#define HAVE_MMAP 1
#define HAVE_MREMAP 1
#define HAVE_GETIFADDRS 1
#define HAVE_FREEIFADDRS 1
#define HAVE_TIMEGM 1
#define HAVE_GETPAGESIZE 1
#define HAVE_GETPGRP 1
#define HAVE_EPOLL_CREATE 1
#define HAVE_CLOCK_GETTIME 1
#define HAVE_CLOCK_MONOTONIC 1
#define HAVE_CLOCK_REALTIME 1
#define HAVE_CLOCK_PROCESS_CPUTIME_ID 1
#define HAVE_STRUCT_TIMESPEC 1
#define HAVE_FDATASYNC 1
#define HAVE_GETAUXVAL 1
#define HAVE_PRCTL 1
#define HAVE_SIGACTION 1
#define HAVE_SIGPROCMASK 1
#define HAVE_SIGSET 1
#define HAVE_CONNECT 1
#define HAVE_GETHOSTBYNAME 1
#define HAVE_GETADDRINFO 1
#define HAVE_GETNAMEINFO 1
#define HAVE_FREEADDRINFO 1
#define HAVE_GAI_STRERROR 1
#define HAVE_SOCKETPAIR 1
#define HAVE_INET_NTOA 1
#define HAVE_INET_ATON 1
#define HAVE_INET_NTOP 1
#define HAVE_INET_PTON 1
#define HAVE_IPV6 1
#define HAVE_IPV6_V6ONLY 1
#define HAVE_GETPWNAM_R 1
#define HAVE_GETPWUID_R 1
#define HAVE_GETGRGID_R 1
#define HAVE_GETGRNAM_R 1
#define HAVE_GETGROUPLIST 1
#define HAVE_FGETXATTR 1
#define HAVE_FLISTXATTR 1
#define HAVE_FREMOVEXATTR 1
#define HAVE_FSETXATTR 1
#define HAVE_GETXATTR 1
#define HAVE_LISTXATTR 1
#define HAVE_REMOVEXATTR 1
#define HAVE_SETXATTR 1
#define HAVE_XATTR_SUPPORT 1
#define HAVE_DLOPEN 1
#define HAVE_DLSYM 1
#define HAVE_DLERROR 1
#define HAVE_DLCLOSE 1
#define HAVE_LIBDL 1
#define HAVE_POLL 1
#define HAVE_EPOLL 1
#define HAVE_STRPTIME 1
#define HAVE_IF_NAMETOINDEX 1
#define HAVE_PTHREAD_CREATE 1
#define HAVE_LIBPTHREAD 1
#define HAVE_PTHREAD_ATTR_INIT 1
#define HAVE_PTHREAD 1
#define HAVE_PTHREAD_MUTEXATTR_SETROBUST 1
#define HAVE_DECL_PTHREAD_MUTEX_ROBUST 1
#define HAVE_PTHREAD_MUTEX_CONSISTENT 1
#define HAVE_ROBUST_MUTEXES 1
#define HAVE_VSYSLOG 1
#define HAVE_SETLINEBUF 1
#define HAVE_SETBUFFER 1
#define HAVE_GET_CURRENT_DIR_NAME 1
#define HAVE_INOTIFY_INIT 1

/* ---- 声明检查 ---- */
#define HAVE_DECL_MALLOC 1
#define HAVE_DECL_EWOULDBLOCK 1
#define HAVE_DECL_SNPRINTF 1
#define HAVE_DECL_VSNPRINTF 1
#define HAVE_DECL_ASPRINTF 1
#define HAVE_DECL_VASPRINTF 1
#define HAVE_DECL_MEMALIGN 1
#define HAVE_DECL_FDATASYNC 1
#define HAVE_DECL_GETTIMEOFDAY 1
#define HAVE_DECL_STRPTIME 1
#define HAVE_DECL_DLOPEN 1
#define HAVE_ERRNO_DECL 1
#define HAVE_ENVIRON_DECL 1
#define HAVE_PREAD_DECL 1
#define HAVE_PWRITE_DECL 1
#define HAVE_SETENV_DECL 1
#define HAVE_SETRESUID_DECL 1
#define HAVE_SETRESGID_DECL 1
#define HAVE_GETTIMEOFDAY_TZ 1
#define HAVE_WORKING_STRPTIME 1

/* ---- 杂项 ---- */
#define HAVE_SHARED_MMAP 1
#define HAVE_SECURE_MKSTEMP 1
#define HAVE_LARGEFILE 1
#define HAVE_OPEN_O_DIRECT 1
#define HAVE_STAT_TV_NSEC 1
#define HAVE_STRUCT_STAT_ST_RDEV 1
#define HAVE_ST_RDEV 1
#define HAVE_SS_FAMILY 1
#define HAVE_UNIXSOCKET 1
#define HAVE_PEERCRED 1
#define HAVE_IFACE_GETIFADDRS 1
#define HAVE_MKDIR_MODE 1
#define HAVE_STRUCT_IFADDRS 1
#define HAVE_STRUCT_ADDRINFO 1
#define HAVE_STRUCT_SOCKADDR 1
#define HAVE_STRUCT_SOCKADDR_IN6 1
#define HAVE_STRUCT_SOCKADDR_STORAGE 1
#define HAVE_LITTLE_ENDIAN 1
#define HAVE_LIBREPLACE 1
#define LIBREPLACE_NETWORK_CHECKS 1
#define HAVE_SIMPLE_C_PROG 1

#endif /* _CONFIG_H_WAF */
")

# ==========================================================================
# 1. talloc 静态库
# ==========================================================================
add_library(talloc STATIC
    ${TALLOC_DIR}/talloc.c
    ${TALLOC_DIR}/lib/replace/replace.c
)

target_include_directories(talloc
    PUBLIC  ${TALLOC_DIR}              # talloc.h（proot 通过 <talloc.h> 引用）
    PRIVATE ${TALLOC_CONFIG_DIR}       # 优先使用我们生成的 Android config.h
    PRIVATE ${TALLOC_DIR}/lib/replace  # replace 内部头文件
)

target_compile_definitions(talloc PRIVATE
    _GNU_SOURCE
    HAVE_CONFIG_H
)

# 抑制 talloc/replace 中的编译警告（第三方代码）
target_compile_options(talloc PRIVATE -O2 -w)

# ==========================================================================
# 2. PRoot Loader — 特殊静态可执行文件
#
#    loader 是一个极简二进制，用于在 ptrace 拦截后加载目标程序：
#    - 不使用 C 标准库 (-nostdlib)
#    - 位置无关代码 (-fPIC)
#    - 独立运行环境 (-ffreestanding)
#    - 加载到固定内存地址 (-Ttext=LOADER_ADDRESS)
#    - 所有系统调用通过内联汇编实现
# ==========================================================================
add_executable(proot-loader
    ${PROOT_SRC_DIR}/loader/loader.c
    ${PROOT_SRC_DIR}/loader/assembly.S
)

target_include_directories(proot-loader PRIVATE
    ${PROOT_SRC_DIR}
)

target_compile_definitions(proot-loader PRIVATE
    _GNU_SOURCE
)

target_compile_options(proot-loader PRIVATE
    -fPIC
    -ffreestanding
    -O2
    -Wall
)

# 特殊链接选项
target_link_options(proot-loader PRIVATE
    -static
    -nostdlib
    "LINKER:--build-id=none"
    "LINKER:-Ttext=${LOADER_ADDRESS}"
    "LINKER:--rosegment"
    "LINKER:-z,noexecstack"
)

if(PROOT_HAS_POKEDATA_WORKAROUND)
    # Android NDK/LLD may garbage-collect this unreferenced ARM64 stub.
    # loader-info.c must read the symbol from the final loader binary.
    target_link_options(proot-loader PRIVATE
        "LINKER:--undefined=pokedata_workaround"
    )
endif()

if(TINA_PROOT_16KB_PAGE_ALIGNMENT)
    target_link_options(proot-loader PRIVATE
        "LINKER:-z,max-page-size=16384"
    )
endif()

# 关闭 PIE（与 -static -nostdlib 冲突）
# 输出命名为 libproot-loader.so（AGP 只会打包 lib*.so 格式的文件到 APK）
set_target_properties(proot-loader PROPERTIES
    POSITION_INDEPENDENT_CODE OFF
    PREFIX "lib"
    SUFFIX ".so"
)

# ==========================================================================
# 3. 生成 loader-info.c（仅 ARM64 需要）+ 剥离 loader
#
#    ARM64 存在 PTRACE_POKEDATA bug，需要一个变通方案。
#    loader-info.c 提供 pokedata_workaround 函数在 loader 中的偏移量，
#    供 proot 主程序在运行时定位该函数。
#
#    原始 GNUmakefile 使用 readelf + awk 生成此文件，
#    这里改用 CMake 脚本（cmake/gen_loader_info.cmake）替代，
#    以支持 Windows 主机构建。
#
#    注意执行顺序：必须先用 readelf 提取符号，再剥离 loader。
# ==========================================================================
if(PROOT_HAS_POKEDATA_WORKAROUND)
    # 从未剥离的 loader 提取符号信息，生成 loader-info.c
    add_custom_command(
        OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/loader-info.c
        DEPENDS proot-loader
        COMMAND ${CMAKE_COMMAND}
            -DREADELF=${CMAKE_READELF}
            -DLOADER=$<TARGET_FILE:proot-loader>
            -DOUTPUT=${CMAKE_CURRENT_BINARY_DIR}/loader-info.c
            -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/gen_loader_info.cmake
        COMMENT "生成 loader-info.c (ARM64 pokedata workaround)"
    )

    set(LOADER_INFO_SOURCE ${CMAKE_CURRENT_BINARY_DIR}/loader-info.c)
else()
    set(LOADER_INFO_SOURCE "")
endif()

# ==========================================================================
# 4. PRoot 主程序
# ==========================================================================
set(PROOT_SOURCES
    # ---- CLI ----
    ${PROOT_SRC_DIR}/cli/cli.c
    ${PROOT_SRC_DIR}/cli/proot.c
    ${PROOT_SRC_DIR}/cli/note.c

    # ---- execve ----
    ${PROOT_SRC_DIR}/execve/enter.c
    ${PROOT_SRC_DIR}/execve/exit.c
    ${PROOT_SRC_DIR}/execve/shebang.c
    ${PROOT_SRC_DIR}/execve/elf.c
    ${PROOT_SRC_DIR}/execve/ldso.c
    ${PROOT_SRC_DIR}/execve/auxv.c
    ${PROOT_SRC_DIR}/execve/aoxp.c

    # ---- path ----
    ${PROOT_SRC_DIR}/path/binding.c
    ${PROOT_SRC_DIR}/path/glue.c
    ${PROOT_SRC_DIR}/path/canon.c
    ${PROOT_SRC_DIR}/path/f2fs-bug.c
    ${PROOT_SRC_DIR}/path/path.c
    ${PROOT_SRC_DIR}/path/proc.c
    ${PROOT_SRC_DIR}/path/temp.c

    # ---- syscall ----
    ${PROOT_SRC_DIR}/syscall/seccomp.c
    ${PROOT_SRC_DIR}/syscall/syscall.c
    ${PROOT_SRC_DIR}/syscall/chain.c
    ${PROOT_SRC_DIR}/syscall/enter.c
    ${PROOT_SRC_DIR}/syscall/exit.c
    ${PROOT_SRC_DIR}/syscall/sysnum.c
    ${PROOT_SRC_DIR}/syscall/socket.c
    ${PROOT_SRC_DIR}/syscall/heap.c
    ${PROOT_SRC_DIR}/syscall/rlimit.c

    # ---- tracee ----
    ${PROOT_SRC_DIR}/tracee/tracee.c
    ${PROOT_SRC_DIR}/tracee/mem.c
    ${PROOT_SRC_DIR}/tracee/reg.c
    ${PROOT_SRC_DIR}/tracee/event.c
    ${PROOT_SRC_DIR}/tracee/seccomp.c
    ${PROOT_SRC_DIR}/tracee/statx.c

    # ---- ptrace ----
    ${PROOT_SRC_DIR}/ptrace/ptrace.c
    ${PROOT_SRC_DIR}/ptrace/user.c
    ${PROOT_SRC_DIR}/ptrace/wait.c

    # ---- extensions ----
    ${PROOT_SRC_DIR}/extension/extension.c
    ${PROOT_SRC_DIR}/extension/ashmem_memfd/ashmem_memfd.c
    ${PROOT_SRC_DIR}/extension/kompat/kompat.c
    ${PROOT_SRC_DIR}/extension/fake_id0/chown.c
    ${PROOT_SRC_DIR}/extension/fake_id0/chroot.c
    ${PROOT_SRC_DIR}/extension/fake_id0/getsockopt.c
    ${PROOT_SRC_DIR}/extension/fake_id0/sendmsg.c
    ${PROOT_SRC_DIR}/extension/fake_id0/socket.c
    ${PROOT_SRC_DIR}/extension/fake_id0/open.c
    ${PROOT_SRC_DIR}/extension/fake_id0/unlink.c
    ${PROOT_SRC_DIR}/extension/fake_id0/rename.c
    ${PROOT_SRC_DIR}/extension/fake_id0/chmod.c
    ${PROOT_SRC_DIR}/extension/fake_id0/utimensat.c
    ${PROOT_SRC_DIR}/extension/fake_id0/access.c
    ${PROOT_SRC_DIR}/extension/fake_id0/exec.c
    ${PROOT_SRC_DIR}/extension/fake_id0/link.c
    ${PROOT_SRC_DIR}/extension/fake_id0/symlink.c
    ${PROOT_SRC_DIR}/extension/fake_id0/mk.c
    ${PROOT_SRC_DIR}/extension/fake_id0/stat.c
    ${PROOT_SRC_DIR}/extension/fake_id0/helper_functions.c
    ${PROOT_SRC_DIR}/extension/fake_id0/fake_id0.c
    ${PROOT_SRC_DIR}/extension/hidden_files/hidden_files.c
    ${PROOT_SRC_DIR}/extension/mountinfo/mountinfo.c
    ${PROOT_SRC_DIR}/extension/port_switch/port_switch.c
    ${PROOT_SRC_DIR}/extension/sysvipc/sysvipc.c
    ${PROOT_SRC_DIR}/extension/sysvipc/sysvipc_msg.c
    ${PROOT_SRC_DIR}/extension/sysvipc/sysvipc_sem.c
    ${PROOT_SRC_DIR}/extension/sysvipc/sysvipc_shm.c
    ${PROOT_SRC_DIR}/extension/link2symlink/link2symlink.c
    ${PROOT_SRC_DIR}/extension/fix_symlink_size/fix_symlink_size.c

    # ---- loader-info（ARM64 POKEDATA workaround） ----
    ${LOADER_INFO_SOURCE}
)

add_executable(proot ${PROOT_SOURCES})

target_include_directories(proot PRIVATE
    ${PROOT_SRC_DIR}
    ${CMAKE_CURRENT_BINARY_DIR}   # build.h 所在目录
)

target_compile_definitions(proot PRIVATE
    _FILE_OFFSET_BITS=64
    _GNU_SOURCE
    # PROOT_UNBUNDLE_LOADER 模式:
    #   loader 不内嵌到 proot 二进制中，而是作为独立文件部署。
    #   运行时查找顺序:
    #     1. PROOT_LOADER 环境变量（如果设置）
    #     2. PROOT_UNBUNDLE_LOADER/loader（默认路径）
    PROOT_UNBUNDLE_LOADER="${PROOT_LOADER_DIR}"
)

target_compile_options(proot PRIVATE
    -Wall
    -Wextra
    -O2
    # PRoot 源码有部分文件缺少 #include <string.h> 等头文件声明，
    # NDK Clang 默认将隐式函数声明视为错误，这里降级为警告
    -Wno-error=implicit-function-declaration
    -Wno-error=int-conversion
)

target_link_libraries(proot PRIVATE talloc)

target_link_options(proot PRIVATE
    "LINKER:-z,noexecstack"
)

if(TINA_PROOT_16KB_PAGE_ALIGNMENT)
    target_link_options(proot PRIVATE
        "LINKER:-z,max-page-size=16384"
    )
endif()

# 确保 loader 在 proot 之前构建（loader-info.c 依赖 loader 二进制）
add_dependencies(proot proot-loader)

# 输出命名为 libproot.so（AGP 只会打包 lib*.so 格式的文件到 APK）
set_target_properties(proot PROPERTIES
    PREFIX "lib"
    SUFFIX ".so"
)

# ==========================================================================
# 5. libarchive 静态库
#
#    只构建核心库，禁用命令行工具和测试。
#    Android NDK 自带 zlib，其他压缩库（bzip2, lzma 等）
#    根据系统可用性自动启用/禁用。
# ==========================================================================

# 禁用不需要的组件
set(ENABLE_TAR OFF CACHE BOOL "" FORCE)
set(ENABLE_CPIO OFF CACHE BOOL "" FORCE)
set(ENABLE_CAT OFF CACHE BOOL "" FORCE)
set(ENABLE_UNZIP OFF CACHE BOOL "" FORCE)
set(ENABLE_TEST OFF CACHE BOOL "" FORCE)
set(ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
set(ENABLE_WERROR OFF CACHE BOOL "" FORCE)

# 禁用 Android NDK 不自带的可选依赖
set(ENABLE_OPENSSL OFF CACHE BOOL "" FORCE)
set(ENABLE_MBEDTLS OFF CACHE BOOL "" FORCE)
set(ENABLE_NETTLE OFF CACHE BOOL "" FORCE)
set(ENABLE_LIBB2 OFF CACHE BOOL "" FORCE)
set(ENABLE_LZ4 OFF CACHE BOOL "" FORCE)
set(ENABLE_LZO OFF CACHE BOOL "" FORCE)
set(ENABLE_LZMA OFF CACHE BOOL "" FORCE)
set(ENABLE_ZSTD OFF CACHE BOOL "" FORCE)
set(ENABLE_BZip2 OFF CACHE BOOL "" FORCE)
set(ENABLE_LIBXML2 OFF CACHE BOOL "" FORCE)
set(ENABLE_EXPAT OFF CACHE BOOL "" FORCE)
set(ENABLE_PCREPOSIX OFF CACHE BOOL "" FORCE)
set(ENABLE_PCRE2POSIX OFF CACHE BOOL "" FORCE)
set(ENABLE_LIBGCC OFF CACHE BOOL "" FORCE)
set(ENABLE_CNG OFF CACHE BOOL "" FORCE)
set(ENABLE_ACL OFF CACHE BOOL "" FORCE)
set(ENABLE_XATTR OFF CACHE BOOL "" FORCE)

# Android NDK 自带 zlib，保留启用
set(ENABLE_ZLIB ON CACHE BOOL "" FORCE)

# 构建静态库
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

add_subdirectory(libarchive)

# 将 archive_static 添加为构建目标（proot 依赖它确保它会被构建）
# 同时导出为 libarchive.a 供运行时使用
target_link_libraries(proot PRIVATE archive_static)
