#!/bin/bash

# Some logics of this script are copied from [scripts/build_kernel]. Thanks to UtsavBalar1231.

set -e
set -o pipefail

# Bắt đầu đếm giờ ngay khi chạy
SCRIPT_START_TIME=$(date +%s)

# --- CÁC HÀM MÀU SẮC CHO ĐẸP MẮT ---
GREEN='\033[1;32m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m' # No Color

TOOLCHAIN_PATH=$HOME/zyc-clang/bin
GIT_COMMIT_ID=$(git rev-parse --short=8 HEAD)
TARGET_DEVICE=$1
SCRIPT_DIR=$(pwd)
dts_source=arch/arm64/boot/dts/vendor/qcom

# Kernel local version string (UTC+7, ~23 chars — well under 64-char limit)
local_version_str="-perf"
local_version_date_str="-Rezzchan-$(TZ='Asia/Ho_Chi_Minh' date +%Y%m%d)-$(TZ='Asia/Ho_Chi_Minh' date +%H%M)-${GIT_COMMIT_ID}-perf++"

# --- CẤU HÌNH TELEGRAM BOT TỪ .ENV ---
ENV_FILE=".env"
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

echo -e "${GREEN}⚙️ Kiểm tra cấu hình Telegram Bot...${NC}"

if [ -z "$TG_TOKEN" ] && [ "$GITHUB_ACTIONS" != "true" ]; then
    read -t 30 -p "$(echo -e ${YELLOW}"Nhập Token Telegram Bot (Đợi 30s hoặc Enter để bỏ qua): "${NC})" input_token
    if [ -n "$input_token" ]; then
        TG_TOKEN="$input_token"
        echo "TG_TOKEN=\"$TG_TOKEN\"" >> "$ENV_FILE"
    else
        echo -e "\n${YELLOW}Bỏ qua nhập Token.${NC}"
    fi
fi

if [ -n "$TG_TOKEN" ] && [ -z "$TG_CHAT_ID" ] && [ "$GITHUB_ACTIONS" != "true" ]; then
    read -t 30 -p "$(echo -e ${YELLOW}"Nhập Telegram Chat ID của bạn (Đợi 30s để bỏ qua): "${NC})" input_id
    if [ -n "$input_id" ]; then
        TG_CHAT_ID="$input_id"
        echo "TG_CHAT_ID=\"$TG_CHAT_ID\"" >> "$ENV_FILE"
    fi
fi

# Các hàm Telegram
send_telegram_msg() {
    local text="$1"
    if [ "$USE_TELEGRAM" = true ]; then
        curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
            -d "chat_id=${TG_CHAT_ID}" \
            -d "parse_mode=Markdown" \
            -d "text=${text}" > /dev/null || true
    fi
}

send_start_msg_with_button() {
    local text="$1"
    if [ "$USE_TELEGRAM" = true ]; then
        local json_payload=$(cat <<EOF
{
    "chat_id": "$TG_CHAT_ID",
    "text": "$text",
    "parse_mode": "Markdown",
    "reply_markup": {
        "inline_keyboard": [[
            {"text": "❌ Hủy Build Nhanh", "callback_data": "cancel_build"}
        ]]
    }
}
EOF
)
        local res=$(curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
            -H "Content-Type: application/json" \
            -d "$json_payload")
        TG_MSG_ID=$(echo "$res" | grep -o '"message_id":[0-9]*' | head -n1 | cut -d':' -f2)
        export TG_MSG_ID
    fi
}

