# ============================================================
# DevNote APK 一键构建脚本（Windows / PowerShell）
# ------------------------------------------------------------
# 用法：
#   .\scripts\build_apk.ps1                  # Release 构建
#   .\scripts\build_apk.ps1 -DebugBuild      # Debug 构建
#   .\scripts\build_apk.ps1 -Clean           # 先清理再构建
#   .\scripts\build_apk.ps1 -NoProxy         # 显式跳过代理
#   .\scripts\build_apk.ps1 -SkipEnvCheck    # 跳过 CMake/JDK 版本检查
#   .\scripts\build_apk.ps1 -FullClean       # 深度清理所有 .cxx 缓存（包括插件）
# ============================================================

[CmdletBinding()]
param(
    [switch]$DebugBuild,
    [switch]$Clean,
    [switch]$FullClean,
    [switch]$NoProxy,
    [switch]$SkipEnvCheck
)

# 重要：不使用 $ErrorActionPreference='Stop'
# 原因：Stop 模式会把 native command 的 stderr 当作终止错误，导致 flutter/gradle
# 的 WARNING 输出（走 stderr）触发脚本中断。改用 Continue，通过显式检查
# 退出码来判断成功失败。
$ErrorActionPreference = 'Continue'

# --- 项目根目录（脚本所在目录的上一级） -----------------------
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$ProjectRoot = Split-Path -Parent $ScriptDir

