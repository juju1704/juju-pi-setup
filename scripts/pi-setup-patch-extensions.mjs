#!/usr/bin/env node
/**
 * pi-setup-patch-extensions.mjs — vá các lỗi trong package bên thứ ba đang cài.
 * Hai vá đầu là lỗi "stale extension ctx": pi coi MỌI truy cập vào ctx cũ là
 * lỗi fatal và GIẾT tiến trình pi (in stack trace ra shell) ở lần `/reload`
 * kế tiếp. Vá advisor-pi là lỗi logic, không liên quan stale ctx.
 *
 * Cơ chế chung của ba bản vá stale-ctx: `/reload`, `newSession()`, `fork()`,
 * `switchSession()` invalidate runner cũ; extension nào giữ `ctx` trong closure của
 * một hàm chạy lại sau đó
 * (render của footer/widget, factory, callback hoãn bằng microtask) sẽ ném:
 *
 *   Error: This extension ctx is stale after session replacement or reload.
 *
 * Bốn bản vá đang có (ba bản vá stale-ctx, một bản vá phân giải module):
 *
 *   pi-footer  — `render()` gọi `collectStatuslineData(ctx, …)` → `ctx.getContextUsage()`.
 *                Vá: bọc trong try/catch, trả `[]` cho frame cũ (footer được áp lại
 *                bằng ctx mới ở `session_start` kế tiếp).
 *   advisor-pi — `restoreStateFromSession` replay session-state entry lên config ĐÃ
 *                load từ prefs; entry cũ do fallback im lặng của `ensureAdvisorModelResolves`
 *                ghi ra vẫn resolve được → đè prefs mãi (advisor kẹt model fallback sau reload).
 *                Vá: chụp provider/modelId/thinkingLevel từ prefs trước khi replay, re-assert
 *                sau replay nếu prefs model vẫn resolve.
 *
 *   pi-goal-x  — widget factory của goal truyền cho host hai getter chạy ở MỖI frame
 *                (`getSettings` → `loadGoalSettings(ctx.cwd)`, `getLedgerEvents` →
 *                `goalActivityEvents(ctx, …)`). Vá: chụp `cwd` (chuỗi thuần) lúc đăng ký
 *                widget rồi dùng nó trong getter → đường render không còn chạm ctx.
 *
 *   node-notifier — KHÔNG phải stale ctx: `node-notifier` 12.x là ESM-only, chỉ có
 *                `"type": "module"` + `"exports"`, KHÔNG có `"main"`. Bản `@pi-unipi/notify`
 *                mới (3.0.x) phụ thuộc `node-notifier@^12.1.0`; nhánh phân giải module
 *                kiểu cũ mà pi/jiti dùng (đọc `main`, fallback `index.js`) không thấy file
 *                nào nên extension notify chết ngay lúc load:
 *
 *                  Failed to load extension: Cannot find module
 *                  '…/npm/node_modules/node-notifier/index.js'.
 *                  Please verify that the package.json has a valid "main" entry
 *
 *                Vá: thêm `"main": "./dist/index.js"` vào package.json của package
 *                (resolver chuẩn ESM vẫn dùng `exports`; `main` chỉ để nhánh cũ resolve
 *                được). Đây là bản vá duy nhất sửa `.json` chứ không sửa source `.ts`,
 *                nên nó tự kiểm tra bằng `JSON.parse` thay vì parser TypeScript.
 *
 * Vì sao cần script này trong repo: bản vá nằm trong `node_modules` nên
 * `pi update <package>` / cài lại SẼ ghi đè. Chạy lại script sau mỗi lần update.
 *
 * Dùng:
 *   node scripts/pi-setup-patch-extensions.mjs            # vá tất cả (idempotent)
 *   node scripts/pi-setup-patch-extensions.mjs --check    # chỉ kiểm tra, không ghi
 *   node scripts/pi-setup-patch-extensions.mjs --help
 *
 * Exit code: 0 = tất cả đã vá (hoặc vừa vá xong) · 1 = còn bản chưa vá khi chạy
 * `--check` (hoặc ghi xong mà không thấy guard → tự khôi phục từ backup) ·
 * 2 = lỗi môi trường (không thấy package, code đã đổi cấu trúc nên anchor không khớp).
 */
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { stripTypeScriptTypes } from "node:module";

const say = (line = "") => process.stdout.write(`${line}\n`);
const complain = (line = "") => process.stderr.write(`${line}\n`);

