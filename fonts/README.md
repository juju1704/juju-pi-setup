# fonts/ — JetBrains Mono 1.0.2

Font terminal đi kèm repo này để cài máy mới nhanh (không phải nội dung setup của `pi`).

| | |
|---|---|
| Font | JetBrains Mono **1.0.2** (đọc từ name table trong TTF) |
| Nguồn | <https://github.com/JetBrains/JetBrainsMono> · <https://www.jetbrains.com/lp/mono/> |
| License | **SIL Open Font License 1.1** — xem [`LICENSE.txt`](./LICENSE.txt) |
| Nerd-patched? | **Không** — xem cảnh báo bên dưới |

## Có gì

8 weight, mỗi weight 4 định dạng (32 file):

- **`ttf/`** (1.0 MB) — `Regular` · `Medium` · `Italic` · `Medium-Italic` · `Bold` · `Bold-Italic` · `ExtraBold` · `ExtraBold-Italic`. Đây là phần dùng cho terminal.
- **`web/`** (2.0 MB) — cùng 8 weight ở dạng `woff2`, `woff`, `eot`, chỉ cần khi nhúng font vào web. **Xoá được** nếu bạn chỉ muốn font cho terminal (tiết kiệm 2 MB).

## Cài (macOS)

```bash
# cách 1: mở bằng Font Book
open fonts/JetBrainsMono-1.0.2/ttf/*.ttf

# cách 2: copy thẳng vào thư mục font của user
cp fonts/JetBrainsMono-1.0.2/ttf/*.ttf ~/Library/Fonts/
```

Rồi chọn `JetBrains Mono` trong profile của terminal (iTerm2 / Ghostty / Terminal.app).

## Cài (Windows)

Cách nhanh nhất: bôi đen toàn bộ `.ttf` trong `fonts/JetBrainsMono-1.0.2/ttf/` → chuột phải → **Install** (chỉ user hiện tại, không cần admin).

Hoặc bằng dòng lệnh (user-scope — copy file **và** đăng ký registry, thiếu registry thì app không thấy font):

```powershell
$src = ".\fonts\JetBrainsMono-1.0.2\ttf"
$dst = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
New-Item -ItemType Directory -Force $dst | Out-Null
Get-ChildItem "$src\*.ttf" | ForEach-Object {
  Copy-Item $_.FullName $dst -Force
  $name = [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -replace '-', ' '
  New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts" `
    -Name "$name (TrueType)" -Value "$dst\$($_.Name)" -PropertyType String -Force | Out-Null
}
```

Rồi chọn `JetBrains Mono` trong profile của terminal (Windows Terminal, WezTerm, …). Kiểm tra đã cài chưa:

```powershell
reg query "HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts" | findstr /i jetbrains
```

## ⚠️ Không phải Nerd Font

Đây là **JetBrains Mono gốc**, không có icon patch. Config statusline trong repo này (`config/extensions/pi-footer.json`) dùng `"iconMode": "nerd"` → **11/11 icon** là codepoint Private Use Area của Nerd Fonts (`U+F07C` cwd, `U+F06A9` model, `U+F0208` thinking, `U+F035B` context-bar, `U+F04CE` cache-hit-rate, `U+F13AB` total-time, `U+E725` git-branch, `U+E702` git-diff, `U+F04A3` cost, `U+F01BC` cache_ttl, `U+EAF3` tps), **không codepoint nào có trong JetBrains Mono gốc**.

Khi thiếu glyph, terminal **không** để trống ô: nó fallback sang font khác có codepoint đó, nên icon hiện ra thành **hình vô nghĩa** — trên Windows thường thấy kim cương ◆, ngôi sao ✦ hoặc dấu `?` (máy có nhiều font map dải PUA, ví dụ font VNI cho tiếng Việt). Đây **không phải** lỗi config `pi-footer`.

**Sửa — chọn 1:**

**1) Cài Nerd Font rồi trỏ terminal vào đó** (giữ icon đẹp). Bắt buộc chọn bản **Mono** (single-width): bản non-Mono vẽ icon rộng 2 ô → lệch cột trong TUI.

```bash
# macOS
brew install --cask font-jetbrains-mono-nerd-font     # hoặc font-dank-mono-nerd-font
```

Windows: tải `.otf`/`.ttf` (bản **Mono**) từ <https://www.nerdfonts.com/font-downloads> rồi Install như mục [Cài (Windows)](#cài-windows), sau đó đặt font trong profile terminal:

```json
"profiles": {
  "defaults": {
    "font": { "face": "DankMono Nerd Font Mono", "size": 12 }
  }
}
```

> Windows Terminal: `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json`. Đặt ở `profiles.defaults` để áp cho mọi profile — nhưng profile nào đã có `font` riêng thì **ghi đè** defaults, nên phải sửa cả profile đó.

**2) Không muốn cài font patch:** đổi `iconMode` sang `emoji` (dùng 📁… — trên Windows render bằng Segoe UI Emoji, không cần font patch) hoặc `text` (chữ thuần). Đổi lại: icon to hơn, statusline kém gọn.

Xem thêm bảng đối chiếu font ↔ codepoint trong [`../README.vi.md`](../README.vi.md#font-terminal-bắt-buộc-nerd-font).

## License

Font được phân phối theo **OFL-1.1** (xem [`LICENSE.txt`](./LICENSE.txt)):

- được dùng, sửa, nhúng, phân phối lại kèm license này;
- **không** được bán font như một sản phẩm độc lập;
- bản sửa đổi không được dùng Reserved Font Name (tên "JetBrains Mono") nếu chưa có phép bằng văn bản.

License gốc của JetBrains Mono không có trong thư mục tải về này, nên `LICENSE.txt` được thêm vào đây để việc phân phối lại hợp lệ.