MAIN_PID=$$
POLLER_PID=""
start_telegram_poller() {
    if [ "$USE_TELEGRAM" = true ]; then
        (
            last_update_id=""
            res=$(curl -s "https://api.telegram.org/bot${TG_TOKEN}/getUpdates?offset=-1")
            if echo "$res" | grep -q '"update_id":'; then
                last_update_id=$(echo "$res" | grep -o '"update_id":[0-9]*' | cut -d':' -f2 | tail -n1)
            fi

            while true; do
                if [ -n "$last_update_id" ]; then
                    offset=$((last_update_id + 1))
                    res=$(curl -s "https://api.telegram.org/bot${TG_TOKEN}/getUpdates?timeout=5&offset=$offset")
                else
                    res=$(curl -s "https://api.telegram.org/bot${TG_TOKEN}/getUpdates?timeout=5")
                fi
                
                if echo "$res" | grep -q '"update_id":'; then
                    last_update_id=$(echo "$res" | grep -o '"update_id":[0-9]*' | cut -d':' -f2 | tail -n1)
                    if echo "$res" | grep -q '"callback_data":"cancel_build"'; then
                        curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
                            -d chat_id="$TG_CHAT_ID" \
                            -d text="🛑 *Lệnh HỦY đã được kích hoạt! Đang buộc dừng hệ thống...*" \
                            -d parse_mode="Markdown" > /dev/null
                        
                        kill -TERM $MAIN_PID
                        break
                    fi
                fi
                sleep 5
            done
        ) &
        POLLER_PID=$!
    fi
}

# ── Cleanup trap: always restore DTS and defconfig on exit (success or error) ──
cleanup() {
    local exit_code=$?
    
    # Telegram error handling
    [ -n "$POLLER_PID" ] && kill $POLLER_PID 2>/dev/null || true
    if [ $exit_code -ne 0 ]; then
        local CRASH_TIME=$(( $(date +%s) - SCRIPT_START_TIME ))
        local FORMATTED_CRASH_TIME=$(printf "%02d:%02d:%02d" $((CRASH_TIME/3600)) $(((CRASH_TIME%3600)/60)) $((CRASH_TIME%60)))

        if [ $exit_code -eq 143 ]; then
            echo -e "\n${RED}🛑 Tiến trình đã bị hủy do yêu cầu từ Telegram! (Sau $FORMATTED_CRASH_TIME)${NC}"
        else
            echo -e "\n${RED}❌ Quá trình build bị sập (Mã lỗi: $exit_code). Đã gửi báo cáo về Telegram!${NC}"
            local ERR_MSG="❌ *CẢNH BÁO LỖI BUILD KERNEL!* ❌\n\n▪️ *Dự án:* \`${TARGET_DEVICE:-Không rõ}\`\n▪️ *Thời gian chạy trước khi lỗi:* \`${FORMATTED_CRASH_TIME}\`\n▪️ *Mã lỗi (Exit Code):* \`${exit_code}\`\n\n🛑 _Vui lòng kiểm tra lại terminal._"
            local err_json="{\"chat_id\": \"$TG_CHAT_ID\", \"text\": \"$ERR_MSG\", \"parse_mode\": \"Markdown\"}"
            curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" -H "Content-Type: application/json" -d "$err_json" > /dev/null || true
        fi
    fi

    cd "$SCRIPT_DIR"
    if [ -d ".dts.bak" ]; then
        echo "Restoring DTS..."
        rm -rf "${dts_source}"
        mv .dts.bak "${dts_source}"
    fi
}
trap cleanup EXIT

if [ -n "$TG_TOKEN" ] && [ -n "$TG_CHAT_ID" ]; then
    echo -e "${GREEN}✅ Telegram Bot đã sẵn sàng!${NC}"
    USE_TELEGRAM=true
else
    echo -e "${YELLOW}⚠️ Bỏ qua Telegram.${NC}"
    USE_TELEGRAM=false
fi

# ── Argument checks ───────────────────────────────────────────────────────────

if [ -z "$1" ]; then
    echo "Error: No argument provided, please specify a target device."
    echo "If you need KernelSU, please add [ksu] as the second arg."
    echo "Examples:"
    echo "  Build for lmi (K30 Pro/POCO F2 Pro) without KernelSU:"
    echo "      bash build.sh lmi"
    echo "  Build for umi (Mi10) with KernelSU:"
    echo "      bash build.sh umi ksu"
    exit 1
fi

