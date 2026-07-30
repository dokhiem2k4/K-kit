// verify-gate.js — phan logic cua hook. Doc JSON su kien tren stdin, in quyet dinh ra stdout.
// Duoc goi boi hooks/verify-gate: node verify-gate.js <mode> <marker-dir> < event.json
//
// Tach ra file rieng vi mot ly do cu the: neu nhung script nay vao heredoc trong bash thi
// heredoc chiem mat stdin, va node khong con doc duoc JSON su kien nua.
const fs = require("fs");
const path = require("path");
const [mode, markerDir] = process.argv.slice(2);

let inp = {};
try { inp = JSON.parse(fs.readFileSync(0, "utf8")); } catch { process.exit(0); }

const sid = String(inp.session_id || "nosession").replace(/[^A-Za-z0-9_.-]/g, "_");
const marker = path.join(markerDir, sid);
const toolInput = inp.tool_input || {};
const filePath = String(toolInput.file_path || "");
const base = path.basename(filePath);

// File STATE, khong phai code. Sua chung khong lam mot lan verify cu thanh vo nghia.
const STATE_FILES = new Set(["feature_list.json", "progress.md", "session-handoff.md", "CLAUDE.md"]);
const isStateFile = STATE_FILES.has(base) || /(^|\/)docs\//.test(filePath);

// Chuoi "VERIFY OK" la HOP DONG giua init.sh va gate nay. Gate khong co cach nao khac
// de biet mot lan verify da thanh cong. Neu init.sh khong con in chuoi do, marker khong
// bao gio duoc dat, va gate am tham chuyen tu fail-open thanh fail-closed: chan sach moi
// thao tac ghi done ma khong ai hieu tai sao.
//
// Nen truoc khi TU CHOI, gate phai tu kiem: du an nay co init.sh khong, va init.sh do co
// kha nang in "VERIFY OK" khong. Khong co kha nang do -> gate khong co quyen tu choi.
const CONTRACT = "VERIFY OK";
function contractHolds(projectDir) {
  const p = path.join(projectDir, "init.sh");
  try {
    if (!fs.existsSync(p)) return { ok: false, why: "khong tim thay " + p };
    if (!fs.readFileSync(p, "utf8").includes(CONTRACT)) {
      return { ok: false, why: p + " khong in chuoi \"" + CONTRACT + "\" — hop dong voi verify-gate da vo" };
    }
    return { ok: true };
  } catch (e) {
    return { ok: false, why: "khong doc duoc " + p + ": " + e.message };
  }
}

// ---------------------------------------------------------------- post-bash
if (mode === "post-bash") {
  const r = inp.tool_response;
  const text = typeof r === "string" ? r : JSON.stringify(r || "");

  // Chay init.sh ma output khong co ca VERIFY OK lan VERIFY FAILED = hop dong da vo.
  // Canh bao ngay tai day, khong doi den luc gate chan nham roi moi phat hien.
  const cmd = String((inp.tool_input || {}).command || "");
  if (/init\.sh/.test(cmd) && !/VERIFY (OK|FAILED)/.test(text)) {
    process.stderr.write(
      "harness-kit verify-gate: da chay `" + cmd.slice(0, 80) + "` nhung output khong co " +
      "\"VERIFY OK\" hay \"VERIFY FAILED\".\ninit.sh phai in mot trong hai chuoi do — gate dua vao " +
      "chung de biet verify da chay va ket qua ra sao. Khong co chung thi gate khong bao ve duoc gi.\n"
    );
  }

  // VERIFY FAILED phai HUY marker: mot lan chay do sau mot lan chay xanh nghia la
  // trang thai hien tai khong xanh. Neu chi set ma khong huy, agent chay xanh mot lan
  // roi lam vo moi thu van con marker.
  if (/VERIFY FAILED/.test(text)) { try { fs.unlinkSync(marker); } catch {} process.exit(0); }
  if (/VERIFY OK/.test(text)) {
    try { fs.writeFileSync(marker, JSON.stringify({ at: new Date().toISOString(), cwd: inp.cwd || "" })); } catch {}
  }
  process.exit(0);
}

