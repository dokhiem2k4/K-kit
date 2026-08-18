// session-checkpoint.js — append a breadcrumb line after every Edit/Write/MultiEdit.
// Invoked by hooks/session-checkpoint: node session-checkpoint.js <marker-dir> < event.json
//
// Reads the PostToolUse event JSON from stdin. Writes ONE JSON line to a project-keyed log:
//   {"t": ISO timestamp, "tool": "Edit"|"Write"|"MultiEdit", "target": relative file path}
//
// Never denies anything — this hook only observes. Any error (unreadable event JSON, unwritable
// temp dir) exits 0 silently; a checkpoint log is a convenience, not a gate.
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const markerDir = process.argv[2];

let inp = {};
try { inp = JSON.parse(fs.readFileSync(0, "utf8")); } catch { process.exit(0); }

const cwd = String(inp.cwd || process.cwd());
const toolName = String(inp.tool_name || "");
const toolInput = inp.tool_input || {};

// Precondition: only log inside a harness project. Keeps this hook from polluting temp for every
// unrelated Claude Code project the user works in.
if (!fs.existsSync(path.join(cwd, "feature_list.json"))) process.exit(0);

if (!["Edit", "Write", "MultiEdit"].includes(toolName)) process.exit(0);

const filePath = String(toolInput.file_path || "");
if (!filePath) process.exit(0);

let target = filePath;
try {
  const rel = path.relative(cwd, filePath);
  if (rel) target = rel;
} catch { /* keep the raw path */ }

const hash = crypto.createHash("sha1").update(path.resolve(cwd)).digest("hex").slice(0, 16);
const logFile = path.join(markerDir, "checkpoint-" + hash + ".jsonl");

const line = JSON.stringify({ t: new Date().toISOString(), tool: toolName, target });

// Size safety net: the read-side truncation in hooks/session-start only runs at SessionStart, so a
// single very long session that never touches session-handoff.md could otherwise grow this file
// without bound. Cap it here too, independently.
try {
  let existing = [];
  if (fs.existsSync(logFile)) {
    existing = fs.readFileSync(logFile, "utf8").split("\n").filter(Boolean);
  }
  if (existing.length >= 500) existing = existing.slice(Math.floor(existing.length / 2));
  existing.push(line);
  fs.writeFileSync(logFile, existing.join("\n") + "\n");
} catch { /* best-effort — never block the edit that just happened */ }

process.exit(0);
