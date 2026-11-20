# Skill packs ngoài repo này

Repo này mirror **setup của pi** (`settings.json`, `extensions/`, `bin/`). Skill pack
bên thứ ba thì không nằm trong `config/`: chúng là repo riêng, phải clone ở máy mới, và
pi trỏ tới chúng bằng **đường dẫn tuyệt đối** trong `settings.json` → không migrate
bằng copy file được, phải chạy script.

Hiện có một pack: **`reverse-skill`** — router cho công việc reverse engineering,
pentest có uỷ quyền, malware/forensics/CTF.

## reverse-skill

Nguồn: [zhaoxuya520/reverse-skill](https://github.com/zhaoxuya520/reverse-skill) (MIT,
~56 mục trong `skills/`). Cấu trúc quan trọng:

```text
reverse-skill/
└── skills/
    ├── SKILL.md              ← ROUTER: name=reverse-skill-router + description
    ├── config/routing.json   ← bảng route duy nhất (44 rule)
    ├── scripts/              ← master-route.sh, case-init.sh, refresh-tool-index.sh, bootstrap-reverse.sh
    ├── apk-reverse/SKILL.md  ┐
    ├── js-reverse/SKILL.md   ├ 43 thư mục con trực tiếp có SKILL.md
    ├── pentest-tools/        │  (tổng 45 nếu tính cả 2 cái lồng sâu:
    └── field-journal/        ┘   pentest-tools/src-hunter, reverse-engineering/dsl-vm-reverse)
```

### Cài

```bash
cd ~/juju-projects/repo/juju-pi-setup
./scripts/install-reverse-skill.sh              # cả 3 client, idempotent
./scripts/install-reverse-skill.sh --dry-run    # xem trước
./scripts/install-reverse-skill.sh --ref v1.0.1 # ghim tag/commit
```

Bản đã cài trên máy này: commit **`b972ad0`** (2026-11-20). Script mặc định `git pull`
nhánh mặc định → máy mới nhận bản **mới hơn**; dựng lại đúng bản này thì
`./scripts/install-reverse-skill.sh --ref b972ad0`.

Script làm đúng ba việc, chạy lại bao nhiêu lần cũng ra cùng trạng thái:

| Client | Việc | Vì sao |
|---|---|---|
| `~/.omp/agent/skills/reverse-skill` | symlink → `<pack>/skills` | omp scan thư mục này lúc khởi động |
| `~/.claude/skills/reverse-skill` | symlink → `<pack>/skills` | Claude-family client đọc cùng convention |
| `~/.pi/agent/settings.json` → `.skills[]` | thêm `<pack>/skills` | pi đọc mảng `skills`; script backup `settings.json` trước khi ghi, dùng `node` chứ không `jq` (pi chắc chắn có Node) |

Biến môi trường: `REVERSE_SKILL_DIR`, `PI_CODING_AGENT_DIR`, `OMP_SKILLS_DIR`,
`CLAUDE_SKILLS_DIR`. Cờ: `--dir`, `--ref`, `--client omp|claude|pi|all`, `--no-pull`,
`--dry-run`.

### Vì sao chỉ link thư mục `skills/`, không link từng skill con

Cả hai client dừng ở `SKILL.md` đầu tiên gặp trong một thư mục — chúng **không** đăng ký
các `SKILL.md` nằm sâu bên trong. Bằng chứng:

- **pi 1.5.2** — `dist/core/skills.js` `loadSkillsFromDirInternal`: gặp `dir/SKILL.md` là
  load rồi `return` ngay, vòng lặp đệ quy vào thư mục con chỉ chạy khi thư mục đó
  **không** có `SKILL.md`. Đo trực tiếp bằng chính module đó:
  `loadSkills({skillPaths:['<pack>/skills']})` → `count: 1, diagnostics: []`,
  entry duy nhất `reverse-skill-router`.
- **omp 19.0.1** — hỏi catalog: skill `reverse-skill-router` có mặt; `apk-reverse` (tên
  sub-skill) **không** resolve được — nó chỉ là nội dung router trỏ tới.

| Cách | Entry trong catalog | Token mô tả | Hệ quả |
|---|---|---|---|
| Link `skills/` (chọn) | 1 | ~90 | 45 mô tả chuyên môn không vào prompt; router đọc `routing.json` khi cần |
| Link từng skill con | 45 | ~1.789 (đo: 7.159 ký tự) | trả tiền mỗi request; dễ trùng tên skill khác |

