<div align="center">

# juju-pi-setup

**Snapshot portable của setup [`pi`](https://github.com/earendil-works/pi) coding-agent — clone là dựng lại đủ 27 extension trên máy khác.**

pi `1.3.0` · Node `24` · Linux headless server · updated 2026-10-21

Fork/ý tưởng từ [mrgoonie/zuey-pi-setup](https://github.com/mrgoonie/zuey-pi-setup).

</div>

---

## Vì sao có repo này

`pi` không có config export/import. Repo này là cách **deterministic** mang **toàn bộ setup** sang máy khác mà không copy cache:

- `~/.pi/agent/npm/` (~300 MB) — **không cần**, pi tự `npm install` lại từ `settings.json`
- `~/.pi/agent/auth.json` — **không commit** (API key + OAuth token), login lại ở máy mới
- `~/.pi/agent/sessions/` và `missions/` — **không commit** (lịch sử/state, có thể chứa dữ liệu nội bộ)

Cơ chế: `settings.json` có mảng `packages`; pi đọc lúc khởi động và `npm install` những gì còn thiếu. Mang được manifest là mang được cả bộ extension.

---

## Quickstart (máy mới)

```bash
# 1) cài pi
npm i -g @earendil-works/pi-coding-agent

# 2) clone
git clone https://github.com/juju1704/juju-pi-setup.git
cd juju-pi-setup

# 3) diễn tập an toàn vào thư mục tạm (không đụng config thật)
./scripts/pi-setup-restore.sh --from-config config --scratch --install --verify

# 4) bản thật
./scripts/pi-setup-restore.sh --install --verify
```

Sau đó login lại các provider (auth không nằm trong repo):

```bash
pi auth check --provider opencode-go   # và /login trong pi cho từng provider
```

> **Headless server:** snapshot này chạy trên Linux server không GUI. `pi-browser-use`
> và `@injaneity/pi-computer-use` **đã bị gỡ** khỏi manifest (cần Chrome/desktop) —
> duyệt web dùng `pi-smart-fetch` + `pi-web-access` thay thế.

Chi tiết đầy đủ: **[`docs/pi-setup-migration.md`](./docs/pi-setup-migration.md)**.

---

## Repo chứa gì

```text
juju-pi-setup/
├── README.md                        ← bạn đang đọc
├── docs/
│   └── pi-setup-migration.md        hướng dẫn chi tiết + troubleshooting
├── fonts/                           JetBrains Mono 1.0.2 (font terminal, OFL-1.1)
├── scripts/
│   ├── pi-setup-backup.sh           đóng gói setup của máy hiện tại
│   ├── pi-setup-restore.sh          dựng lại setup trên máy mới
│   ├── pi-setup-verify-advisor.mjs  validate advisor.json theo schema thật của pi-advisor-flow
│   ├── pi-lens-compact-lsp-status.mjs  vá bundle pi-lens để status LSP gọn (xem ghi chú)
│   └── pi-setup-patch-extensions.mjs   vá stale-ctx crash của pi-footer + pi-goal-x
├── backups/
│   └── pi-setup-portable.tar.gz     bundle sẵn sàng tải (đã lọc)
└── config/                          snapshot setup (plain file, git-diff được)
    ├── .pi-setup-exclude            glob loại trừ — backup tôn trọng file này
    ├── settings.json                manifest 27 packages + model/theme/compaction
    ├── advisor.json                 config pi-advisor-flow (ở gốc config dir)
    ├── advisor-pi-preferences/      prefs của advisor-pi (model + thinking level)
    ├── pi-lens-config.json          config pi-lens — nằm ở ~/.pi-lens/, NGOÀI config dir
    ├── external-configs.txt         manifest: file nào đi về đâu khi restore
    ├── APPEND_SYSTEM.md             system prompt bổ sung
    ├── models-store.json            catalog model (đỡ phải chờ refresh)
    ├── model-fallback/
    │   └── config.json              rule của pi-model-fallback
    └── extensions/                  extension viết tay, không có trên npm
        ├── compaction-policy.ts     trigger compaction duy nhất của setup
        ├── pi-footer-cache-tps.ts   đẩy cache-TTL + tốc độ token (t/s) vào pi-footer
        └── pi-footer.json           layout statusline (gồm context bar)
```

`config/` là **mirror** của phần setup trong `~/.pi/agent`. Mọi thứ khác (cache, secret, lịch sử) đều không đưa vào.

### Không nằm trong repo (do tool khác sinh, tự cài lại được)

| Loại trừ | Sinh bởi | Vì sao |
|---|---|---|
| `extensions/orca-*.ts` (3 file) | Orca (`@orca-managed-pi-extension`) | glue tích hợp Orca; Orca tự sinh khi quản pi |
| `extensions/agentkit-*/` | AgentKit (`ak`) | hook đã sinh + cache chứa **path tuyệt đối**; `ak` tự cài lại |
| `extensions/devin/` | host Devin/ACP | provider extension do host quản lý |
| `missions/`, `memory/`, `skills/` | pi / AgentKit | state theo máy, không phải setup |
| `~/.pi/agent/agents/`, `rules/` | AgentKit | tự cài lại khi `ak` chạy |

### `.pi-setup-exclude`

`scripts/pi-setup-backup.sh --config-dir config` đọc file này (mỗi dòng 1 glob, `#` là comment) và xoá mọi file khớp sau khi mirror — nên chạy backup lại bao nhiêu lần cũng không kéo `orca-*`/`agentkit-*`/`devin/` vào repo:

```bash
./scripts/pi-setup-backup.sh --config-dir config   # → "loại trừ: 93 file khớp .pi-setup-exclude"
```

Ngoài các family đã sinh, file này còn bỏ `advisor-outcomes.jsonl`, `advisor-outcomes-salt` (log advisor theo máy) và `extensions/*.bak*` (backup của chính các script vá).

Cùng file này cũng dùng được cho **tarball** qua `--exclude-file`:

```bash
./scripts/pi-setup-backup.sh -o backups/pi-setup-portable.tar.gz \
  --exclude-file config/.pi-setup-exclude
```

### Config không backup được: `@pi-unipi/notify`

`~/.unipi/config/notify/config.json` chứa **token Gotify** và **botToken + chatId Telegram** → cố ý KHÔNG nằm trong `EXTERNAL_CONFIGS`; commit là lộ credential. Thiết lập lại trên máy mới:

```bash
/unipi:notify-set-gotify     # cấu hình server Gotify
/unipi:notify-set-tg         # cấu hình bot Telegram
/unipi:notify-settings       # phần còn lại
```

`pi-multix` cũng giữ credential ngoài config dir (`~/.multix/.env`) — cố ý không backup. Tạo lại trên máy mới.

### Config nằm ngoài config dir

Vài extension giữ config **ngoài** `~/.pi/agent/` → không gom được theo path tương đối. Script có danh sách riêng:

```bash
# trong scripts/pi-setup-backup.sh
EXTERNAL_CONFIGS=(
	"~/.pi-lens/config.json:pi-lens-config.json"
)
```

- Backup copy mỗi file tồn tại vào artifact dưới `<name>` (`pi-lens-config.json`), cộng **`external-configs.txt`** — manifest `<name>=<đường dẫn dạng ~>`.
- Restore đọc manifest và đặt file về đúng chỗ (`mkdir -p`, snapshot file cũ thành `*.bak.<timestamp>`).
- Manifest dùng `~` thay `/home/...` → artifact không lộ path máy.
- Thêm config ngoài khác = thêm 1 dòng vào `EXTERNAL_CONFIGS`; restore không cần sửa.

> ⚠️ **Tên artifact không được trùng basename config của pi-lens:** `pi-lens.json`,
> `pi-lsp.json`, `.pi-lens.json`. pi-lens walk ngược lên từ **mọi** thư mục nó resolve
> config và khớp **đúng basename** → artifact tên `config/pi-lens.json` bị đọc như
> project config deprecated → warning PILENS_CFG mỗi session trong repo. Đặt tên
> `pi-lens-config.json` là vì vậy; script có guard `pi_lens_reserved_name` cảnh báo
> nếu tên cũ quay lại.

---

## 27 extension trong snapshot

| # | Package | Chức năng |
|---|---|---|
| 1 | `pi-web-access` | web search, fetch URL, clone repo GitHub, đọc PDF, hiểu YouTube + video local |
| 2 | `pi-mcp-adapter` | MCP adapter (xem mục xung đột `builtin:mcp` bên dưới) |
| 3 | `pi-subagents` | subagent delegation + workflow đa-agent |
| 4 | `@tintinweb/pi-subagents` | subagent bổ sung (song song với pi-subagents) |
| 5 | `subagents-pi` | panel/statusline subagent |
| 6 | `pi-goal-x` | `/goal`: goal planning, progress bền, auditor kiểm hoàn thành |
| 7 | `pi-background-tasks` | background shell task, agent ủy quyền read-only, run có attest |
| 8 | `pi-model-fallback` | đổi sang model fallback theo **rule** (provider/model + HTTP 429/5xx) khi provider lỗi |
| 9 | `@narumitw/pi-usage` | hiển thị usage tài khoản |
| 10 | `pi-simplify` | review code vừa đổi: clarity, consistency, maintainability |
| 11 | `pi-footer` | statusline nhiều hàng, tùy biến (repo này đang dùng) |
| 12 | `pi-powerline-footer` | status bar kiểu powerline (hiện **tắt** qua `"extensions": []`) |
| 13 | `statusline-pi` | statusline bổ sung |
| 14 | `pi-memory` | memory + semantic search (qmd) trên daily log / long-term / scratchpad |
| 15 | `pi-worktree` | quản lý git worktree, workspace cô lập 1 lệnh |
| 16 | `@99percentpeople/pi-todo` | todo nguyên tử tối giản: xoá bằng omission, sống qua compaction |
| 17 | `@juicesharp/rpiv-ask-user-question` | hỏi user bằng questionnaire trắc nghiệm thay vì đoán |
| 18 | `@juicesharp/rpiv-btw` | `/btw`: hỏi nhanh 1 câu bằng main model không làm bẩn hội thoại |
| 19 | `@pi-unipi/notify` | notify khi agent xong/lỗi: OS native, Gotify, Telegram, ntfy (⚠ config chứa credential — không backup) |
| 20 | `pi-smart-fetch` **(pin 0.3.17)** | `web_fetch` giả TLS fingerprint desktop + defuddle extraction |
| 21 | `pi-advisor-flow` | Executor/Advisor: ý kiến thứ 2 từ model mạnh hơn, review gate trước plan / sau fail lặp / trước khi kết luận xong |
| 22 | `advisor-pi` | tool `advisor` riêng + prefs tại `advisor-pi-preferences/` |
| 23 | `@tmustier/pi-session-recap` | recap "while you were away" khi quay lại session |
| 24 | `pi-lens` | LSP diagnostics + navigation, linter/type-checker, formatter, ast-grep/tree-sitter |
| 25 | `@pinet/model-aware-compaction` | compaction theo cửa sổ model — **tắt**, `compaction-policy.ts` đã làm việc này |
| 26 | `pi-multix` | sinh/xử lý media qua multix CLI (credential ở `~/.multix/.env`) |
| 27 | `@tian.zuo/pi-devin-acp` | tích hợp Devin qua ACP |

> Version **chỉ để tham khảo tại thời điểm snapshot**; source of truth là `config/settings.json`.
> Chỉ `pi-smart-fetch` pin cứng, còn lại float → máy mới lấy bản mới nhất. Pin trong
> `config/settings.json` nếu cần khớp tuyệt đối.

### Xung đột `builtin:mcp` ↔ `pi-mcp-adapter`

Cả hai đăng ký `/mcp` → `settings.json` có `"extensions": ["-builtin:mcp"]` để tắt
bản built-in, giữ `pi-mcp-adapter` (đầy đủ hơn: quản qua `mcp.json` + tool `mcp__*`).
Xoá dòng đó nếu muốn dùng built-in.

### `pi-devin-acp`: bypass permission mặc định (yolo)

Devin qua ACP mặc định chạy mode `accept-edits` và hỏi quyền mỗi tool call (prompt
"devin requests permission"). Extension đọc toggle bền vững ở
`~/.pi/devin-acp/settings.json` — file **ngoài** `~/.pi/agent` → không nằm trong backup:

```json
{
  "yolo": true,
  "fast": false
}
```

- `yolo: true` → mọi session devin mới được set mode `bypass` (auto-approve
  server-side, không hiện prompt). Request nào lọt qua (rule bắt buộc ask) thì bridge
  tự chọn `allow_always`/`allow_once`. Khi bật, `/devin mode` khóa ở bypass.
- `fast` → dùng priority tier của model family nếu có; toggle `/devin fast on|off`.
- Flag đọc lúc extension load → sửa file xong phải reload pi. Trong session đang chạy
  dùng `/devin yolo on|off` — vừa ghi file vừa áp dụng ngay cho runtime.

---

## Statusline

Statusline là `pi-footer`, config ở `config/extensions/pi-footer.json`. Layout **3 hàng**,
không rơi widget nào: hàng `extensionStatusRow` bị ẩn qua `hiddenKeys` và status của
extension khác được kéo lên hàng 3 dưới dạng widget `external-status`.

> ⚠️ `hiddenKeys` là danh sách **đúng tuyệt đối**, không wildcard. Extension mới publish
> status key khác → hàng thứ 4 quay lại; thêm key vào `hiddenKeys` (hoặc `/footer`).

> ⚠️ Config dùng `"iconMode": "nerd"` → terminal cần **Nerd Font** (bản Mono) để icon
> hiển thị; font `fonts/` trong repo là JetBrains Mono **chưa patch** — cài nó rồi trỏ
> terminal vào là cách chắc chắn để icon vỡ. Hoặc đổi `iconMode` sang `"emoji"`/`"text"`.

### Font terminal: cần Nerd Font

Mọi icon statusline là codepoint **Private Use Area** của Nerd Fonts — font thường không có,
terminal sẽ fallback sang font khác và icon thành hình vô nghĩa (◆, ✦, `?`) thay vì báo lỗi.

```bash
# Linux (user-local)
mkdir -p ~/.local/share/fonts
# tải Nerd Font bản *Mono*, VD:
#   https://github.com/ryanoasis/nerd-fonts/releases → JetBrainsMono.zip
fc-cache -fv
```

Rồi trỏ terminal về font đó. Bỏ qua nếu đổi `iconMode` sang `emoji`/`text`.

---

## pi-model-fallback

Đổi model theo rule khi provider trả HTTP status khớp rule (mặc định `429`, `500`, `502`,
`503`, `504`), state bền + cooldown (`429` → 72h, `5xx` → 10 phút; header `Retry-After` /
`x-ratelimit-reset*` ghi đè khi có). Rule khớp theo thứ tự, cái đầu thắng.

```bash
/model-fallback:status   # trạng thái, entry durable nào đang active
/model-fallback:reset    # xoá durable state, về model trước fallback
```

Config ở `~/.pi/agent/model-fallback/config.json`. Snapshot này dùng rule cho provider
`deepseek` → `deepseek-v4-flash`. `state.json` cùng thư mục là state theo máy → không backup.

---

## `pi-advisor-flow` và `advisor-pi` — 2 extension advisor khác nhau

**Đừng nhầm:** trong snapshot có *hai* extension advisor độc lập:

- **`pi-advisor-flow`**: config `~/.pi/agent/advisor.json` (gốc config dir), review gate
  tự động. Validate bằng `scripts/pi-setup-verify-advisor.mjs` — extension nuốt key lạ
  không lỗi, chỉ notify "preserved but ignored" → key sai chính tả **trông như đã config
  nhưng không có tác dụng**. Script replay đúng 2 check extension chạy lúc load.
- **`advisor-pi`**: prefs ở `~/.pi/agent/advisor-pi-preferences/` — mỗi setting 1 file
  (`model.json`, `thinkingLevel.json`, `maxUses.json`, …). Dòng `advisor:<model> <level>`
  trên footer là của extension này; sửa `advisor.json` không ảnh hưởng nó.

```bash
node scripts/pi-setup-verify-advisor.mjs          # validate file trong repo
node scripts/pi-setup-verify-advisor.mjs --live   # + file đang chạy, so 2 bản
```

---

## `pi-lens` (LSP)

pi không có LSP built-in → phải là extension. Config **ngoài** config dir:
`~/.pi-lens/config.json` (restore qua `external-configs.txt`):

```json
{
  "lsp": { "enabled": true },
  "widget": { "visible": false },
  "format": { "enabled": false },
  "autofix": { "enabled": false },
  "ui": { "compactLspStatus": true }
}
```

- `format`/`autofix` **false** — package mặc định `true` nghĩa là nó format và apply
  quickfix lên code bạn sửa; chỉ bật khi muốn.
- `ui.compactLspStatus` **true** — pi-lens ≥4.4 có sẵn option này (issue #3099):
  status `LSP ✓`/`LSP ✗` thay vì liệt kê tên server. Với bản ≤4.1.x phải vá bundle
  bằng `scripts/pi-lens-compact-lsp-status.mjs` (script dừng exit 1/2 khi bundle đổi
  shape, không đoán bừa). `npm update` ghi đè bundle → chạy lại script khi cần.

---

## Compaction: khi nào compact vs summary được dài bao nhiêu

Hai nút độc lập, gộp làm một là cách để session chết với
`Compaction failed: generation hit the token cap`:

- **Khi nào compact**: extension local `config/extensions/compaction-policy.ts` —
  **40%** cửa sổ cho model ≥500K context, **75%** cho model nhỏ hơn, nghỉ 60s giữa các
  request và **backoff 10 phút** sau compaction lỗi (để không re-arm ~500K token
  summarization ngay turn kế).
- **Summary được dài bao nhiêu**: pi core — `min(floor(0.8 × compaction.reserveTokens),
  model.maxTokens)`. Default `reserveTokens: 16384` → cap summary **13,107 token**;
  UPDATE summarization của pi tăng đơn điệu nên session dài vượt cap → fail.
- Snapshot ship `compaction.modelOverrides` với `reserveTokens: 60000` (→ cap ~48K)
  cho các model cửa sổ ≥500K trong `enabledModels`. `reserveTokens` global giữ 16384
  vì nó còn là native trigger reserve — phải nhỏ cho cửa sổ nhỏ.
- `@pinet/model-aware-compaction` cài nhưng **tắt** (`enabled: false`): rule trùng 2
  ngưỡng trên, và khi lỗi nó re-arm ngay (`onError` xoá `triggeredModelKey`) → retry
  summarization đắt tiền mỗi turn.

---

## Scripts

Các script setup **không hỏi xác nhận** — an toàn để chạy trong script/CI. Rủi ro xử lý
bằng snapshot + cảnh báo stderr. Script vá dừng exit 2 thay vì đoán khi code đổi hình.

### `pi-setup-patch-extensions.mjs`

`/reload` invalidate runner cũ; extension giữ `ctx` trong hàm render chạy sau đó ném
`Error: This extension ctx is stale…` và pi coi đó là fatal → tiến trình chết.

| Patch | Fix |
|---|---|
| `pi-footer` | bọc `ctx.getContextUsage()` trong render bằng try/catch, trả `[]` cho frame cũ; footer áp lại bằng ctx mới ở `session_start` kế |
| `pi-goal-x` | 0.32.x đã fix upstream (capture `goalCwd`/`storage` lúc đăng ký widget) — script nhận dạng cả bản vá tay lẫn bản npm đã fix, vá tay cho bản ≤0.31.x |

```bash
node scripts/pi-setup-patch-extensions.mjs           # vá (idempotent, backup trước)
node scripts/pi-setup-patch-extensions.mjs --check   # báo trạng thái: 0 = đủ, 1 = thiếu
```

> ⚠ Vá nằm trong `node_modules` → **chạy lại sau mỗi `pi update`** hoặc cài lại package.

### `pi-setup-backup.sh`

```bash
./scripts/pi-setup-backup.sh                        # → ./pi-setup-portable.tar.gz (chỉ setup)
./scripts/pi-setup-backup.sh --config-dir config     # → cập nhật config/ trong repo
./scripts/pi-setup-backup.sh --skills --hooks        # thêm skills + hooks
./scripts/pi-setup-backup.sh -o backups/pi-setup-portable.tar.gz \
  --exclude-file config/.pi-setup-exclude            # bundle đã lọc
./scripts/pi-setup-backup.sh --dry-run
```

| Opt-in (KHÔNG mặc định) | Lấy gì |
|---|---|
| `--auth` | `auth.json` ⚠ chứa credential → đừng bao giờ publish artifact |
| `--skills` | `skills/` (dereference symlink) |
| `--hooks` | `hooks/` trong `~/.pi/agent` |
| `--memory` | `memory/` |
| `--missions` | `missions/` ⚠ state pi-goal-x, có thể chứa tên project |
| `--sessions` | `sessions/` (lịch sử chat) |

| Opt-out | Hiệu quả |
|---|---|
| `--no-statusline` | Không backup config statusline → máy mới giữ layout mặc định |

Script còn: ghi temp file rồi `mv` (artifact không hỏng khi ngắt giữa chừng) · **quét
secret** (`sk-*`, `ghp_*`, `xox*`, `BEGIN PRIVATE KEY`, `api_key=…`) · cảnh báo symlink
trỏ ra ngoài · báo extension config có được backup không · nén deterministic (`gzip -n`
→ cùng nội dung cùng SHA-256) · từ chối ghi `--config-dir` vào `$HOME`, `/`, hoặc chính
config dir của pi.

### `pi-setup-restore.sh`

| Option | Hiệu quả |
|---|---|
| `--from-config DIR` | restore từ `config/` (plain file) |
| `--bundle FILE` | restore từ `.tar.gz` |
| `--target DIR` | đích khác `~/.pi/agent` |
| `--scratch` | đích thư mục tạm — diễn tập an toàn |
| `--install` | chạy pi headless 1 lần để cài extension (~2-3 phút) |
| `--verify` | so số extension đã cài với `settings.json` |
| `--with-trust` | copy cả `trust.json` |
| `--dry-run` | chỉ in, không ghi |

Trước khi ghi đè, `settings.json` **và** `auth.json` (khi có trong nguồn) được snapshot
thành `*.bak.<timestamp>`. Script đặt `trap ERR` — không bao giờ thoát im lặng.

---

## Hạn chế đã biết

- **`auth.json` không trong repo** (secret) → `/login` lại ở máy mới.
- **`sessions/`, `missions/` không trong repo** → lịch sử không migrate; tự backup bằng
  `--sessions`/`--missions` nếu cần.
- **`pi-memory` cần `qmd`** → `npm i -g @tobilu/qmd` ở máy mới.
- **`pi` cài global theo version Node** → đổi `nvm use`/`fnm use` làm mất lệnh `pi`;
  cài lại global cho version đó.
- **Statusline icon cần Nerd Font** → xem mục font phía trên.
- **Vá `pi-footer` nằm trong `node_modules`** → chạy lại `pi-setup-patch-extensions.mjs`
  sau mỗi `pi update`.

---

## Repo cá nhân

Đây là snapshot setup của một người tại một thời điểm — **không phải sản phẩm chính
thức** của pi hay package nào được liệt kê. Không kèm license; bên thứ ba theo license
của họ. Ý tưởng + script gốc: [mrgoonie/zuey-pi-setup](https://github.com/mrgoonie/zuey-pi-setup).
