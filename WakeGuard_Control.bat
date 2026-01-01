@echo off
setlocal EnableDelayedExpansion
title WakeGuard 控制台
cd /d "%~dp0"

:: ==========================================
:: 1. 自动获取管理员权限
:: ==========================================
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo.
    echo   正在请求管理员权限...
    goto UACPrompt
) else ( goto gotAdmin )

:UACPrompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "%~s0", "", "", "runas", 1 >> "%temp%\getadmin.vbs"
    "%temp%\getadmin.vbs"
    exit /b

:gotAdmin
    if exist "%temp%\getadmin.vbs" ( del "%temp%\getadmin.vbs" )
    pushd "%CD%"
    CD /D "%~dp0"

:: ==========================================
:: 2. 检查核心文件
:: ==========================================
if not exist "WakeGuard.ps1" (
    cls
    echo.
    echo [错误] 找不到 WakeGuard.ps1 文件！
    echo.
    echo 请确保本脚本与 WakeGuard.ps1 位于同一文件夹内。
    echo.
    pause
    exit
)

:: ==========================================
:: 3. 主菜单
:: ==========================================
:Menu
cls
echo =================================================
echo           WakeGuard USB 唤醒管理器
echo =================================================
echo.
echo    [1] 安装 / 启动服务 (Install)
echo    [2] 卸载 / 恢复默认 (Uninstall)
echo.
echo    [3] 查看运行日志 (View Logs)
echo    [4] 检查当前唤醒列表 (Check Status)
echo.
echo =================================================
set /p choice=请输入选项数字 [1-4]: 

if "%choice%"=="1" goto Install
if "%choice%"=="2" goto Uninstall
if "%choice%"=="3" goto ViewLog
if "%choice%"=="4" goto CheckStatus
goto Menu

:: ==========================================
:: 功能区
:: ==========================================

:Install
cls
echo 正在调用 PowerShell 进行安装...
powershell -NoProfile -ExecutionPolicy Bypass -File "WakeGuard.ps1" -Action Install
echo.
echo 按任意键返回主菜单...
pause >nul
goto Menu

:Uninstall
cls
echo 正在调用 PowerShell 进行卸载...
powershell -NoProfile -ExecutionPolicy Bypass -File "WakeGuard.ps1" -Action Uninstall
echo.
echo 按任意键返回主菜单...
pause >nul
goto Menu

:ViewLog
cls
echo =================================================
echo             最新日志预览 (最后 20 行)
echo =================================================
echo.
if exist "C:\ProgramData\WakeGuard\WakeGuard.log" (
    powershell -Command "Get-Content 'C:\ProgramData\WakeGuard\WakeGuard.log' -Tail 20"
    echo.
    echo =================================================
    echo.
    echo 正在打开记事本...
    "%SystemRoot%\system32\notepad.exe" "C:\ProgramData\WakeGuard\WakeGuard.log"
) else (
    echo [提示] 暂无日志文件。
    echo 服务可能未安装，或刚刚启动尚未产生日志。
)
echo.
echo 按任意键返回主菜单...
pause >nul
goto Menu

:CheckStatus
cls
echo ==========================================
echo 当前允许唤醒系统的设备 (wake_armed):
echo ==========================================
powercfg /devicequery wake_armed
echo.
echo ------------------------------------------
echo 正常状态说明:
echo 1. 列表中应该只有网卡 (Ethernet/Wi-Fi)。
echo 2. 如果看到鼠标/键盘，请等待 5 秒再次刷新，
echo    服务会自动将其移除。
echo ==========================================
echo.
echo 按任意键返回主菜单...
pause >nul
goto Menu