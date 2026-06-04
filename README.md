# <h1 style="color: red; font-size: 4em;">I USE ANTIGRAVITY</h1>

# Kernel Xiaomi SM8250 của ApartTUSITU

## Mục lục
- [Giới thiệu](#giới-thiệu)
- [Tính năng](#tính-năng)
- [Lưu ý quan trọng](#lưu-ý-quan-trọng)
- [Cộng đồng](#cộng-đồng)
- [Các thiết bị hỗ trợ](#các-thiết-bị-hỗ-trợ)
- [Tính năng khác](#tính-năng-khác)
- [Hướng dẫn Build](#hướng-dẫn-build)
  - [Build nhanh qua GitHub Actions](#build-nhanh-qua-github-actions)
  - [Build thủ công](#build-thủ-công)

---

## Giới thiệu
Kho lưu trữ này được phát triển dựa trên [Mã nguồn Kernel Xiaomi SM8250 của Starwing](https://github.com/liyafe1997/kernel_xiaomi_sm8250_mod).
Nếu bạn muốn tìm hiểu thêm về [vấn đề pin bị kẹt ở mức 1%](https://github.com/liyafe1997/Xiaomi-fix-battery-one-percent), vui lòng xem kho lưu trữ ở trên để biết thêm chi tiết.

---

## Tính năng
Kernel này hỗ trợ [SukiSU Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra) (một nhánh tùy biến của KernelSU có hỗ trợ KPM) & [SUSFS](https://github.com/sidex15/susfs4ksu-module).
Vui lòng tự cài đặt [Trình quản lý SukiSU Ultra](https://github.com/ShirkNeko/SukiSU-Ultra/releases) và flash module SUSFS nếu bạn cần.
Phiên bản NoKernelSU (không có KSU) hỗ trợ dùng chung với Magisk và APatch.

Các bản Kernel được build sẵn trong phần **Release** được biên dịch từ nhánh `android16-aptusitu`, và có thể hoạt động tốt trên các bản ROM MIUI/HyperOS gốc cũng như các ROM tùy biến dựa trên AOSP từ Android 11 đến 16.
Rất mong nhận được phản hồi từ các bạn (thông qua việc mở Issue hoặc Pull Requests)! Người dùng Coolapk có thể tham gia thảo luận tại [bài viết này](https://www.coolapk.com/feed/67088487), hoặc nhắn tin trực tiếp cho tôi để góp ý.

---

## Lưu ý quan trọng
**Lưu ý**: File zip Kernel này **không** chứa `dtbo.img` và sẽ không tự flash phân vùng dtbo của bạn.
Chúng tôi khuyến nghị sử dụng `dtbo` gốc của máy, hoặc lấy từ các file đi kèm của bản ROM tùy biến mà bạn đang dùng (nếu tác giả ROM xác nhận là nó hoạt động tốt).
Nguyên nhân là do file `dtbo.img` được build từ mã nguồn này có một số vấn đề — ví dụ: ở màn hình khóa, màn hình có thể đột ngột chớp sáng lên mức tối đa khi cố gắng tắt màn hình.
Nếu bạn đã từng flash các kernel bên thứ 3 khác hoặc gặp phải các vấn đề lạ, hãy kiểm tra xem phân vùng `dtbo` của bạn đã bị thay thế hay chưa.

**CẢNH BÁO**: Nếu bạn đang dùng HyperOS hoặc MIUI, vui lòng flash bản **Kernel dành cho MIUI**.
Phiên bản Kernel dành cho AOSP có trình điều khiển màn hình (display drivers) khác, điều này sẽ khiến màn hình không thể hiển thị bình thường trên HyperOS/MIUI.
Nếu bạn gặp tình trạng màn hình đen sau khi flash, hãy kiểm tra xem bạn có đang dùng HyperOS/MIUI nhưng lại vô tình flash nhầm bản AOSP hay không.
Những báo cáo lỗi liên quan đến vấn đề này sẽ mặc định bị từ chối hỗ trợ.

---

## Cộng đồng
Chào mừng bạn gia nhập nhóm QQ của Starwing: **459094061**

---

## Các thiết bị hỗ trợ
| Mã thiết bị | Tên thiết bị |
|-------------|--------------|
| psyche      | Xiaomi 12X |
| umi         | Xiaomi 10 |
| munch       | Redmi K40S |
| lmi         | Redmi K30 Pro / POCO F2 Pro |
| cmi         | Xiaomi 10 Pro |
| cas         | Xiaomi 10 Ultra |
| apollo      | Xiaomi 10T / Redmi K30S Ultra |
| alioth      | Xiaomi 11X / POCO F3 / Redmi K40 |
| elish       | Xiaomi Pad 5 Pro |
| enuma       | Xiaomi Pad 5 Pro 5G |
| dagu        | Xiaomi Pad 5 Pro 12.4 |
| pipa        | Xiaomi Pad 6 |

---

## Tính năng khác
1. Hỗ trợ driver cổng COM / USB Serial (CH340 / FTDI / PL2303 / OTI6858 / TI / SPCP8X5 / QT2 / UPD78F0730 / CP210X).
2. Hỗ trợ phân vùng EROFS.
3. Bật tính năng realtime discard cho F2FS giúp TRIM bộ nhớ flash tốt hơn.
4. Hỗ trợ các bộ chuyển đổi CANBus và USB CAN (ví dụ: CANable).
5. Tính năng zRAM hỗ trợ các thuật toán nén LZ4, LZ4HC, và ZSTD.
6. Cập nhật ngược (Backport) BPF từ Linux 5.10.

---

## Hướng dẫn Build

### Build nhanh qua GitHub Actions
1. Fork kho lưu trữ này về tài khoản của bạn (và đừng quên thả 1 sao Star~ nhé).
2. Truy cập vào tab **Actions**.
3. Nếu bạn muốn biên dịch Kernel cho tất cả các thiết bị được hỗ trợ, hãy tìm workflow `Build All Devices Kernel (Matrix Parallel)` và nhấn `Run workflow`.
4. Nếu bạn chỉ muốn biên dịch Kernel cho một thiết bị duy nhất, hãy tìm workflow `Build Kernel`, nhấn `Run workflow` và chọn các tùy chọn tương ứng.

---

### Build thủ công
1. Chuẩn bị môi trường build:
   Bạn cần có `git`, `make`, `curl`, `bison`, `flex`, `zip`, v.v.
   - Trên Debian/Ubuntu:
   ```bash
   sudo apt install build-essential git curl wget bison flex zip bc cpio libssl-dev ccache
   ```
   Bạn cũng cần cài đặt `python` (chỉ có `python3` là chưa đủ):
   ```bash
   sudo apt install python-is-python3
   ```

   - Trên RHEL/RPM:
   ```bash
   sudo yum groupinstall 'Development Tools'
   sudo yum install wget bc openssl-devel ccache
   ```

   *Lưu ý*: Script `build.sh` có bật sẵn tính năng `ccache` (lưu tại `$HOME/.cache/ccache_mikernel`). Bạn có thể xóa hoặc sửa tùy ý.

2. Tải bộ công cụ [ZyC-Clang v15](https://github.com/ZyCromerZ/Clang/releases/tag/15.0.7-20251111-release):
   ```bash
   mkdir zyc-clang
   cd zyc-clang
   wget https://github.com/ZyCromerZ/Clang/releases/download/15.0.7-20251111-release/Clang-15.0.7-20251111.tar.gz
   tar -zxvf Clang-15.0.7-20251111.tar.gz
   cd ..
   ```

3. Bắt đầu Build:
   - Build **KHÔNG** dùng KernelSU:
     ```bash
     bash build.sh TARGET_DEVICE
     ```
   - Build **CÓ** dùng KernelSU:
     ```bash
     bash build.sh TARGET_DEVICE ksu
     ```

   Ví dụ:
   - Cho mã lmi (Redmi K30 Pro/POCO F2 Pro) KHÔNG dùng KernelSU:
     ```bash
     bash build.sh lmi
     ```
   - Cho mã umi (Xiaomi 10) CÓ dùng KernelSU:
     ```bash
     bash build.sh umi ksu
     ```

   Ngoài ra, script `buildall.sh` có thể build cho toàn bộ các thiết bị cùng một lúc.