Lưu ý: chỉ đúng vì `skills/` **có** `SKILL.md` ở gốc. Nếu link thẳng repo root
(`<pack>/`), loader sẽ đệ quy và kéo theo 42 `SKILL.md` của `CTF-Sandbox-Orchestrator/`
cùng các module khác.

Sub-skill vẫn đọc được: router đưa đường dẫn tương đối (`skills/apk-reverse/SKILL.md`),
agent đọc file đó trong chính thư mục pack.

### Toolchain **không** tự cài

`skills/tool-index.md` (gitignore, sinh theo máy) liệt kê tool nào có/thiếu. Trên máy
Linux này lần sinh đầu: **35 tool khai báo, 5 có sẵn** (python3, node, npm, npx +
runtime), còn lại thiếu — `jadx`, `apktool`, `frida`, `r2`, `ghidra`, `burp`, `nmap`…

Cài toolchain là hành động riêng, có chủ đích, **không** nằm trong `install-reverse-skill.sh`:

```bash
bash <pack>/skills/scripts/bootstrap-reverse.sh --list   # xem manifest, chưa cài gì
bash <pack>/skills/scripts/refresh-tool-index.sh         # chỉ detect, không cài
```

Lý do tách: `bootstrap-reverse.sh` tải binary ngoài (jadx/ghidra từ GitHub release,
radare2 từ source) và có thể đăng ký MCP server — loại side effect phải được duyệt
theo từng lần, không phải hệ quả phụ của "cài skill".

### Dùng

```bash
# route thử. KHÔNG read-only: master-route.sh mkdir + ghi route-scope.md vào
# <project-root>/work/master-route-<ts>/, mặc định project-root = cwd.
# Truyền --project-root để artefact rơi vào chỗ mình muốn:
bash <pack>/skills/scripts/master-route.sh --hint 'reverse an android apk with frida' \
  --project-root /tmp/rs-route
# → PRIMARY -> skills/apk-reverse/SKILL.md | confidence: high
# → ghi /tmp/rs-route/work/master-route-<ts>/route-scope.md

# trong pi / omp: gọi tường minh khi model không tự chọn
/skill:reverse-skill-router reverse the APK in ./samples/app.apk
```

Chạy không có `--project-root` từ một thư mục không gitignore `work/` sẽ để lại
`work/` untracked ở đó — đúng cái đã xảy ra ở `~/juju-projects` trong lần cài này.
`case-init.sh` cũng ghi tương tự.

Router yêu cầu `case-init.sh` tạo `work/<case>/scope.md` với `auth.status=granted`
trước khi đụng vào target — gate này là của pack, giữ nguyên.

### Cập nhật / gỡ

```bash
./scripts/install-reverse-skill.sh              # git pull --ff-only rồi nối lại
git -C <pack> log --oneline -1                  # xem đang ở commit nào
rm ~/.omp/agent/skills/reverse-skill ~/.claude/skills/reverse-skill
node -e 'const f=process.env.HOME+"/.pi/agent/settings.json";const fs=require("fs");const c=JSON.parse(fs.readFileSync(f,"utf8"));c.skills=c.skills.filter(p=>!p.includes("reverse-skill"));fs.writeFileSync(f,JSON.stringify(c,null,2))'
```

### Ghi chú

- `config/settings.json` trong repo này là **mirror sinh tự động** của
  `~/.pi/agent/settings.json` (`pi-setup-backup.sh --config-dir config` xoá rồi copy lại
  từng mục). Nên `.skills[]` chỉ có path của pack **sau lần chạy backup kế tiếp** —
  sửa tay `config/settings.json` là vô nghĩa, lần mirror sau sẽ ghi đè. Trạng thái hiện
  tại: live có 2 phần tử, `config/settings.json` vẫn 1 (chưa backup lại vì working tree
  đang có WIP khác).
- Path trong `.skills[]` là **tuyệt đối theo `$HOME`** → restore trên máy mới (user khác
  hoặc `$HOME` khác) sẽ trỏ sai. Máy mới phải chạy `install-reverse-skill.sh`, không dựa
  vào `settings.json` được restore.
- Pack 16 MB sau clone (chủ yếu `skills/field-journal` + `docs/`). Không nằm trong
  artifact backup của repo này — clone lại bằng script.
- `work/` và `skills/tool-index.*` bị gitignore trong pack: chạy router sinh `work/`
  nhưng `git status` của pack vẫn sạch.
- Pack tự nhận là **client-neutral**; không copy `RULES.md` của nó vào system prompt
  toàn cục. Chỉ entry `SKILL.md` được nạp khi task khớp.
