@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

rem ===== 可选：预设服务列表（留空则自动扫描）=====
rem 格式：目录名|服务名|镜像|端口，用 ; 分隔
set "PRESET_SERVICES="
rem 示例：
rem set "PRESET_SERVICES=plaindoc|plaindoc|lifei6671/plaindoc:latest|8080:8080"
rem set "PRESET_SERVICES=!PRESET_SERVICES!;nginx|nginx|nginx:alpine|80:80"

:MENU
cls
echo ============================================
echo   Docker 目录管理
echo ============================================
echo   1. 初始化 / 同步全部服务
echo   2. 新增单个服务
echo   3. 生成总控 compose.yaml (include)
echo   0. 退出
echo ============================================
set "CHOICE="
set /p "CHOICE=请选择 [1/2/3/0]（默认 0）: "
if "!CHOICE!"=="" set "CHOICE=0"

if "!CHOICE!"=="1" goto SYNC_ALL
if "!CHOICE!"=="2" goto ADD_ONE
if "!CHOICE!"=="3" goto GEN_ROOT_ONLY
if "!CHOICE!"=="0" goto END
goto MENU

rem ============================================================
rem  模式一：初始化 / 同步全部服务
rem ============================================================
:SYNC_ALL
echo.
echo ==^> 同步全部服务

if not "!PRESET_SERVICES!"=="" (
    rem 用预设列表
    for %%S in ("!PRESET_SERVICES:;=" "!") do (
        for /f "tokens=1-4 delims=|" %%A in (%%S) do (
            call :CREATE_SERVICE "%%A" "%%B" "%%C" "%%D"
        )
    )
) else (
    rem 自动扫描：只补目录和 .env，不覆盖已有 compose.yaml
    call :SCAN_SERVICES
    if not "!SCAN_LIST!"=="" (
        for %%D in (!SCAN_LIST!) do (
            set "SDIR=%%D"
            if not exist "!SDIR!\data"    mkdir "!SDIR!\data"
            if not exist "!SDIR!\uploads" mkdir "!SDIR!\uploads"
            echo   目录已就绪: !SDIR!\
            if not exist "!SDIR!\.env" (
                call :WRITE_ENV "!SDIR!" "!SDIR!"
                echo   已生成 !SDIR!\.env
            ) else (
                echo   跳过 !SDIR!\.env（已存在）
            )
        )
    ) else (
        echo   未发现任何子服务。
    )
)

call :GEN_ROOT_COMPOSE
call :GEN_ROOT_ENV
goto DONE

rem ============================================================
rem  模式二：新增单个服务
rem ============================================================
:ADD_ONE
echo.
set /p "DIR=服务目录名（如 minio）: "
if "!DIR!"=="" (
    echo   目录名不能为空，已取消。
    goto DONE
)
set /p "NAME=服务名（回车默认与目录名相同）: "
if "!NAME!"=="" set "NAME=!DIR!"
set /p "IMAGE=镜像（如 minio/minio:latest）: "
if "!IMAGE!"=="" (
    echo   镜像不能为空，已取消。
    goto DONE
)
set /p "PORT=端口映射（如 9000:9000）: "
if "!PORT!"=="" (
    echo   端口不能为空，已取消。
    goto DONE
)

call :CREATE_SERVICE "!DIR!" "!NAME!" "!IMAGE!" "!PORT!"

rem 追加到总控 include（若尚不存在）
if exist "compose.yaml" (
    findstr /c:"!DIR!/compose.yaml" compose.yaml >nul 2>&1
    if errorlevel 1 (
        echo   - !DIR!/compose.yaml>> compose.yaml
        echo   已追加到总控 compose.yaml
    ) else (
        echo   总控 compose.yaml 已包含该服务，跳过
    )
) else (
    echo   总控 compose.yaml 不存在，正在生成...
    call :GEN_ROOT_COMPOSE
)
goto DONE

rem ============================================================
rem  模式三：只生成总控 compose.yaml
rem ============================================================
:GEN_ROOT_ONLY
echo.
call :GEN_ROOT_COMPOSE
goto DONE

rem ============================================================
rem  子过程：扫描所有含 compose.yaml 的子目录
rem  结果存入 SCAN_LIST，空格分隔
rem ============================================================
:SCAN_SERVICES
set "SCAN_LIST="
set "SCAN_COUNT=0"
for /d %%D in (*) do (
    if exist "%%D\compose.yaml" (
        set /a SCAN_COUNT+=1
        set "SCAN_LIST=!SCAN_LIST! %%D"
    )
)
exit /b 0

rem ============================================================
rem  子过程：创建一个服务目录及文件（存在则询问，默认否）
rem  参数：%1=目录名 %2=服务名 %3=镜像 %4=端口
rem ============================================================
:CREATE_SERVICE
set "S_DIR=%~1"
set "S_NAME=%~2"
set "S_IMAGE=%~3"
set "S_PORT=%~4"

echo.
echo --- 服务: !S_DIR! ---

