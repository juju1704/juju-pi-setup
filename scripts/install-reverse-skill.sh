#!/usr/bin/env bash
#
# install-reverse-skill.sh — cài pack skill "reverse-skill" (router bảo mật/RE) theo
# đúng convention skill của máy này, idempotent: chạy lại bao nhiêu lần cũng ra cùng
# trạng thái.
#
# <summary>
# Pack nguồn: https://github.com/zhaoxuya520/reverse-skill (MIT). `skills/SKILL.md` là
# ROUTER (frontmatter name=reverse-skill-router); dưới nó là 45 skill chuyên môn — 43
# thư mục con trực tiếp + 2 lồng sâu (pentest-tools/src-hunter,
# reverse-engineering/dsl-vm-reverse) — mà router trỏ tới bằng đường dẫn tương đối.
#
# Vì sao chỉ link ĐÚNG thư mục `skills/` chứ không link từng skill con: pi và omp đều
# load theo kiểu "một thư mục có SKILL.md là một skill, không đệ quy vào trong nó".
# Link một lần → catalog chỉ thêm 1 entry (~90 token) thay vì 45; sub-skill vẫn đọc
# được qua đường dẫn router đưa ra. Đo trên pi 1.5.2: loadSkills trả count=1.
#
# Đăng ký theo convention có sẵn của máy — KHÔNG thêm entry riêng vào settings:
#   ~/juju-projects/repo/juju-agent-skills/skills/<name>  symlink
#       → pi  đọc qua `skills[]` trong ~/.pi/agent/settings.json (đã đo: count=1)
#       → omp khai báo `skills.customDirectories` trỏ cùng thư mục
#   ~/.claude/skills/<name>                               symlink
#       → Claude Code
#       → omp qua `skills.enableClaudeUser` (đã đo: ẩn link juju-agent-skills thì omp
#         vẫn nạp được skill từ đây)
# Nhờ vậy skill pack nằm cùng chỗ với `jj-*` và không tạo đường đăng ký thứ hai.
#
# KHÔNG chạy script trong pack (skills/scripts/bootstrap-reverse.sh cài jadx/frida/
# radare2/ghidra…). Cài toolchain là hành động riêng, có chủ đích:
#   bash <pack>/skills/scripts/bootstrap-reverse.sh --list
# </summary>
#
# Dùng:
#   ./scripts/install-reverse-skill.sh                  # cả hai đích
#   ./scripts/install-reverse-skill.sh --client agents  # chỉ juju-agent-skills (omp + pi)
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
AGENT_SKILLS="${AGENT_SKILLS_DIR:-$HOME/juju-projects/repo/juju-agent-skills/skills}"
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
  --client WHICH    agents | claude | all  (mặc định all)
                    agents = ~/juju-projects/repo/juju-agent-skills/skills (omp + pi)
  --no-pull         Không `git pull` khi repo đã tồn tại
  --dry-run         Chỉ in ra sẽ làm gì
  -h, --help        In hướng dẫn này

Biến môi trường:
  REVERSE_SKILL_DIR   đổi đường dẫn đích
  AGENT_SKILLS_DIR    đổi thư mục skill dùng chung (mặc định juju-agent-skills/skills)
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
	all | agents | claude) ;;
	*) die "--client phải là agents|claude|all (nhận: $CLIENTS)" ;;
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
# Đích của symlink: tương đối khi thư mục chứa link nằm trong git work tree VÀ pack
# nằm cạnh repo đó (cùng thư mục cha của repo, vd `<workspace>/repo/`), tuyệt đối
# trong mọi trường hợp còn lại.
#
# Vì sao có điều kiện thứ hai: symlink trong repo phải sống sót khi clone ở path khác,
# nhưng tương đối hoá một pack nằm ngoài cây làm việc sinh ra `../../../..` trỏ ra
# /tmp hay /opt — vừa dễ đứt vừa khó đọc. Ngoài cây thì tuyệt đối là câu trả lời đúng.
link_value() { # link_value <thư mục chứa link>
	local top shared
	if top="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)"; then
		shared="$(dirname "$top")"
		case "$(realpath -m "$SKILL_ROOT")" in
			"$shared"/*) realpath -m --relative-to="$1" "$SKILL_ROOT"; return ;;
		esac
	fi
	printf '%s\n' "$SKILL_ROOT"
}

link_into() { # link_into <thư mục skill của client> <nhãn>
	local dir="$1" label="$2" target="$1/$NAME" value
	run mkdir -p "$dir"
	value="$(link_value "$dir")"
	if [ -L "$target" ]; then
		# So sánh đích thật để symlink tương đối và tuyệt đối cùng trỏ một chỗ
		# không bị coi là lệch.
		if [ "$(realpath -m "$target" 2>/dev/null)" = "$(realpath -m "$SKILL_ROOT")" ]; then
			info "→ $label: đã link đúng"
			return
		fi
		info "→ $label: symlink cũ trỏ $(readlink "$target") — cập nhật"
		run ln -sfn "$value" "$target"
	elif [ -d "$target" ]; then
		warn "$label: $target là thư mục thật, không phải symlink — giữ nguyên (muốn thay: xoá tay rồi chạy lại)"
	else
		info "→ $label: link $target → $value"
		run ln -sfn "$value" "$target"
	fi
}

if want agents; then
	if [ -d "$AGENT_SKILLS" ]; then
		link_into "$AGENT_SKILLS" "agents (omp + pi)"
	else
		warn "không thấy $AGENT_SKILLS — bỏ qua; omp và pi sẽ không thấy skill này"
		warn "  (đặt AGENT_SKILLS_DIR nếu chỗ đó nằm ở path khác)"
	fi
fi
if want claude; then
	link_into "$CLAUDE_SKILLS" "claude"
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