# 不用 Set-Location（会改变调用者的全局工作目录），改用 Push-Location
# 脚本退出时通过 finally 块自动恢复
Push-Location $ProjectRoot
try {

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host '  DevNote APK Build Script' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "  Project Root : $ProjectRoot"
Write-Host "  Build Mode   : $(if ($DebugBuild) { 'Debug' } else { 'Release' })"
Write-Host "  Clean Build  : $Clean"
Write-Host "  Full Clean   : $FullClean"
Write-Host "  Skip EnvChk  : $SkipEnvCheck"
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''

# ============================================================
# 步骤 1/6：JAVA_HOME 探测 + JDK 版本检查
# ============================================================
# 优先级：候选路径探测 > 环境变量 JAVA_HOME > 失败退出
$JavaCandidates = @(
    'D:\Software\001_AndriodTools\002_DevTool\001Android\Android Studio\jbr',
    'D:\Software\001_AndriodTools\002_DevTool\android-studio\jbr',
    'C:\Program Files\Android\Android Studio\jbr',
    "${env:ProgramFiles}\Android\Android Studio\jbr",
    "${env:LOCALAPPDATA}\Programs\Android Studio\jbr",
    $env:JAVA_HOME
) | Where-Object { $_ -and (Test-Path $_) }

$JavaHome = $JavaCandidates | Select-Object -First 1

if (-not $JavaHome) {
    Write-Host '[ERROR] JAVA_HOME not found.' -ForegroundColor Red
    Write-Host '        Please set JAVA_HOME env or update $JavaCandidates in this script.' -ForegroundColor Yellow
    exit 1
}

$JavaExe = Join-Path $JavaHome 'bin\java.exe'
if (-not (Test-Path $JavaExe)) {
    Write-Host "[ERROR] java.exe not found in $JavaHome\bin" -ForegroundColor Red
    exit 1
}

# 用 .NET Process 调用 java -version
# java -version 的输出走 stderr 是 JVM 的设计，不是错误
$javaVersionOutput = ''
$jProc = $null
try {
    $jPsi = New-Object System.Diagnostics.ProcessStartInfo
    $jPsi.FileName = $JavaExe
    $jPsi.Arguments = '-version'
    $jPsi.RedirectStandardError = $true
    $jPsi.RedirectStandardOutput = $true
    $jPsi.UseShellExecute = $false
    $jPsi.CreateNoWindow = $true
    $jProc = [System.Diagnostics.Process]::Start($jPsi)
    if (-not $jProc) { throw 'Process.Start returned null for java' }
    # 异步读取避免死锁
    $jErrTask = $jProc.StandardError.ReadToEndAsync()
    $jOutTask = $jProc.StandardOutput.ReadToEndAsync()
    $jProc.WaitForExit()
    $javaErr = $jErrTask.Result
    $javaOut = $jOutTask.Result
    $javaVersionOutput = ($javaErr -split "`n")[0].Trim()
    if (-not $javaVersionOutput) { $javaVersionOutput = ($javaOut -split "`n")[0].Trim() }
} catch {
    Write-Host "[ERROR] Failed to execute 'java -version': $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    if ($jProc) { $jProc.Dispose() }
}

Write-Host "[1/6] JAVA_HOME   = $JavaHome" -ForegroundColor Green
Write-Host "      Java version = $javaVersionOutput"

# JDK 版本检查（默认 fatal，可用 -SkipEnvCheck 跳过）
if (-not $SkipEnvCheck) {
    if ($javaVersionOutput -notmatch 'version "([0-9]+)') {
        Write-Host "[ERROR] Cannot parse Java version from: $javaVersionOutput" -ForegroundColor Red
        Write-Host '        Expected format: openjdk version "21.x.x"' -ForegroundColor Yellow
        Write-Host '        Run with -SkipEnvCheck to bypass (not recommended)' -ForegroundColor Yellow
        exit 1
    }
    $javaMajor = [int]$matches[1]
    if ($javaMajor -lt 21) {
        Write-Host "[ERROR] Java version $javaMajor is less than 21." -ForegroundColor Red
        Write-Host '        Gradle 8.14 requires JDK 21+.' -ForegroundColor Yellow
        Write-Host '        Fix: Set JAVA_HOME to Android Studio jbr (JDK 21)' -ForegroundColor Yellow
        Write-Host '        Or run with -SkipEnvCheck to bypass (not recommended)' -ForegroundColor Yellow
        exit 1
    }
}

# 设置环境变量（PATH 前置去重 + 清理冲突 JDK 路径）
$env:JAVA_HOME = $JavaHome
$env:ORG_GRADLE_JAVA_HOME = $JavaHome  # Gradle 优先使用此变量

# 清理 PATH 中所有其他 JDK 路径（避免 CMake 调用 Java 工具时找到错误的 JDK）
# 已知冲突路径：D:\Software\002_DevelopmentTool\001_Java\jdk-16.0.2\bin
$javaHomeBin = "$JavaHome\bin"
$cleanedPath = @()
foreach ($entry in ($env:PATH -split ';')) {
    # 跳过空和空白条目
    $trimmed = "$entry".Trim()
    if (-not $trimmed) { continue }
    # 跳过非目标 JDK 的 bin 路径（保留 $javaHomeBin）
    if ($trimmed -match '\\bin$' -and $trimmed -ne $javaHomeBin) {
        $javaCandidate = "$trimmed\java.exe"
        if (Test-Path -LiteralPath $javaCandidate) {
            Write-Host "      [PATH] Removing conflicting JDK: $trimmed" -ForegroundColor DarkGray
            continue
        }
    }
    $cleanedPath += $trimmed
}
# 前置 JDK 21 bin（确保优先级最高）
if ($cleanedPath -notcontains $javaHomeBin) {
    $cleanedPath = @($javaHomeBin) + $cleanedPath
}
$env:PATH = $cleanedPath -join ';'

# ============================================================
# 步骤 2/6：CMake 版本检查（AGP 8.x 只支持 CMake 3.22.1）
# ============================================================
# 错误的 CMake 版本会导致 configureCMakeRelease 任务退出码 268435659 (0x1000000B)
$localProps = Join-Path $ProjectRoot 'android\local.properties'
if (Test-Path $localProps) {
    $propsContent = Get-Content $localProps -Raw
    if ($propsContent -match 'cmake\.dir\s*=\s*(.+)') {
        # 规范化路径：properties 文件中 \\ 表示单个 \
        $cmakeDir = $matches[1].Trim().Replace('\\', '\').Replace('/', '\').TrimEnd('\')
        $cmakeExePath = Join-Path $cmakeDir 'bin\cmake.exe'
        if (Test-Path $cmakeExePath) {
            $cmakeVer = ''
            $cProc = $null
            try {
                $cPsi = New-Object System.Diagnostics.ProcessStartInfo
                $cPsi.FileName = $cmakeExePath
                $cPsi.Arguments = '--version'
                $cPsi.RedirectStandardOutput = $true
                $cPsi.RedirectStandardError = $true
                $cPsi.UseShellExecute = $false
                $cPsi.CreateNoWindow = $true
                $cProc = [System.Diagnostics.Process]::Start($cPsi)
                if (-not $cProc) { throw 'Process.Start returned null for cmake' }
                $cOutTask = $cProc.StandardOutput.ReadToEndAsync()
                $cErrTask = $cProc.StandardError.ReadToEndAsync()
                $cProc.WaitForExit()
                $cmakeOut = $cOutTask.Result
                $cmakeVer = ($cmakeOut -split "`n")[0].Trim()
            } catch {
                Write-Host "[ERROR] Failed to execute 'cmake --version': $($_.Exception.Message)" -ForegroundColor Red
                exit 1
            } finally {
                if ($cProc) { $cProc.Dispose() }
            }

            Write-Host "[2/6] CMake path    = $cmakeDir" -ForegroundColor Green
            Write-Host "      CMake version = $cmakeVer"

            if ($cmakeVer -and $cmakeVer -notmatch '3\.22\.1') {
                if ($SkipEnvCheck) {
                    Write-Host "[WARNING] CMake version is not 3.22.1 (-SkipEnvCheck, continuing)" -ForegroundColor Yellow
                } else {
                    Write-Host '[ERROR] CMake version is not 3.22.1.' -ForegroundColor Red
                    Write-Host '        AGP 8.x only supports CMake 3.22.1; other versions cause exit code 268435659.' -ForegroundColor Yellow
                    Write-Host "        Fix: sdkmanager --install 'cmake;3.22.1'" -ForegroundColor Yellow
                    Write-Host '        And update android/local.properties cmake.dir to SDK cmake/3.22.1' -ForegroundColor Yellow
                    Write-Host '        Or run with -SkipEnvCheck to bypass (not recommended)' -ForegroundColor Yellow
                    exit 1
                }
            }
        } else {
            Write-Host "[WARNING] cmake.exe not found at: $cmakeExePath" -ForegroundColor Yellow
            if (-not $SkipEnvCheck) {
                Write-Host '[ERROR] cmake.exe missing - cannot verify CMake version.' -ForegroundColor Red
                exit 1
            }
        }
    } else {
        Write-Host '[WARNING] cmake.dir not configured in local.properties' -ForegroundColor Yellow
    }
} else {
    Write-Host '[WARNING] android/local.properties not found' -ForegroundColor Yellow
}

# ============================================================
# 步骤 3/6：代理配置
# ============================================================
# 默认清理代理环境变量（代理未运行时会导致下载失败）
if ($NoProxy) {
    Remove-Item Env:HTTP_PROXY  -ErrorAction SilentlyContinue
    Remove-Item Env:HTTPS_PROXY -ErrorAction SilentlyContinue
    Remove-Item Env:GRADLE_OPTS -ErrorAction SilentlyContinue
    Write-Host '[3/6] Proxy disabled (explicit -NoProxy)' -ForegroundColor Green
} elseif ($env:DEVNOTE_PROXY) {
    $env:HTTP_PROXY  = $env:DEVNOTE_PROXY
    $env:HTTPS_PROXY = $env:DEVNOTE_PROXY
    Write-Host "[3/6] Proxy enabled: $env:DEVNOTE_PROXY" -ForegroundColor Green
} else {
    Remove-Item Env:HTTP_PROXY  -ErrorAction SilentlyContinue
    Remove-Item Env:HTTPS_PROXY -ErrorAction SilentlyContinue
    Remove-Item Env:GRADLE_OPTS -ErrorAction SilentlyContinue
    Write-Host '[3/6] Proxy cleared (default; set DEVNOTE_PROXY env to enable)' -ForegroundColor Green
}

# ============================================================
# 步骤 4/6：Flutter SDK 探测
# ============================================================
$FlutterExe = $null
$pathFlutter = (Get-Command flutter -ErrorAction SilentlyContinue).Source
if ($pathFlutter -and (Test-Path $pathFlutter)) {
    $FlutterExe = $pathFlutter
} else {
    # 退化路径：尝试常用安装位置（Pub Cache 不放 Flutter SDK）
    $flutterCandidates = @(
        'D:\Software\001_AndriodTools\002_DevTool\flutter\bin\flutter.bat',
        'C:\flutter\bin\flutter.bat',
        'C:\src\flutter\bin\flutter.bat',
        'C:\dev\flutter\bin\flutter.bat'
    )
    foreach ($c in $flutterCandidates) {
        if (Test-Path $c) { $FlutterExe = $c; break }
    }
}
if (-not $FlutterExe) {
    Write-Host '[ERROR] flutter executable not found in PATH or candidate locations.' -ForegroundColor Red
    Write-Host '        Please add flutter to PATH or update $flutterCandidates in this script.' -ForegroundColor Yellow
    exit 1
}
Write-Host "[4/6] Flutter path  = $FlutterExe" -ForegroundColor Green

# ============================================================
# 步骤 5/6：预检 Flutter 版本
# ============================================================
Write-Host ''
Write-Host '[5/6] Pre-build checks...' -ForegroundColor Green

$fvProc = $null
try {
    $fvPsi = New-Object System.Diagnostics.ProcessStartInfo
    $fvPsi.FileName = $FlutterExe
    $fvPsi.Arguments = '--version'
    $fvPsi.RedirectStandardOutput = $true
    $fvPsi.RedirectStandardError = $true
    $fvPsi.UseShellExecute = $false
    $fvPsi.CreateNoWindow = $true
    $fvProc = [System.Diagnostics.Process]::Start($fvPsi)
    if (-not $fvProc) { throw 'Process.Start returned null for flutter --version' }
    # 异步读取避免死锁
    $fvOutTask = $fvProc.StandardOutput.ReadToEndAsync()
    $fvErrTask = $fvProc.StandardError.ReadToEndAsync()
    $fvProc.WaitForExit()
    $fvStdout = $fvOutTask.Result
    $fvExitCode = $fvProc.ExitCode
    foreach ($line in ($fvStdout -split "`n")) {
        if ($line.Trim()) { Write-Host "        $line" }
    }
    if ($fvExitCode -ne 0) {
        Write-Host "[WARNING] flutter --version exited with code $fvExitCode" -ForegroundColor Yellow
    }
} catch {
    Write-Host "[ERROR] Failed to execute 'flutter --version': $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    if ($fvProc) { $fvProc.Dispose() }
}

# ============================================================
# 步骤 6a：清理（-Clean 基础清理 / -FullClean 深度清理）
# ============================================================
# -Clean       : flutter clean + 清理项目级 .cxx 缓存
# -FullClean   : flutter clean + 清理所有 .cxx 缓存（包括插件目录）
#                用于解决 CMake 缓存指纹不一致导致的 exit 268435659 错误
$DoClean = $Clean -or $FullClean
if ($DoClean) {
    Write-Host ''
    if ($FullClean) {
        Write-Host 'Full clean (deep) - removing all .cxx caches including plugins...' -ForegroundColor Yellow
    } else {
        Write-Host 'Cleaning previous build artifacts...' -ForegroundColor Yellow
    }
    $cleanProc = $null
    try {
        $cleanPsi = New-Object System.Diagnostics.ProcessStartInfo
        $cleanPsi.FileName = $FlutterExe
        $cleanPsi.Arguments = 'clean'
        $cleanPsi.UseShellExecute = $false
        $cleanPsi.RedirectStandardOutput = $false
        $cleanPsi.RedirectStandardError = $false
        $cleanPsi.CreateNoWindow = $false
        $cleanPsi.WorkingDirectory = $ProjectRoot
        $cleanProc = [System.Diagnostics.Process]::Start($cleanPsi)
        if ($cleanProc) {
            $cleanProc.WaitForExit()
            $cleanExit = $cleanProc.ExitCode
            if ($cleanExit -ne 0) {
                Write-Host "[WARNING] flutter clean exited with code $cleanExit, continuing anyway" -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Host "[WARNING] flutter clean failed: $($_.Exception.Message)" -ForegroundColor Yellow
    } finally {
        if ($cleanProc) { $cleanProc.Dispose() }
    }
    if (Test-Path '.dart_tool') {
        Remove-Item '.dart_tool' -Recurse -Force -ErrorAction SilentlyContinue
    }
    # 项目级 .cxx 缓存（-Clean 和 -FullClean 都清理）
    $cxxPaths = @('android\.cxx', 'android\app\.cxx', 'build\.cxx')
    foreach ($cxx in $cxxPaths) {
        if (Test-Path $cxx) {
            Write-Host "  Removing $cxx"
            Remove-Item $cxx -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    # -FullClean 额外清理插件目录的 .cxx 缓存
    # 这对于解决 jni 插件缓存指纹不一致导致的 configureCMakeRelWithDebInfo 失败至关重要
    if ($FullClean) {
        $pluginCxxPaths = @(
            'plugins\jni\android\.cxx',
            'plugins\*\android\.cxx'
        )
        foreach ($pattern in $pluginCxxPaths) {
            $matches = Get-Item $pattern -ErrorAction SilentlyContinue
            foreach ($m in $matches) {
                if (Test-Path $m.FullName) {
                    Write-Host "  Removing $($m.FullName)"
                    Remove-Item $m.FullName -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
        # 同时清理 build/intermediates/cxx（AGP 生成的中间产物）
        $intermediatesCxx = 'build\intermediates\cxx'
        if (Test-Path $intermediatesCxx) {
            Write-Host "  Removing $intermediatesCxx"
            Remove-Item $intermediatesCxx -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ============================================================
# 步骤 6b：执行构建
# ============================================================
$BuildArgs = @('build', 'apk')
if ($DebugBuild) {
    $BuildArgs += '--debug'
} else {
    $BuildArgs += '--release'
}

Write-Host ''
Write-Host '[6/6] Running: flutter ' -NoNewline -ForegroundColor Green
Write-Host ($BuildArgs -join ' ')
Write-Host ''

$StartTime = Get-Date

# 关键：用 System.Diagnostics.Process 直接调用 flutter
# 原因：
#   1. Start-Process 的 -NoNewWindow + -RedirectStandardOutput 会吞掉控制台实时输出
#   2. & $FlutterExe 会让 PowerShell 把 stderr 包装为 ErrorRecord，污染错误流
#   3. .NET Process 可以让 stdout/stderr 直接继承父进程控制台句柄，
#      实时显示且不被 PowerShell 解析
$BuildExitCode = $null
$buildProc = $null
try {
    $buildPsi = New-Object System.Diagnostics.ProcessStartInfo
    $buildPsi.FileName = $FlutterExe
    # 将参数数组拼接为字符串（ProcessStartInfo.Arguments 接受字符串）
    $buildPsi.Arguments = ($BuildArgs | ForEach-Object {
        if ($_ -match '\s') { "`"$_`"" } else { $_ }
    }) -join ' '
    # UseShellExecute=false + 不重定向 stdout/stderr
    # 子进程会继承父进程的控制台句柄，实时显示且退出码正确
    $buildPsi.UseShellExecute = $false
    $buildPsi.RedirectStandardOutput = $false
    $buildPsi.RedirectStandardError = $false
    $buildPsi.CreateNoWindow = $false
    $buildPsi.WorkingDirectory = $ProjectRoot

    $buildProc = [System.Diagnostics.Process]::Start($buildPsi)
    if (-not $buildProc) {
        throw "Process.Start returned null for: $FlutterExe"
    }
    $buildProc.WaitForExit()
    $BuildExitCode = $buildProc.ExitCode
} catch {
    Write-Host ''
    Write-Host '[ERROR] Failed to execute flutter build:' -ForegroundColor Red
    Write-Host "        $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host '        Check that flutter.bat is accessible and not locked by another process.' -ForegroundColor Yellow
    $BuildExitCode = -1
} finally {
    if ($buildProc) { $buildProc.Dispose() }
}

$Elapsed = (Get-Date) - $StartTime
$ElapsedStr = '{0}m {1}s' -f [int]$Elapsed.TotalMinutes, [int]$Elapsed.Seconds

# ============================================================
# 结果汇总
# ============================================================
Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
if ($BuildExitCode -eq 0) {
    $ApkPath = Join-Path $ProjectRoot 'build\app\outputs\flutter-apk\app-release.apk'
    if ($DebugBuild) {
        $ApkPath = Join-Path $ProjectRoot 'build\app\outputs\flutter-apk\app-debug.apk'
    }

    if (Test-Path $ApkPath) {
        $ApkInfo = Get-Item $ApkPath
        $SizeMB = [math]::Round($ApkInfo.Length / 1MB, 2)
        Write-Host '  BUILD SUCCESS' -ForegroundColor Green
        Write-Host '============================================================' -ForegroundColor Cyan
        Write-Host "  APK Path   : $($ApkInfo.FullName)"
        Write-Host ("  APK Size   : {0} MB ({1} bytes)" -f $SizeMB, $ApkInfo.Length)
        Write-Host "  Build Time : $ElapsedStr"
        Write-Host "  Built At   : $($ApkInfo.LastWriteTime)"
        Write-Host '============================================================' -ForegroundColor Cyan
    } else {
        Write-Host '  BUILD SUCCESS but APK file not found at expected location.' -ForegroundColor Yellow
        Write-Host "  Expected: $ApkPath" -ForegroundColor Yellow
        Write-Host '  This may happen if build output was redirected to a different path.' -ForegroundColor Yellow
    }
} else {
    Write-Host '  BUILD FAILED' -ForegroundColor Red
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host "  Exit Code  : $BuildExitCode"
    Write-Host "  Elapsed    : $ElapsedStr"
    Write-Host ''
    Write-Host '  Common causes:' -ForegroundColor Yellow
    Write-Host '    * Proxy not running (set DEVNOTE_PROXY env or use -NoProxy)'
    Write-Host '    * Android SDK licenses not accepted (run: flutter doctor --android-licenses)'
    Write-Host '    * CMake path incorrect in android/local.properties (must be 3.22.1)'
    Write-Host '    * JDK version mismatch (expected JDK 21 from Android Studio jbr)'
    Write-Host '    * CMake cache stale (run with -Clean to clear .cxx directory)'
    Write-Host '============================================================' -ForegroundColor Cyan
}

# 退出码（防御性：null 时返回 1 而非 0）
$finalExitCode = if ($null -eq $BuildExitCode) { 1 } else { [int]$BuildExitCode }
exit $finalExitCode

} finally {
    # 恢复调用者的工作目录
    Pop-Location -ErrorAction SilentlyContinue
}