if not exist "!S_DIR!\data"    mkdir "!S_DIR!\data"
if not exist "!S_DIR!\uploads" mkdir "!S_DIR!\uploads"
echo   目录已就绪: !S_DIR!\

rem ---- compose.yaml ----
if exist "!S_DIR!\compose.yaml" (
    call :CONFIRM "!S_DIR!\compose.yaml 已存在，是否覆盖？"
    if "!CONFIRM_RESULT!"=="1" (
        call :WRITE_COMPOSE "!S_DIR!" "!S_NAME!" "!S_IMAGE!" "!S_PORT!"
        echo   已覆盖 compose.yaml
    ) else (
        echo   跳过 compose.yaml（保留原文件）
    )
) else (
    call :WRITE_COMPOSE "!S_DIR!" "!S_NAME!" "!S_IMAGE!" "!S_PORT!"
    echo   已生成 compose.yaml
)

rem ---- .env ----
if exist "!S_DIR!\.env" (
    call :CONFIRM "!S_DIR!\.env 已存在，是否覆盖？"
    if "!CONFIRM_RESULT!"=="1" (
        call :WRITE_ENV "!S_DIR!" "!S_NAME!"
        echo   已覆盖 .env
    ) else (
        echo   跳过 .env（保留原文件）
    )
) else (
    call :WRITE_ENV "!S_DIR!" "!S_NAME!"
    echo   已生成 .env
)
exit /b 0

rem ============================================================
rem  子过程：写入 compose.yaml
rem ============================================================
:WRITE_COMPOSE
(
    echo services:
    echo   %~2:
    echo     image: %~3
    echo     container_name: %~2
    echo     ports:
    echo       - "%~4"
    echo     env_file:
    echo       - .env
    echo     volumes:
    echo       - ./data:/app/data
    echo       - ./uploads:/app/uploads
    echo     restart: unless-stopped
) > "%~1\compose.yaml"
exit /b 0

rem ============================================================
rem  子过程：写入 .env
rem ============================================================
:WRITE_ENV
(
    echo # %~2 服务配置
    echo APP_ENV=production
) > "%~1\.env"
exit /b 0

rem ============================================================
rem  子过程：生成总控 compose.yaml（自动扫描 include）
rem ============================================================
:GEN_ROOT_COMPOSE
echo.
echo ==^> 生成总控 compose.yaml
if exist "compose.yaml" (
    call :CONFIRM "总控 compose.yaml 已存在，是否覆盖？"
    if "!CONFIRM_RESULT!"=="1" (
        call :WRITE_ROOT_COMPOSE
        echo   已覆盖总控 compose.yaml
    ) else (
        echo   跳过总控 compose.yaml（保留原文件）
    )
) else (
    call :WRITE_ROOT_COMPOSE
    echo   已生成总控 compose.yaml
)
exit /b 0

:WRITE_ROOT_COMPOSE
(
    echo name: mydocker
    echo.
    echo include:
) > compose.yaml

call :SCAN_SERVICES
if "!SCAN_COUNT!"=="0" (
    echo   # 未发现任何子服务>> compose.yaml
) else (
    for %%D in (!SCAN_LIST!) do (
        echo   - %%D/compose.yaml>> compose.yaml
    )
)
exit /b 0

rem ============================================================
rem  子过程：生成根目录 .env（初始化时用）
rem ============================================================
:GEN_ROOT_ENV
echo.
echo ==^> 生成根目录 .env
if exist ".env" (
    call :CONFIRM "根目录 .env 已存在，是否覆盖？"
    if "!CONFIRM_RESULT!"=="1" (
        call :WRITE_ROOT_ENV
        echo   已覆盖根目录 .env
    ) else (
        echo   跳过根目录 .env（保留原文件）
    )
) else (
    call :WRITE_ROOT_ENV
    echo   已生成根目录 .env
)
exit /b 0

:WRITE_ROOT_ENV
(
    echo # 公共变量（仅用于总控变量替换）
    echo COMPOSE_PROJECT_NAME=mydocker
) > .env
exit /b 0

rem ============================================================
rem  子过程：确认提示，默认否
rem  返回：CONFIRM_RESULT=1（是） / 0（否）
rem ============================================================
:CONFIRM
set "CONFIRM_RESULT=0"
set "ANS="
set /p "ANS=%~1 [y/N]: "
if /i "!ANS!"=="y" set "CONFIRM_RESULT=1"
if /i "!ANS!"=="yes" set "CONFIRM_RESULT=1"
exit /b 0

rem ============================================================
rem  任务完成：显示结果，等待按键后回主菜单
rem ============================================================
:DONE
echo.
echo ==^> 完成。
echo.
echo ==^> 当前目录结构：
dir /b /ad 2>nul
echo.
echo ==^> 总控 compose.yaml 内容：
if exist "compose.yaml" (
    type compose.yaml
) else (
    echo   (未生成)
)
echo.
echo 按任意键返回主菜单...
pause >nul
goto MENU

rem ============================================================
rem  真正退出
rem ============================================================
:END
endlocal
exit /b 0