// stripTypeScriptTypes (parser TS của Node) còn experimental nên mỗi lần gọi in một
// ExperimentalWarning; chặn đúng cảnh báo đó để output của script vẫn đọc được.
const emitWarning = process.emit;
process.emit = function (name, data, ...rest) {
	if (name === "warning" && data?.name === "ExperimentalWarning" && /stripTypeScriptTypes/i.test(String(data?.message))) return false;
	return emitWarning.call(process, name, data, ...rest);
};

/** pi cài package vào cây npm riêng của config dir. */
function agentDir() {
	return process.env.PI_CODING_AGENT_DIR || path.join(os.homedir(), ".pi", "agent");
}

function packageFile(relative) {
	return path.join(agentDir(), "npm", "node_modules", relative);
}

/** Các dòng của `source`, giữ nguyên ký tự xuống dòng và thứ tự. */
function splitLines(source) {
	return source.split("\n");
}

function indentOf(line) {
	return line.slice(0, line.length - line.trimStart().length);
}

/**
 * Thay mọi dòng có nội dung (đã trim) khớp `from` bằng `indent + to`, và yêu cầu
 * đúng `count` lần khớp — lệch nghĩa là upstream đã đổi code, phải xem lại tay.
 */
function replaceLines(lines, from, to, count, label) {
	let seen = 0;
	const out = lines.map((line) => {
		if (line.trim() !== from) return line;
		seen += 1;
		return `${indentOf(line)}${to}`;
	});
	if (seen !== count) {
		throw new Error(`${label}: khớp ${seen} lần, cần đúng ${count} lần — bản cài đã đổi cấu trúc, mở file xem lại trước khi vá.`);
	}
	return out;
}

const PI_FOOTER_ANCHOR = [
	"        render(width: number): string[] {",
	"          const data = collectStatuslineData(ctx, pi, footerData, eventWidgets.values, {",
	"            config,",
	"            requestRender: () => tui.requestRender(),",
	"            textVerbosity: liveTextVerbosity,",
	"          });",
].join("\n");

const PI_FOOTER_REPLACEMENT = [
	"        render(width: number): string[] {",
	"          let data: StatuslineData;",
	"          try {",
	"            data = collectStatuslineData(ctx, pi, footerData, eventWidgets.values, {",
	"              config,",
	"              requestRender: () => tui.requestRender(),",
	"              textVerbosity: liveTextVerbosity,",
	"            });",
	"          } catch {",
	"            // ctx is invalidated by ctx.reload()/newSession(), and pi treats any use of an",
	"            // invalidated ctx as fatal. The next session_start re-applies this footer with a",
	"            // fresh ctx, so skip this frame rather than throwing out of render.",
	"            return [];",
	"          }",
].join("\n");

const GOAL_WIDGET_MARK = "const goalCwd = ctx.cwd;";

