// verify-gate.js — the logic half of the hook. Reads the event JSON on stdin, prints its
// decision to stdout. Invoked by hooks/verify-gate: node verify-gate.js <mode> <marker-dir> < event.json
//
// Kept in its own file for one specific reason: if this script lived in a bash heredoc,
// the heredoc would take over stdin and node could no longer read the event JSON.
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

// STATE files, not code. Editing them does not invalidate an earlier verify run.
const STATE_FILES = new Set(["feature_list.json", "progress.md", "session-handoff.md", "CLAUDE.md"]);
const isStateFile = STATE_FILES.has(base) || /(^|\/)docs\//.test(filePath);

// The string "VERIFY OK" is the CONTRACT between init.sh and this gate. The gate has no
// other way to know a verify run succeeded. If init.sh stops printing it, the marker is
// never set, and the gate silently flips from fail-open to fail-closed: it blocks every
// write of done with nobody understanding why.
//
// So before it REFUSES, the gate must check itself: does this project have an init.sh, and
// can that init.sh print "VERIFY OK"? Without that ability the gate has no right to refuse.
const CONTRACT = "VERIFY OK";
function contractHolds(projectDir) {
  const p = path.join(projectDir, "init.sh");
  try {
    if (!fs.existsSync(p)) return { ok: false, why: "not found: " + p };
    if (!fs.readFileSync(p, "utf8").includes(CONTRACT)) {
      return { ok: false, why: p + " never prints \"" + CONTRACT + "\" — the contract with verify-gate is broken" };
    }
    return { ok: true };
  } catch (e) {
    return { ok: false, why: "cannot read " + p + ": " + e.message };
  }
}

// ---------------------------------------------------------------- post-bash
if (mode === "post-bash") {
  const r = inp.tool_response;
  const text = typeof r === "string" ? r : JSON.stringify(r || "");

  // Running init.sh with neither VERIFY OK nor VERIFY FAILED in the output = broken contract.
  // Warn right here, rather than waiting until the gate blocks the wrong thing.
  const cmd = String((inp.tool_input || {}).command || "");
  if (/init\.sh/.test(cmd) && !/VERIFY (OK|FAILED)/.test(text)) {
    process.stderr.write(
      "harness-kit verify-gate: ran `" + cmd.slice(0, 80) + "` but the output contains neither " +
      "\"VERIFY OK\" nor \"VERIFY FAILED\".\ninit.sh must print one of those two strings — the gate relies on " +
      "them to know that verify ran and how it went. Without them the gate protects nothing.\n"
    );
  }

  // VERIFY FAILED must CLEAR the marker: a red run after a green one means the current
  // state is not green. If we only set and never cleared, an agent could go green once,
  // then break everything and still hold the marker.
  if (/VERIFY FAILED/.test(text)) { try { fs.unlinkSync(marker); } catch {} process.exit(0); }
  if (/VERIFY OK/.test(text)) {
    try { fs.writeFileSync(marker, JSON.stringify({ at: new Date().toISOString(), cwd: inp.cwd || "" })); } catch {}
  }
  process.exit(0);
}

// ---------------------------------------------------------------- post-edit
if (mode === "post-edit") {
  // The code just changed -> the earlier VERIFY OK proves nothing about the current code.
  // This is what closes the loophole: "run verify green first, edit code after, then mark done".
  if (filePath && !isStateFile) { try { fs.unlinkSync(marker); } catch {} }
  process.exit(0);
}

// ---------------------------------------------------------------- pre-edit
if (mode !== "pre-edit") process.exit(0);
if (base !== "feature_list.json") process.exit(0);

// Collect every chunk of text ABOUT TO BE written to the file.
const incoming = [];
if (typeof toolInput.content === "string") incoming.push(toolInput.content);
if (typeof toolInput.new_string === "string") incoming.push(toolInput.new_string);
for (const e of (toolInput.edits || [])) if (e && typeof e.new_string === "string") incoming.push(e.new_string);
const outgoing = typeof toolInput.old_string === "string" ? toolInput.old_string : "";

const DONE = /"status"\s*:\s*"(done|verified)"/;
const addsDone = incoming.some((t) => DONE.test(t)) && !DONE.test(outgoing);
if (!addsDone) process.exit(0);

// For Write (whole-file overwrite): only block if the NUMBER of done features GREW versus
// what is on disk. Rewriting the same state (after reformatting the JSON, say) is not a new claim.
if (typeof toolInput.content === "string") {
  const count = (obj) => (obj.features || []).filter((f) => ["done", "verified"].includes(f.status)).length;
  try {
    const before = count(JSON.parse(fs.readFileSync(filePath, "utf8")));
    const after = count(JSON.parse(toolInput.content));
    if (after <= before) process.exit(0);
  } catch { /* unreadable/unparseable -> keep checking, do not let it through */ }
}

let hasMarker = false;
try { hasMarker = fs.existsSync(marker); } catch {}
if (hasMarker) process.exit(0);

// About to refuse. CHECK THE CONTRACT FIRST: if the project has no init.sh, or that init.sh
// cannot print "VERIFY OK", then no path exists for the agent to satisfy this gate. Refusing
// at that point is not a gate — it is a hard lock.
// feature_list.json lives at the repo root by convention, so its dirname is the project dir.
const projectDir = path.dirname(path.resolve(filePath));
const contract = contractHolds(projectDir);
if (!contract.ok) {
  process.stderr.write(
    "harness-kit verify-gate: LETTING THROUGH instead of blocking, because there is no way to verify.\n" +
    "Reason: " + contract.why + "\n" +
    "The gate can only block when init.sh prints \"" + CONTRACT + "\" on success. " +
    "Fix init.sh (or run verify by hand and paste the output) and the gate will work again.\n"
  );
  process.exit(0);
}

const reason =
  "BLOCKED by harness-kit verify-gate.\n\n" +
  "You are writing status done/verified into feature_list.json, but in this session there has " +
  "been NO run of ./init.sh returning VERIFY OK — or there was one, but code was edited afterwards " +
  "so that result no longer proves anything.\n\n" +
  "Evidence first, claims second:\n" +
  "  1. run ./init.sh (the part named in the feature's `verify` field)\n" +
  "  2. read the output, confirm VERIFY OK\n" +
  "  3. paste the output into progress.md\n" +
  "  4. only then write the status\n\n" +
  "If init.sh reports that checks were SKIPped: those are checks that DID NOT RUN, not passes.\n" +
  "See skill harness-kit:verifying-a-feature.";

process.stdout.write(JSON.stringify({
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: reason,
  },
}));
