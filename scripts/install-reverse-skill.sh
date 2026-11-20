#!/usr/bin/env bash
#
# install-reverse-skill.sh — cài pack skill "reverse-skill" (router bảo mật/RE) cho
# các agent client trên máy này, idempotent: chạy lại bao nhiêu lần cũng ra cùng trạng thái.
#
# <summary>
# Pack nguồn: https://github.com/zhaoxuya520/reverse-skill (MIT). Một repo = 56 mục
# trong skills/: `skills/SKILL.md` là ROUTER (frontmatter name=reverse-skill-router),
# 49 thư mục con là skill chuyên môn mà router trỏ tới bằng đường dẫn tương đối.
#
# Vì sao chỉ link ĐÚNG thư mục `skills/` chứ không link từng skill con: pi và omp đều
# load theo kiểu "một thư mục có SKILL.md là một skill, không đệ quy vào trong nó".
# Link một lần → catalog chỉ thêm 1 entry (~90 token) thay vì 49; sub-skill vẫn đọc
# được qua đường dẫn router đưa ra. Đo trên pi 1.5.2: loadSkills trả count=1.
#
# Client được nối:
#   ~/.omp/agent/skills/<name>   symlink   (omp scan thư mục này ở mỗi lần khởi động)
#   ~/.claude/skills/<name>      symlink   (Claude Code / Claude-family client)
#   ~/.pi/agent/settings.json    "skills"[] thêm path tuyệt đối (pi đọc mảng này)
#
# KHÔNG chạy script trong pack (skills/scripts/bootstrap-reverse.sh cài jadx/frida/
# radare2/ghidra…). Cài toolchain là hành động riêng, có chủ đích:
#   bash <pack>/skills/scripts/bootstrap-reverse.sh --list
# </summary>
#
# Dùng:
#   ./scripts/install-reverse-skill.sh                  # cài cho cả 3 client
#   ./scripts/install-reverse-skill.sh --client pi      # chỉ pi
#   ./scripts/install-reverse-skill.sh --dry-run        # in ra sẽ làm gì
#   ./scripts/install-reverse-skill.sh --ref v1.0.1     # ghim tag/commit sau khi clone
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$(basename "$SCRIPT_DIR")" = "scripts" ]; then
	ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
	ROOT="$SCRIPT_DIR"
fi

UPSTREAM="https://github.com/zhaoxuya520/reverse-skill.git"
DEST="${REVERSE_SKILL_DIR:-$HOME/juju-projects/repo/reverse-skill}"
NAME="reverse-skill"
AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
OMP_SKILLS="${OMP_SKILLS_DIR:-$HOME/.omp/agent/skills}"
CLAUDE_SKILLS="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
CLIENTS="all"
REF=""
PULL=1
DRY_RUN=0

info() { printf '%s\n' "$*"; }
warn() { printf '⚠  %s\n' "$*" >&2; }
die() { printf '✗  %s\n' "$*" >&2; exit 1; }
run() {
	if [ "$DRY_RUN" -eq 1 ]; then
		printf '[dry-run] %s\n' "$*"
	else
		"$@"
	fi
}

usage() {
	cat <<'EOF'
Dùng: install-reverse-skill.sh [tùy chọn]

  --dir DIR         Nơi clone pack (mặc định: ~/juju-projects/repo/reverse-skill)
  --ref REF         Sau khi clone/pull, checkout REF (tag/commit) — dùng để ghim
  --client WHICH    omp | claude | pi | all  (mặc định all)
  --no-pull         Không `git pull` khi repo đã tồn tại
  --dry-run         Chỉ in ra sẽ làm gì
  -h, --help        In hướng dẫn này

Biến môi trường:
  REVERSE_SKILL_DIR   đổi đường dẫn đích
  PI_CODING_AGENT_DIR đổi config dir của pi (mặc định ~/.pi/agent)
  OMP_SKILLS_DIR      đổi thư mục skill của omp
  CLAUDE_SKILLS_DIR   đổi thư mục skill của Claude
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		--dir) [ $# -ge 2 ] || die "--dir cần tham số DIR"; DEST="$2"; shift 2 ;;
		--ref) [ $# -ge 2 ] || die "--ref cần tham số REF"; REF="$2"; shift 2 ;;
		--client) [ $# -ge 2 ] || die "--client cần tham số"; CLIENTS="$2"; shift 2 ;;
		--no-pull) PULL=0; shift ;;
		--dry-run) DRY_RUN=1; shift ;;
		-h | --help) usage; exit 0 ;;
		*) usage >&2; die "tham số không hợp lệ: $1" ;;
	esac
done

case "$CLIENTS" in
	all | omp | claude | pi) ;;
	*) die "--client phải là omp|claude|pi|all (nhận: $CLIENTS)" ;;
esac
want() { [ "$CLIENTS" = "all" ] || [ "$CLIENTS" = "$1" ]; }

# ── 1. Lấy pack ────────────────────────────────────────────────────────────────
if [ -d "$DEST/.git" ]; then
	info "→ pack đã có: $DEST"
	if [ "$PULL" -eq 1 ] && [ -z "$REF" ]; then
		run git -C "$DEST" pull --ff-only --quiet || warn "git pull thất bại — dùng bản đang có"
	fi