const PATCHES = [
	{
		id: "pi-footer",
		package: "pi-footer",
		file: path.join("pi-footer", "src", "index.ts"),
		summary: "footer render đọc ctx.getContextUsage() sau /reload",
		isPatched(source) {
			return source.includes("            return [];\n          }\n          const lines = renderStatuslines(widgetStore, data, width, {");
		},
		apply(source) {
			const matches = source.split(PI_FOOTER_ANCHOR).length - 1;
			if (matches !== 1) {
				throw new Error(`pi-footer: khớp anchor ${matches} lần, cần đúng 1 — hàm render đã đổi cấu trúc.`);
			}
			return source.replace(PI_FOOTER_ANCHOR, PI_FOOTER_REPLACEMENT);
		},
	},
	{
		id: "goal-x",
		package: "pi-goal-x",
		file: path.join("pi-goal-x", "extensions", "goal-state.ts"),
		summary: "widget goal gọi getSettings/getLedgerEvents với ctx ở mỗi frame render",
		isPatched(source) {
			// Negative checks phải khoanh đúng hai getter của widget: `loadGoalSettings(ctx.cwd)` còn
			// xuất hiện ở các handler khác (ví dụ `loadGoalSettings(ctx.cwd).hideUnfocusedBanner`),
			// những chỗ đó chạy trong handler chứ không phải trong đường render nên giữ nguyên.
			const captures = source.split(GOAL_WIDGET_MARK).length - 1;
			// pi-goal-x 0.32.x đã fix upstream: factory chụp `goalCwd` + `storage`
			// (goalStorageContext) lúc đăng ký → getter không còn chạm ctx. Nhận dạng
			// cả hai shape: bản vá bằng script này và bản fix sẵn từ npm.
			const upstreamFixed =
				source.includes("getSettings: () => loadGoalSettings(goalCwd),") &&
				source.includes("goalActivityEvents(storage, state.goal.id)");
			const scriptPatched =
				captures === 2 &&
				source.includes("getSettings: () => loadGoalSettings(goalCwd),") &&
				source.includes("goalActivityEvents({ cwd: goalCwd }, state.goal.id)");
			return (
				(upstreamFixed || scriptPatched) &&
				!source.includes("getSettings: () => loadGoalSettings(ctx.cwd),") &&
				!source.includes("goalActivityEvents(ctx, state.goal.id)")
			);
		},
		apply(source) {
			let lines = splitLines(source);
			lines = replaceLines(
				lines,
				"getSettings: () => loadGoalSettings(ctx.cwd),",
				"getSettings: () => loadGoalSettings(goalCwd),",
				2,
				"goal-x getSettings",
			);
			lines = replaceLines(
				lines,
				"getLedgerEvents: () => state.goal ? goalActivityEvents(ctx, state.goal.id) : [],",
				"getLedgerEvents: () => state.goal ? goalActivityEvents({ cwd: goalCwd }, state.goal.id) : [],",
				2,
				"goal-x getLedgerEvents",
			);
			// `cwd` là chuỗi thuần, chụp ngay lúc đăng ký widget (ctx còn hợp lệ) → getter
			// không còn chạm ctx nữa. Trim vẫn giữ nguyên hành vi: cùng cwd, cùng file settings.
			let inserted = 0;
			const withCapture = [];
			for (let i = 0; i < lines.length; i += 1) {
				const line = lines[i];
				const next = lines[i + 1];
				if (line.trim() === "ctx.ui.setWidget(" && next && next.trim() === "GOAL_WIDGET_KEY,") {
					const indent = indentOf(line);
					withCapture.push(`${indent}// The widget getters below run inside pi's render loop, and pi invalidates an extension's ctx`);
					withCapture.push(`${indent}// on /reload or session replacement: touching ctx there throws and pi treats it as fatal. \`cwd\` is`);
					withCapture.push(`${indent}// a plain string, so capture it here (while the ctx is valid) and let the getters read that.`);
					withCapture.push(`${indent}${GOAL_WIDGET_MARK}`);
					inserted += 1;
				}
				withCapture.push(line);
			}
			if (inserted !== 2) {
				throw new Error(`goal-x: thấy ${inserted} chỗ đăng ký widget (cần 2) — bản cài đã đổi cấu trúc.`);
			}
			return withCapture.join("\n");
		},
	},
	{
		id: "advisor-pi",
		package: "advisor-pi",
		file: path.join("advisor-pi", "src", "index.ts"),
		summary: "session state entry (có thể đã fallback) đè prefs model mỗi lần reload",
		isPatched(source) {
			return source.includes("const preferred = { provider: config.provider, modelId: config.modelId, thinkingLevel: config.thinkingLevel };");
		},
		apply(source) {
			const anchor = "config = normalizeConfig(loadPreferences(), defaultConfig(), ctx.modelRegistry, { migrateLegacyDefault: false });";
			if (source.split(anchor).length - 1 !== 1) {
				throw new Error(`advisor-pi: khớp anchor prefs load ${source.split(anchor).length - 1} lần, cần đúng 1 — bản cài đã đổi cấu trúc.`);
			}
			let lines = splitLines(source);
			lines = replaceLines(
				lines,
				anchor,
				"config = normalizeConfig(loadPreferences(), defaultConfig(), ctx.modelRegistry, { migrateLegacyDefault: false });\n" +
					"\t\t// Preferred model/thinking from prefs must win over replayed session state: a\n" +
					"\t\t// session-state entry saved by the silent fallback in ensureAdvisorModelResolves\n" +
					"\t\t// would otherwise stick forever, since it still resolves and is never rewritten.\n" +
					"\t\tconst preferred = { provider: config.provider, modelId: config.modelId, thinkingLevel: config.thinkingLevel };",
				1,
				"advisor-pi preferred snapshot",
			);
			lines = replaceLines(
				lines,
				"restoreStateFromSession(ctx, ctx.modelRegistry);",
				"restoreStateFromSession(ctx, ctx.modelRegistry);\n" +
					"\t\tif (modelResolves(ctx.modelRegistry, preferred.provider, preferred.modelId)) {\n" +
					"\t\t\tconfig.provider = preferred.provider;\n" +
					"\t\t\tconfig.modelId = preferred.modelId;\n" +
					"\t\t\tconfig.thinkingLevel = preferred.thinkingLevel;\n" +
					"\t\t}",
				1,
				"advisor-pi preferred reassert",
			);
			return lines.join("\n");
		},
	},
	{
		id: "node-notifier-main",
		package: "node-notifier",
		file: path.join("node-notifier", "package.json"),
		summary: '12.x là ESM-only (chỉ "exports", không "main") → resolver kiểu cũ tìm <pkg>/index.js, @pi-unipi/notify không load được',
		isPatched(source) {
			return JSON.parse(source).main === "./dist/index.js";
		},
		apply(source) {
			const pkg = JSON.parse(source);
			// Chỉ thêm main: resolver chuẩn ESM vẫn dùng exports, còn nhánh phân giải
			// kiểu cũ (đọc main rồi fallback index.js) không còn trỏ vào file không tồn tại.
			pkg.main = "./dist/index.js";
			return `${JSON.stringify(pkg, null, 2)}\n`;
		},
		// package.json không phải TypeScript — kiểm tra bằng JSON.parse.
		validate(text) {
			JSON.parse(text);
		},
	},
];