// ---------------------------------------------------------------- post-edit
if (mode === "post-edit") {
  // Code vua doi -> lan VERIFY OK truoc do khong con chung minh gi ve code hien tai.
  // Day la thu chan duong lach: "chay verify xanh truoc, sua code sau, roi danh done".
  if (filePath && !isStateFile) { try { fs.unlinkSync(marker); } catch {} }
  process.exit(0);
}

// ---------------------------------------------------------------- pre-edit
if (mode !== "pre-edit") process.exit(0);
if (base !== "feature_list.json") process.exit(0);

// Gom moi doan text SAP duoc ghi vao file.
const incoming = [];
if (typeof toolInput.content === "string") incoming.push(toolInput.content);
if (typeof toolInput.new_string === "string") incoming.push(toolInput.new_string);
for (const e of (toolInput.edits || [])) if (e && typeof e.new_string === "string") incoming.push(e.new_string);
const outgoing = typeof toolInput.old_string === "string" ? toolInput.old_string : "";

const DONE = /"status"\s*:\s*"(done|verified)"/;
const addsDone = incoming.some((t) => DONE.test(t)) && !DONE.test(outgoing);
if (!addsDone) process.exit(0);

// Voi Write (ghi de ca file): chi chan neu SO feature done TANG so voi tren dia.
// Ghi lai nguyen trang thai cu (vi du sau khi format lai JSON) khong phai tuyen bo moi.
if (typeof toolInput.content === "string") {
  const count = (obj) => (obj.features || []).filter((f) => ["done", "verified"].includes(f.status)).length;
  try {
    const before = count(JSON.parse(fs.readFileSync(filePath, "utf8")));
    const after = count(JSON.parse(toolInput.content));
    if (after <= before) process.exit(0);
  } catch { /* khong doc/parse duoc -> kiem tiep, khong cho qua */ }
}

let hasMarker = false;
try { hasMarker = fs.existsSync(marker); } catch {}
if (hasMarker) process.exit(0);

// Sap tu choi. Kiem hop dong TRUOC DA: neu du an khong co init.sh, hoac init.sh khong
// the in "VERIFY OK", thi khong ton tai duong nao de agent thoa man gate nay. Tu choi
// luc do khong phai la gate — la khoa cung.
// feature_list.json nam o repo root theo quy uoc, nen dirname cua no chinh la project dir.
const projectDir = path.dirname(path.resolve(filePath));
const contract = contractHolds(projectDir);
if (!contract.ok) {
  process.stderr.write(
    "harness-kit verify-gate: CHO QUA thay vi chan, vi khong co duong nao de verify.\n" +
    "Ly do: " + contract.why + "\n" +
    "Gate chi chan duoc khi init.sh in \"" + CONTRACT + "\" luc thanh cong. " +
    "Sua init.sh (hoac chay verify bang tay va dan output) roi gate se hoat dong lai.\n"
  );
  process.exit(0);
}

const reason =
  "CHAN boi harness-kit verify-gate.\n\n" +
  "Ban dang ghi status done/verified vao feature_list.json, nhung trong phien nay CHUA co " +
  "lan chay nao cua ./init.sh tra ve VERIFY OK — hoac da co, nhung sau do code bi sua nen " +
  "ket qua do khong con chung minh gi.\n\n" +
  "Bang chung truoc, tuyen bo sau:\n" +
  "  1. chay ./init.sh (phan lien quan trong field `verify` cua feature)\n" +
  "  2. doc output, xac nhan VERIFY OK\n" +
  "  3. dan output vao progress.md\n" +
  "  4. roi moi ghi status\n\n" +
  "Neu init.sh bao con check bi SKIP: do la check KHONG CHAY, khong phai pass.\n" +
  "Xem skill harness-kit:verifying-a-feature.";

process.stdout.write(JSON.stringify({
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: reason,
  },
}));
