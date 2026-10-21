# Migrate setup pi sang máy mới

Snapshot của một Linux headless dev server (pi `1.3.0`, Node `24`). Mục tiêu: dựng lại
**toàn bộ 27 extension + config** mà không copy cache, secret hay state theo máy.

## Chạy nhanh

```bash
npm i -g @earendil-works/pi-coding-agent
git clone https://github.com/juju1704/juju-pi-setup.git && cd juju-pi-setup
./scripts/pi-setup-restore.sh --from-config config --scratch --install --verify  # diễn tập
./scripts/pi-setup-restore.sh --install --verify                                 # thật
```

Rồi login lại provider (`auth.json` không nằm trong repo):

```bash
pi auth check --provider opencode-go
# trong pi: /login cho từng provider
```

## Copy gì / không copy gì

| Mục | Copy? | Ghi chú |
|---|---|---|
| `settings.json` | ✅ | manifest packages → pi tự cài lại |
| `APPEND_SYSTEM.md` | ✅ | system prompt bổ sung |
| `models-store.json` | ✅ | đỡ chờ refresh catalog model |
| `advisor.json` | ✅ | config pi-advisor-flow (gốc config dir) |
| `advisor-pi-preferences/` | ✅ | prefs của advisor-pi (footer `advisor:` là của nó) |
| `model-fallback/config.json` | ✅ | chỉ config, không lấy `state.json` (state theo máy) |
| `extensions/` | ✅ | extension local viết tay + statusline config |
| `~/.pi-lens/config.json` | ✅ | qua `external-configs.txt` (ngoài config dir) |
| `auth.json` | ❌ | credential → `/login` lại |
| `npm/` | ❌ | ~300 MB, pi tự cài |
| `sessions/`, `missions/` | ❌ | lịch sử/state (opt-in `--sessions`/`--missions`) |
| `memory/`, `skills/` | ❌ | state theo máy (opt-in `--memory`/`--skills`) |
| `extensions/orca-*.ts`, `agentkit-*/`, `devin/` | ❌ | Orca/AgentKit/Devin host tự sinh lại |
| `~/.unipi/config/notify/config.json` | ❌ | chứa token Gotify/Telegram → set lại bằng `/unipi:notify-*` |
| `~/.multix/.env` | ❌ | credential pi-multix → tạo lại |

## Sau restore — checklist

1. `pi auth check --provider <từng provider>` + `/login`.
2. `npm i -g @tobilu/qmd` nếu dùng `pi-memory` semantic search.
3. `/unipi:notify-set-gotify`, `/unipi:notify-set-tg`, `/unipi:notify-settings` nếu cần notify.
4. Tạo `~/.multix/.env` nếu dùng `pi-multix`.
5. Terminal trỏ **Nerd Font Mono** (statusline `iconMode: "nerd"`) — hoặc đổi
   `iconMode` sang `emoji`/`text` trong `extensions/pi-footer.json`.
6. Sau mỗi `pi update`: `node scripts/pi-setup-patch-extensions.mjs` (vá stale-ctx
   của pi-footer; goal-x 0.32.x đã fix upstream nên script tự nhận diện).
7. Headless server: `pi-browser-use` + `pi-computer-use` **không** nằm trong manifest —
   duyệt web dùng `pi-smart-fetch`/`pi-web-access`. Muốn browser tool thật: cài
   `google-chrome-stable` rồi thêm lại `npm:pi-browser-use` vào `settings.json`.

## Troubleshooting

| Triệu chứng | Nguyên nhân | Cách sửa |
|---|---|---|
| `pi` không tồn tại | pi cài global **theo version Node**; đổi nvm/fnm mất lệnh | `npm i -g @earendil-works/pi-coding-agent` lại |
| `builtin:mcp` extension issue | built-in `mcp` và `pi-mcp-adapter` cùng đăng ký `/mcp` | `settings.json` đã có `"extensions": ["-builtin:mcp"]` — đừng xoá |
| Extension issue về peerDependencies của pi-smart-fetch | package khai báo host dep trong `dependencies` (upstream bug, đã vá local) | vá lại sau `npm reinstall`: chuyển `@earendil-works/pi-tui`, `@sinclair/typebox` sang `peerDependencies: "*"` |
| `/reload` giết pi với "extension ctx is stale" | pi-footer chưa vá | `node scripts/pi-setup-patch-extensions.mjs` |
| Icon statusline thành ◆/✦/`?` | terminal không dùng Nerd Font | cài Nerd Font **Mono** hoặc đổi `iconMode` |
| Footer `advisor:` không đổi khi sửa `advisor.json` | đó là prefs của **advisor-pi**, file khác | sửa `advisor-pi-preferences/model.json` + `thinkingLevel.json` |
| `advisor.json` warning "unrecognized keys" | key sai chính tả bị nuốt lặng | `node scripts/pi-setup-verify-advisor.mjs --live` |
| Warning PILENS_CFG_0003/0001 trong repo | file config trùng basename reserved của pi-lens | đừng đặt `pi-lens.json`/`pi-lsp.json`/`.pi-lens.json` trong config/ |

## Xác minh (đo trên máy này, 2026-10-21)

| Check | Kết quả |
|---|---|
| Scratch restore `--install --verify` | ✅ 27/27, cài 90s, module dirs 0 → 291 |
| Bundle `backups/pi-setup-portable.tar.gz` | ✅ 13 file, không devin/orca/agentkit, sha256 `447498b7…` |
| Secret scan | ✅ sạch |
| `--config-dir` mirror + `.pi-setup-exclude` | ✅ loại 93 file |
