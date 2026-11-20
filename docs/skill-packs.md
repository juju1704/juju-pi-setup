# Skill packs ngoài repo này

Repo này mirror **setup của pi** (`settings.json`, `extensions/`, `bin/`). Skill pack
bên thứ ba không nằm trong `config/`: chúng là repo riêng, phải clone ở máy mới, rồi
đăng ký bằng symlink theo convention skill của máy.

Hiện có một pack: **`reverse-skill`** — router cho công việc reverse engineering,
pentest có uỷ quyền, malware/forensics/CTF.

## Convention đăng ký skill trên máy này

Một skill không cần entry riêng trong `settings.json`. Ba client đều quét cùng những
thư mục sau, nên chỉ cần symlink đúng chỗ:

| Thư mục | Ai đọc | Cấu hình |
|---|---|---|
| `~/juju-projects/repo/juju-agent-skills/skills/` | omp, pi | omp `skills.customDirectories`; pi `skills[]` |
| `~/.claude/skills/` | Claude Code, omp | omp `skills.enableClaudeUser: true` |

`jj-*` nằm trực tiếp trong `juju-agent-skills/skills/`. `argos-qa`, `juju-chef`,
`daily-summary` nằm ở repo riêng rồi symlink vào một trong hai thư mục trên.
`reverse-skill` đi theo kiểu thứ hai.

## reverse-skill

Nguồn: [zhaoxuya520/reverse-skill](https://github.com/zhaoxuya520/reverse-skill) (MIT).
`skills/` có 49 mục; trong đó 45 là skill chuyên môn. Cấu trúc quan trọng:

```text
reverse-skill/
└── skills/
    ├── SKILL.md              ← ROUTER: name=reverse-skill-router + description
    ├── config/routing.json   ← bảng route duy nhất (44 rule)
    ├── scripts/              ← master-route.sh, case-init.sh, refresh-tool-index.sh, bootstrap-reverse.sh
    ├── apk-reverse/SKILL.md  ┐
    ├── js-reverse/SKILL.md   ├ 43 thư mục con trực tiếp có SKILL.md, tìm được từ router
    ├── pentest-tools/        │  (tổng 45 nếu tính cả 2 cái lồng sâu:
    └── field-journal/        ┘   pentest-tools/src-hunter, reverse-engineering/dsl-vm-reverse)
```

### Cài

```bash
cd ~/juju-projects/repo/juju-pi-setup
./scripts/install-reverse-skill.sh              # cả hai đích, idempotent
./scripts/install-reverse-skill.sh --dry-run    # xem trước
./scripts/install-reverse-skill.sh --ref v1.0.1 # ghim tag/commit
```

Bản đã cài trên máy này: commit **`b972ad0`** (2026-11-20). Script mặc định `git pull`
nhánh mặc định → máy mới nhận bản **mới hơn**; dựng lại đúng bản này thì
`./scripts/install-reverse-skill.sh --ref b972ad0`.

Script làm đúng hai việc, chạy lại bao nhiêu lần cũng ra cùng trạng thái:

| Đích | Nội dung | Ai thấy |
|---|---|---|
| `repo/juju-agent-skills/skills/reverse-skill` | symlink **tương đối** (`../../reverse-skill/skills`) | omp qua `customDirectories`, pi qua `skills[]` |
| `~/.claude/skills/reverse-skill` | symlink tuyệt đối | Claude Code, omp qua `enableClaudeUser` |

Symlink trong `juju-agent-skills` cố ý là **tương đối**: nó nằm trong một git work
tree, nên tuyệt đối hoá sẽ hỏng ngay khi clone ở path khác. Script tự chọn tương đối
khi thư mục đích là git repo, tuyệt đối khi không.

Biến môi trường: `REVERSE_SKILL_DIR`, `AGENT_SKILLS_DIR`, `CLAUDE_SKILLS_DIR`.
Cờ: `--dir`, `--ref`, `--client agents|claude|all`, `--no-pull`, `--dry-run`.

`--client agents` chỉ nối `juju-agent-skills` (đủ cho omp + pi), hữu ích khi không
muốn đụng `~/.claude`.

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

| Cách | Entry trong catalog | Token prompt | Hệ quả |
|---|---|---|---|
| Link từng skill con (45 symlink) | 45 | ~1.789 | Mọi mô tả chuyên môn nằm thường trực trong prompt |
| Link `skills/` (chọn) | 1 | ~90 | 45 mô tả chuyên môn không vào prompt; router đọc `routing.json` khi cần |

Lưu ý: chỉ đúng vì `skills/` **có** `SKILL.md` ở gốc. Nếu link thẳng repo root
(không có `SKILL.md` ở gốc) thì client sẽ đệ quy và thấy cả 45 — sai ý đồ.

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
git -C ~/juju-projects/repo/reverse-skill log --oneline -1   # đang ở commit nào

# gỡ: bỏ hai symlink là xong, không có gì phải sửa trong settings
rm ~/juju-projects/repo/juju-agent-skills/skills/reverse-skill ~/.claude/skills/reverse-skill
```

### Ghi chú

- Không có entry nào của pack được thêm vào `~/.pi/agent/settings.json`. pi thấy skill
  qua `skills[]` trỏ `juju-agent-skills/skills` — vốn đã có sẵn cho `jj-*`. Nhờ vậy
  `config/settings.json` (mirror của `pi-setup-backup.sh`) không phải chứa path riêng
  của pack, và restore trên máy mới không trỏ sai.
- Symlink trong `juju-agent-skills` hiện là **untracked**: `juju-agent-skills` chỉ có
  `Makefile` (help/status/lint-md/fix-md) và không có target nào tự sinh symlink.
  Muốn link vào `~/.claude/skills` thì `ln -sfn` tay hoặc để
  `install-reverse-skill.sh` làm — script làm cả hai đích và idempotent.
- Pack 16 MB sau clone (chủ yếu `skills/field-journal` + `docs/`). Không nằm trong
  artifact backup của repo này — clone lại bằng script.
- `work/` và `skills/tool-index.*` bị gitignore trong pack: chạy router sinh `work/`
  nhưng `git status` của pack vẫn sạch.
- Pack tự nhận là **client-neutral**; không copy `RULES.md` của nó vào system prompt
  toàn cục. Chỉ entry `SKILL.md` được nạp khi task khớp.