if [ ! -d "$TOOLCHAIN_PATH" ]; then
    echo "TOOLCHAIN_PATH [$TOOLCHAIN_PATH] does not exist."
    echo "Please ensure the toolchain is there, or change TOOLCHAIN_PATH in the script."
    exit 1
fi

echo "TOOLCHAIN_PATH: [$TOOLCHAIN_PATH]"
export PATH="$TOOLCHAIN_PATH:$PATH"

if ! command -v aarch64-linux-gnu-ld >/dev/null 2>&1; then
    echo "[aarch64-linux-gnu-ld] not found, please check your environment."
    exit 1
fi
if ! command -v arm-linux-gnueabi-ld >/dev/null 2>&1; then
    echo "[arm-linux-gnueabi-ld] not found, please check your environment."
    exit 1
fi
if ! command -v clang >/dev/null 2>&1; then
    echo "[clang] not found, please check your environment."
    exit 1
fi

# ── ccache (fixed: use with clang, not gcc) ───────────────────────────────────
export CCACHE_DIR="$HOME/.cache/ccache_mikernel"
echo "CCACHE_DIR: [$CCACHE_DIR]"

# ── make arguments ────────────────────────────────────────────────────────────
MAKE_ARGS=(
    ARCH=arm64
    SUBARCH=arm64
    O=out
    CC="ccache clang"
    CROSS_COMPILE=aarch64-linux-gnu-
    CROSS_COMPILE_ARM32=arm-linux-gnueabi-
    CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
    CLANG_TRIPLE=aarch64-linux-gnu-
    HOSTCC="/usr/bin/clang -B/usr/bin"
    HOSTCXX="/usr/bin/clang++ -B/usr/bin"
    HOSTLD="/usr/bin/ld.lld -B/usr/bin"
    HOSTLDFLAGS="-fuse-ld=lld"
)

# ── Special build modes ───────────────────────────────────────────────────────
if [ "$1" == "j1" ]; then
    make "${MAKE_ARGS[@]}" -j1
    exit
fi

if [ "$1" == "continue" ]; then
    make "${MAKE_ARGS[@]}" -j"$(nproc)"
    exit
fi