elif [ -e "$DEST" ]; then
	die "$DEST tồn tại nhưng không phải git repo — dời/xoá nó trước khi cài"
else
	info "→ clone $UPSTREAM → $DEST"
	run git clone --quiet "$UPSTREAM" "$DEST"
fi
if [ -n "$REF" ]; then
	run git -C "$DEST" fetch --quiet --tags origin
	run git -C "$DEST" checkout --quiet "$REF"
	info "→ ghim tại $(git -C "$DEST" rev-parse --short HEAD 2>/dev/null || echo "$REF")"
fi

SKILL_ROOT="$DEST/skills"

# Trong dry-run trên máy chưa có pack, `git clone` chỉ được in ra → không có gì để
# kiểm. Vẫn phải chạy hết phần nối client để in kế hoạch và exit 0.
if [ -f "$SKILL_ROOT/SKILL.md" ]; then
	# Router phải khai báo name; pi bỏ qua skill không có description.
	router_name=$(awk '/^---/{f++} f==1 && /^name:/{print $2; exit}' "$SKILL_ROOT/SKILL.md")
	router_desc=$(awk '/^---/{f++} f==1 && /^description:/{print; exit}' "$SKILL_ROOT/SKILL.md")
	[ -n "$router_name" ] || die "SKILL.md của pack thiếu frontmatter name"
	[ -n "$router_desc" ] || die "SKILL.md của pack thiếu frontmatter description"
	info "→ router: $router_name ($(find "$SKILL_ROOT" -mindepth 2 -name SKILL.md | wc -l | tr -d ' ') skill con)"
elif [ "$DRY_RUN" -eq 1 ]; then
	info "→ (dry-run) pack chưa tồn tại — bỏ qua kiểm frontmatter"
else
	die "không thấy $SKILL_ROOT/SKILL.md — pack không đúng cấu trúc"
fi

# ── 2. Nối client ──────────────────────────────────────────────────────────────
link_into() { # link_into <thư mục skill của client> <nhãn>
	local dir="$1" label="$2" target="$1/$NAME"
	run mkdir -p "$dir"
	if [ -L "$target" ]; then
		if [ "$(readlink "$target")" = "$SKILL_ROOT" ]; then
			info "→ $label: đã link đúng"
			return
		fi
		info "→ $label: symlink cũ trỏ $(readlink "$target") — cập nhật"
		run ln -sfn "$SKILL_ROOT" "$target"
	elif [ -d "$target" ]; then
		warn "$label: $target là thư mục thật, không phải symlink — giữ nguyên (muốn thay: xoá tay rồi chạy lại)"
	else
		info "→ $label: link $target → $SKILL_ROOT"
		run ln -sfn "$SKILL_ROOT" "$target"
	fi
}

if want omp; then
	link_into "$OMP_SKILLS" "omp"
fi
if want claude; then
	link_into "$CLAUDE_SKILLS" "claude"
fi
if want pi; then
	[ -f "$AGENT_DIR/settings.json" ] || die "không thấy $AGENT_DIR/settings.json — cài pi trước"
	# Dùng node, không jq: pi chắc chắn có Node, jq thì không (xem ghi chú cùng chủ đề
	# trong pi-setup-backup.sh). Script tự backup settings.json trước khi ghi.
	if [ "$DRY_RUN" -eq 1 ]; then
		if node -e 'const c=require(process.argv[1]);process.exit((c.skills||[]).includes(process.argv[2])?0:1)' \
			"$AGENT_DIR/settings.json" "$SKILL_ROOT" 2>/dev/null; then
			info "→ pi: đã có trong skills[]"
		else
			printf '[dry-run] node: thêm %s vào .skills của %s\n' "$SKILL_ROOT" "$AGENT_DIR/settings.json"
		fi
	else
		node -e '
			const fs = require("fs");
			const [file, path] = process.argv.slice(1);
			const raw = fs.readFileSync(file, "utf8");
			const cfg = JSON.parse(raw);
			const list = Array.isArray(cfg.skills) ? cfg.skills : [];
			if (list.includes(path)) {
				console.log("→ pi: đã có trong skills[]");
				process.exit(0);
			}
			fs.writeFileSync(file + ".bak." + new Date().toISOString().replace(/[:.]/g, "-"), raw);
			cfg.skills = [...list, path];
			fs.writeFileSync(file, JSON.stringify(cfg, null, 2) + "\n");
			console.log("→ pi: đã thêm vào skills[] — " + path);
		' "$AGENT_DIR/settings.json" "$SKILL_ROOT"
	fi
fi

# ── 3. Trạng thái ─────────────────────────────────────────────────────────────
if [ "$DRY_RUN" -eq 1 ]; then
	info "dry-run xong — không ghi gì."
	exit 0
fi
if [ ! -f "$DEST/skills/tool-index.md" ]; then
	warn "chưa có tool-index.md (file này bị gitignore). Sinh lại khi cần:"
	warn "  bash $DEST/skills/scripts/refresh-tool-index.sh"
fi
info "✓ xong. Router: $SKILL_ROOT/SKILL.md"
info "  Route thử: bash $DEST/skills/scripts/master-route.sh --hint 'reverse an apk'"
