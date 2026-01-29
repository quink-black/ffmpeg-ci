@echo off
setlocal enabledelayedexpansion

REM FFmpeg Windows MSVC 构建脚本
REM 用法: build.bat [release|debug]

set BUILD_TYPE=%1
if "%BUILD_TYPE%"=="" set BUILD_TYPE=release

echo ============================================
echo FFmpeg Windows MSVC Build
echo ============================================

REM 查找 Visual Studio
set "VS_PATH="
for %%v in (2022 2019) do (
    for %%e in (Professional Enterprise Community) do (
        if exist "C:\Program Files\Microsoft Visual Studio\%%v\%%e\VC\Auxiliary\Build\vcvars64.bat" (
            set "VS_PATH=C:\Program Files\Microsoft Visual Studio\%%v\%%e"
            goto :found_vs
        )
    )
)
:found_vs

if "%VS_PATH%"=="" (
    echo Error: Visual Studio not found
    exit /b 1
)

echo Using Visual Studio: %VS_PATH%

REM 加载 VS 环境
call "%VS_PATH%\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1

REM 验证cl.exe可用
where cl.exe >nul 2>&1
if errorlevel 1 (
    echo Error: cl.exe not found in PATH
    exit /b 1
)
echo cl.exe found: OK

REM 使用 -use-full-path 让 MSYS2 继承当前环境变量
echo Starting MSYS2 build...
C:\msys64\msys2_shell.cmd -msys2 -defterm -no-start -use-full-path -here -c "./build.sh %BUILD_TYPE%"

endlocal