if [ ! -f "arch/arm64/configs/${TARGET_DEVICE}_defconfig" ]; then
    echo "No target device [${TARGET_DEVICE}] found."
    echo "Available defconfigs:"
    ls arch/arm64/configs/*_defconfig
    exit 1
fi

echo "[clang --version]:"
clang --version

# ── KernelSU ──────────────────────────────────────────────────────────────────
KSU_ZIP_STR=NoKernelSU
if [ "$2" == "ksu" ]; then
    KSU_ENABLE=1
    KSU_ZIP_STR=KittiSU
else
    KSU_ENABLE=0
fi

echo "TARGET_DEVICE: $TARGET_DEVICE"

# GỬI TIN NHẮN BẮT ĐẦU
START_MSG="🚀 *Bắt đầu Build Kernel MIUI* 🚀\n\n"
START_MSG="${START_MSG}▪️ *Device:* \`${TARGET_DEVICE}\`\n"
START_MSG="${START_MSG}▪️ *Variant:* \`${KSU_ZIP_STR}\`\n"
START_MSG="${START_MSG}▪️ *Toolchain:* \`ZYC-Clang\`"
    send_start_msg_with_button "$START_MSG"
    start_telegram_poller

if [ $KSU_ENABLE -eq 1 ]; then
    echo "KSU is enabled"
    rm -rf KernelSU
    KSU_SETUP_SCRIPT=$(mktemp)
    curl -LSs "https://raw.githubusercontent.com/terebiko/KittiSU/main/kernel/setup.sh" \
        -o "$KSU_SETUP_SCRIPT"
    bash "$KSU_SETUP_SCRIPT" main
    rm -f "$KSU_SETUP_SCRIPT"

    # [FIX] Bypass lỗi TP hooks không tương thích Non-GKI (kernel 4.19)
    echo "Patching KSU Kbuild to bypass TP hooks check for Non-GKI..."
    sed -i 's/\$(error TP hooks are incompatible with Non-GKI/\$(warning TP hooks are incompatible with Non-GKI/g' drivers/kernelsu/Kbuild 2>/dev/null || true
    
    # [FIX] Bypass inline hook checks since the kernel has old hooks but we use inline hooking
    echo "Patching KSU inline_hook_check.mk to bypass incompatible hook error..."
    sed -i 's/\$\$(error/\$\$(warning/g' KernelSU/kernel/tools/inline_hook_check.mk 2>/dev/null || true
    
    # [FIX] Fix undeclared identifier 'CMD_SUSFS_HIDE_SUS_MNTS_FOR_NON_SU_PROCS' and related missing functions
    echo "Patching KSU dispatch.c for old SuSFS compatibility..."
    sed -i 's/CMD_SUSFS_HIDE_SUS_MNTS_FOR_NON_SU_PROCS/CMD_SUSFS_HIDE_SUS_MNTS_FOR_ALL_PROCS/g' KernelSU/kernel/supercall/dispatch.c 2>/dev/null || true
    sed -i 's/susfs_set_hide_sus_mnts_for_non_su_procs/susfs_set_hide_sus_mnts_for_all_procs/g' KernelSU/kernel/supercall/dispatch.c 2>/dev/null || true
    sed -i '/susfs_start_sdcard_monitor_fn/d' KernelSU/kernel/supercall/dispatch.c 2>/dev/null || true
    sed -i '/susfs_extra_works/d' KernelSU/kernel/feature/kernel_umount.c 2>/dev/null || true
    echo "Bypassed."
else
    echo "KSU is disabled"
fi

# ── Prep ──────────────────────────────────────────────────────────────────────
echo "Cleaning..."
rm -rf out/ anykernel/

echo "Cloning AnyKernel3 (repo: https://github.com/liyafe1997/AnyKernel3)"
git clone https://github.com/liyafe1997/AnyKernel3 -b kona --single-branch --depth=1 anykernel
sed -i 's/device.name5=lmi/device.name5=lmi\ndevice.name6=thyme/g' anykernel/anykernel.sh

# No longer patching defconfig with sed. Will use scripts/config instead.

# ── Building for MIUI ─────────────────────────────────────────────────────────
echo "Cleaning [out/] and building for MIUI..."
rm -rf out/

# Backup DTS before patching
cp -a "${dts_source}" .dts.bak

# Correct panel dimensions on MIUI builds
sed -i 's/<154>/<1537>/g' ${dts_source}/dsi-panel-j1s*
sed -i 's/<154>/<1537>/g' ${dts_source}/dsi-panel-j2*
sed -i 's/<155>/<1544>/g' ${dts_source}/dsi-panel-j3s-37-02-0a-dsc-video.dtsi
sed -i 's/<155>/<1545>/g' ${dts_source}/dsi-panel-j11-38-08-0a-fhd-cmd.dtsi
sed -i 's/<155>/<1546>/g' ${dts_source}/dsi-panel-k11a-38-08-0a-dsc-cmd.dtsi
sed -i 's/<155>/<1546>/g' ${dts_source}/dsi-panel-l11r-38-08-0a-dsc-cmd.dtsi
sed -i 's/<70>/<695>/g' ${dts_source}/dsi-panel-j11-38-08-0a-fhd-cmd.dtsi
sed -i 's/<70>/<695>/g' ${dts_source}/dsi-panel-j3s-37-02-0a-dsc-video.dtsi
sed -i 's/<70>/<695>/g' ${dts_source}/dsi-panel-k11a-38-08-0a-dsc-cmd.dtsi
sed -i 's/<70>/<695>/g' ${dts_source}/dsi-panel-l11r-38-08-0a-dsc-cmd.dtsi
sed -i 's/<71>/<710>/g' ${dts_source}/dsi-panel-j1s*
sed -i 's/<71>/<710>/g' ${dts_source}/dsi-panel-j2*

# Enable back mi smartfps while disabling qsync min refresh-rate
sed -i 's/\/\/ mi,mdss-dsi-pan-enable-smart-fps/mi,mdss-dsi-pan-enable-smart-fps/g' ${dts_source}/dsi-panel*
sed -i 's/\/\/ mi,mdss-dsi-smart-fps-max_framerate/mi,mdss-dsi-smart-fps-max_framerate/g' ${dts_source}/dsi-panel*
sed -i 's/\/\/ qcom,mdss-dsi-pan-enable-smart-fps/qcom,mdss-dsi-pan-enable-smart-fps/g' ${dts_source}/dsi-panel*
sed -i 's/qcom,mdss-dsi-qsync-min-refresh-rate/\/\/qcom,mdss-dsi-qsync-min-refresh-rate/g' ${dts_source}/dsi-panel*

# Enable back refresh rates supported on MIUI
sed -i 's/120 90 60/120 90 60 50 30/g' ${dts_source}/dsi-panel-g7a-36-02-0c-dsc-video.dtsi
sed -i 's/120 90 60/120 90 60 50 30/g' ${dts_source}/dsi-panel-g7a-37-02-0a-dsc-video.dtsi
sed -i 's/120 90 60/120 90 60 50 30/g' ${dts_source}/dsi-panel-g7a-37-02-0b-dsc-video.dtsi
sed -i 's/144 120 90 60/144 120 90 60 50 48 30/g' ${dts_source}/dsi-panel-j3s-37-02-0a-dsc-video.dtsi

# Enable back brightness control from dtsi
sed -i 's/\/\/39 00 00 00 00 00 03 51 03 FF/39 00 00 00 00 00 03 51 03 FF/g' ${dts_source}/dsi-panel-j9-38-0a-0a-fhd-video.dtsi
sed -i 's/\/\/39 00 00 00 00 00 03 51 0D FF/39 00 00 00 00 00 03 51 0D FF/g' ${dts_source}/dsi-panel-j2-p2-1-38-0c-0a-dsc-cmd.dtsi
sed -i 's/\/\/39 00 00 00 00 00 05 51 0F 8F 00 00/39 00 00 00 00 00 05 51 0F 8F 00 00/g' ${dts_source}/dsi-panel-j1s-42-02-0a-dsc-cmd.dtsi
sed -i 's/\/\/39 00 00 00 00 00 05 51 0F 8F 00 00/39 00 00 00 00 00 05 51 0F 8F 00 00/g' ${dts_source}/dsi-panel-j1s-42-02-0a-mp-dsc-cmd.dtsi
sed -i 's/\/\/39 00 00 00 00 00 05 51 0F 8F 00 00/39 00 00 00 00 00 05 51 0F 8F 00 00/g' ${dts_source}/dsi-panel-j2-mp-42-02-0b-dsc-cmd.dtsi
sed -i 's/\/\/39 00 00 00 00 00 05 51 0F 8F 00 00/39 00 00 00 00 00 05 51 0F 8F 00 00/g' ${dts_source}/dsi-panel-j2-p2-1-42-02-0b-dsc-cmd.dtsi
sed -i 's/\/\/39 00 00 00 00 00 05 51 0F 8F 00 00/39 00 00 00 00 00 05 51 0F 8F 00 00/g' ${dts_source}/dsi-panel-j2s-mp-42-02-0a-dsc-cmd.dtsi
sed -i 's/\/\/39 01 00 00 00 00 03 51 00 00/39 01 00 00 00 00 03 51 00 00/g' ${dts_source}/dsi-panel-j2-38-0c-0a-dsc-cmd.dtsi
sed -i 's/\/\/39 01 00 00 00 00 03 51 03 FF/39 01 00 00 00 00 03 51 03 FF/g' ${dts_source}/dsi-panel-j11-38-08-0a-fhd-cmd.dtsi
sed -i 's/\/\/39 01 00 00 00 00 03 51 03 FF/39 01 00 00 00 00 03 51 03 FF/g' ${dts_source}/dsi-panel-j9-38-0a-0a-fhd-video.dtsi
sed -i 's/\/\/39 01 00 00 00 00 03 51 07 FF/39 01 00 00 00 00 03 51 07 FF/g' ${dts_source}/dsi-panel-j1u-42-02-0b-dsc-cmd.dtsi
sed -i 's/\/\/39 01 00 00 00 00 03 51 07 FF/39 01 00 00 00 00 03 51 07 FF/g' ${dts_source}/dsi-panel-j2-42-02-0b-dsc-cmd.dtsi
sed -i 's/\/\/39 01 00 00 00 00 03 51 07 FF/39 01 00 00 00 00 03 51 07 FF/g' ${dts_source}/dsi-panel-j2-p1-42-02-0b-dsc-cmd.dtsi
sed -i 's/\/\/39 01 00 00 00 00 03 51 0F FF/39 01 00 00 00 00 03 51 0F FF/g' ${dts_source}/dsi-panel-j1u-42-02-0b-dsc-cmd.dtsi
sed -i 's/\/\/39 01 00 00 00 00 03 51 0F FF/39 01 00 00 00 00 03 51 0F FF/g' ${dts_source}/dsi-panel-j2-42-02-0b-dsc-cmd.dtsi
sed -i 's/\/\/39 01 00 00 00 00 03 51 0F FF/39 01 00 00 00 00 03 51 0F FF/g' ${dts_source}/dsi-panel-j2-p1-42-02-0b-dsc-cmd.dtsi
sed -i 's/\/\/39 01 00 00 05 51 07 FF 00 00/39 01 00 00 05 51 07 FF 00 00/g' ${dts_source}/dsi-panel-j1s-42-02-0a-dsc-cmd.dtsi
sed -i 's/\/\/39 01 00 00 05 51 07 FF 00 00/39 01 00 00 05 51 07 FF 00 00/g' ${dts_source}/dsi-panel-j1s-42-02-0a-mp-dsc-cmd.dtsi
sed -i 's/\/\/39 01 00 00 05 51 07 FF 00 00/39 01 00 00 05 51 07 FF 00 00/g' ${dts_source}/dsi-panel-j2-mp-42-02-0b-dsc-cmd.dtsi
sed -i 's/\/\/39 01 00 00 05 51 07 FF 00 00/39 01 00 00 05 51 07 FF 00 00/g' ${dts_source}/dsi-panel-j2-p2-1-42-02-0b-dsc-cmd.dtsi
sed -i 's/\/\/39 01 00 00 05 51 07 FF 00 00/39 01 00 00 05 51 07 FF 00 00/g' ${dts_source}/dsi-panel-j2s-mp-42-02-0a-dsc-cmd.dtsi
sed -i 's/\/\/39 01 00 00 01 00 03 51 03 FF/39 01 00 00 01 00 03 51 03 FF/g' ${dts_source}/dsi-panel-j11-38-08-0a-fhd-cmd.dtsi
sed -i 's/\/\/39 01 00 00 11 00 03 51 03 FF/39 01 00 00 11 00 03 51 03 FF/g' ${dts_source}/dsi-panel-j2-p2-1-38-0c-0a-dsc-cmd.dtsi

make "${MAKE_ARGS[@]}" "${TARGET_DEVICE}_defconfig"

echo "Setting LOCALVERSION in out/.config..."
scripts/config --file out/.config --set-str LOCALVERSION "$local_version_date_str"

if [ $KSU_ENABLE -eq 1 ]; then
    scripts/config --file out/.config \
        -e KSU \
        -d KSU_SUSFS \
        -d KSU_SUSFS_SUS_PATH \
        -d KSU_SUSFS_SUS_MOUNT \
        -d KSU_SUSFS_SUS_KSTAT \
        -d KSU_SUSFS_SPOOF_UNAME \
        -d KSU_SUSFS_ENABLE_LOG \
        -d KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS \
        -d KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG \
        -d KSU_SUSFS_OPEN_REDIRECT \
        -d KSU_SUSFS_SUS_MAP \
        -e THREAD_INFO_IN_TASK \
        -e KPM
else
    scripts/config --file out/.config -d KSU
fi

scripts/config --file out/.config \
    --set-str STATIC_USERMODEHELPER_PATH /system/bin/micd \
    -e PERF_CRITICAL_RT_TASK \
    -e SF_BINDER \
    -e OVERLAY_FS \
    -d DEBUG_FS \
    -e MIGT \
    -e MIGT_ENERGY_MODEL \
    -e MIHW \
    -e PACKAGE_RUNTIME_INFO \
    -e BINDER_OPT \
    -e KPERFEVENTS \
    -e MILLET \
    -e PERF_HUMANTASK \
    -d LTO_CLANG \
    -d LOCALVERSION_AUTO \
    -e SF_BINDER \
    -e XIAOMI_MIUI \
    -d MI_MEMORY_SYSFS \
    -e TASK_DELAY_ACCT \
    -e MIUI_ZRAM_MEMORY_TRACKING \
    -d CONFIG_MODULE_SIG_SHA512 \
    -d CONFIG_MODULE_SIG_HASH \
    -e MI_FRAGMENTION \
    -e PERF_HELPER \
    -e BOOTUP_RECLAIM \
    -e MI_RECLAIM \
    -e RTMM

make "${MAKE_ARGS[@]}" -j"$(nproc)"

if [ -f "out/arch/arm64/boot/Image" ]; then
    echo "The file [out/arch/arm64/boot/Image] exists. MIUI Build successful."
else
    echo "The file [out/arch/arm64/boot/Image] does not exist. MIUI build failed."
    exit 1
fi

echo "Generating [out/arch/arm64/boot/dtb]..."
find out/arch/arm64/boot/dts -name '*.dtb' -exec cat {} + > out/arch/arm64/boot/dtb

# Restore DTS now (cleanup trap handles failures earlier in the build)
rm -rf "${dts_source}"
mv .dts.bak "${dts_source}"

rm -rf anykernel/kernels/
mkdir -p anykernel/kernels/

cp out/arch/arm64/boot/Image anykernel/kernels/
cp out/arch/arm64/boot/dtb anykernel/kernels/

echo "Build for MIUI finished."

# --- BÁO CÁO THÀNH CÔNG ---
END_TIME=$(date +%s)
ELAPSED_SECS=$((END_TIME - SCRIPT_START_TIME))
FORMATTED_TIME=$(printf "%02d:%02d:%02d" $((ELAPSED_SECS/3600)) $(((ELAPSED_SECS%3600)/60)) $((ELAPSED_SECS%60)))

# ── Packaging ─────────────────────────────────────────────────────────────────
cd anykernel

ZIP_FILENAME=Kernel_MIUI_${TARGET_DEVICE}_${KSU_ZIP_STR}_${GIT_COMMIT_ID}_$(TZ='Asia/Ho_Chi_Minh' date +'%Y%m%d_%H%M%S')_anykernel3.zip

zip -r9 "$ZIP_FILENAME" . \
    -x "*.git*" \
    -x ".gitignore" \
    -x "out/*" \
    -x "*.zip"

mv "$ZIP_FILENAME" ../

cd ..

echo "Done. The flashable zip is: [./$ZIP_FILENAME]"

# ── Building for AOSP ─────────────────────────────────────────────────────────
echo "Cleaning [out/] and building for AOSP..."
rm -rf out/

make "${MAKE_ARGS[@]}" "${TARGET_DEVICE}_defconfig"

echo "Setting LOCALVERSION in out/.config..."
scripts/config --file out/.config --set-str LOCALVERSION "$local_version_date_str"

if [ $KSU_ENABLE -eq 1 ]; then
    scripts/config --file out/.config \
        -e KSU \
        -d KSU_SUSFS \
        -d KSU_SUSFS_SUS_PATH \
        -d KSU_SUSFS_SUS_MOUNT \
        -d KSU_SUSFS_SUS_KSTAT \
        -d KSU_SUSFS_SPOOF_UNAME \
        -d KSU_SUSFS_ENABLE_LOG \
        -d KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS \
        -d KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG \
        -d KSU_SUSFS_OPEN_REDIRECT \
        -d KSU_SUSFS_SUS_MAP \
        -e THREAD_INFO_IN_TASK \
        -e KPM
else
    scripts/config --file out/.config -d KSU
fi

make "${MAKE_ARGS[@]}" -j"$(nproc)"

if [ -f "out/arch/arm64/boot/Image" ]; then
    echo "The file [out/arch/arm64/boot/Image] exists. AOSP Build successful."
else
    echo "The file [out/arch/arm64/boot/Image] does not exist. AOSP build failed."
    exit 1
fi

echo "Generating [out/arch/arm64/boot/dtb]..."
find out/arch/arm64/boot/dts -name '*.dtb' -exec cat {} + > out/arch/arm64/boot/dtb

rm -rf anykernel/kernels/
mkdir -p anykernel/kernels/

# Patch for KittiSU KPM support. 
if [ $KSU_ENABLE -eq 1 ]; then
    cd out/arch/arm64/boot/
    wget -q https://github.com/SukiSU-Ultra/SukiSU_KernelPatch_patch/releases/download/0.12.2/patch_linux
    chmod +x patch_linux
    ./patch_linux
    rm Image
    mv oImage Image
    cd -
fi

cp out/arch/arm64/boot/Image anykernel/kernels/
cp out/arch/arm64/boot/dtb anykernel/kernels/

echo "Build for AOSP finished."

# ── Packaging AOSP ────────────────────────────────────────────────────────────
cd anykernel

AOSP_ZIP_FILENAME=Kernel_AOSP_${TARGET_DEVICE}_${KSU_ZIP_STR}_${GIT_COMMIT_ID}_$(TZ='Asia/Ho_Chi_Minh' date +'%Y%m%d_%H%M%S')_anykernel3.zip

zip -r9 "$AOSP_ZIP_FILENAME" . \
    -x "*.git*" \
    -x ".gitignore" \
    -x "out/*" \
    -x "*.zip"

mv "$AOSP_ZIP_FILENAME" ../

cd ..

echo "Done. The flashable zip for AOSP is: [./$AOSP_ZIP_FILENAME]"

# --- BÁO CÁO THÀNH CÔNG TỔNG ---
END_TIME=$(date +%s)
ELAPSED_SECS=$((END_TIME - SCRIPT_START_TIME))
FORMATTED_TIME=$(printf "%02d:%02d:%02d" $((ELAPSED_SECS/3600)) $(((ELAPSED_SECS%3600)/60)) $((ELAPSED_SECS%60)))

echo -e "${GREEN}⏱ Tổng thời gian chạy: ${FORMATTED_TIME}${NC}"

FINISH_MSG="🎉 *Đã build xong Kernel (MIUI & AOSP)!* 🥂%0A%0A"
FINISH_MSG="${FINISH_MSG}▪️ *Device:* \`${TARGET_DEVICE}\`%0A"
FINISH_MSG="${FINISH_MSG}▪️ *Variant:* \`${KSU_ZIP_STR}\`%0A"
FINISH_MSG="${FINISH_MSG}⏱ *Thời gian:* \`${FORMATTED_TIME}\`%0A"
FINISH_MSG="${FINISH_MSG}📁 *MIUI ZIP:* \`${ZIP_FILENAME}\`%0A"
FINISH_MSG="${FINISH_MSG}📁 *AOSP ZIP:* \`${AOSP_ZIP_FILENAME}\`"

send_telegram_msg "$FINISH_MSG"

# Tắt tiến trình theo dõi Telegram
[ -n "$POLLER_PID" ] && kill $POLLER_PID 2>/dev/null || true