const checkOnly = process.argv.includes("--check");
for (const arg of process.argv.slice(2)) {
	if (arg === "--check") continue;
	if (arg === "--help" || arg === "-h") {
		say("Dùng: node scripts/pi-setup-patch-extensions.mjs [--check]");
		process.exit(0);
	}
	complain(`tham số lạ: ${arg} (chỉ có --check)`);
	process.exit(2);
}

const results = [];
let environmentError = false;

for (const patch of PATCHES) {
	const file = packageFile(patch.file);
	if (!fs.existsSync(file)) {
		complain(`[${patch.id}] không thấy ${file}`);
		complain(`          → máy này chưa cài npm:${patch.package}, hoặc pi đổi layout thư mục npm/.`);
		environmentError = true;
		continue;
	}

	const source = fs.readFileSync(file, "utf8");
	if (patch.isPatched(source)) {
		say(`[${patch.id}] đã vá trước đó — ${patch.summary}`);
		results.push({ id: patch.id, status: "already" });
		continue;
	}

	if (checkOnly) {
		complain(`[${patch.id}] CHƯA VÁ — ${patch.summary}`);
		results.push({ id: patch.id, status: "missing" });
		continue;
	}

	let patched;
	try {
		patched = patch.apply(source);
	} catch (error) {
		complain(`[${patch.id}] ${error.message}`);
		environmentError = true;
		continue;
	}

	const backup = `${file}.bak-pi-setup-patch`;
	if (!fs.existsSync(backup)) fs.copyFileSync(file, backup);

	const tmp = `${file}.tmp-pi-setup-patch-${process.pid}`;
	fs.writeFileSync(tmp, patched);
	fs.renameSync(tmp, file);

	// Tự kiểm tra: file phải parse được, phải mang guard, và guard phải thật sự có tác dụng.
	// Mặc định là parser TypeScript của Node; patch nào sửa JSON thì tự khai `validate`.
	const validate = patch.validate ?? ((text) => stripTypeScriptTypes(text, { mode: "strip" }));
	try {
		validate(fs.readFileSync(file, "utf8"));
	} catch (error) {
		fs.copyFileSync(backup, file);
		complain(`[${patch.id}] bản vá không parse được (${error.message}) → đã khôi phục file gốc từ backup.`);
		results.push({ id: patch.id, status: "reverted" });
		continue;
	}
	if (!patch.isPatched(fs.readFileSync(file, "utf8"))) {
		fs.copyFileSync(backup, file);
		complain(`[${patch.id}] ghi xong nhưng không thấy guard → đã khôi phục file gốc từ backup.`);
		results.push({ id: patch.id, status: "reverted" });
		continue;
	}

	say(`[${patch.id}] ĐÃ VÁ — ${patch.summary}`);
	say(`          ${file}`);
	results.push({ id: patch.id, status: "patched" });
}

const missing = results.filter((r) => r.status === "missing").length;
const reverted = results.filter((r) => r.status === "reverted").length;

if (!checkOnly && !environmentError && !reverted) {
	say("");
	say("→ khởi động lại pi (hoặc /reload) để dùng bản vá; chạy lại script này sau MỖI lần `pi update` package.");
}

if (environmentError || reverted) process.exit(2);
if (checkOnly && missing) process.exit(1);
process.exit(0);
