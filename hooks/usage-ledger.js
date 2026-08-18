// usage-ledger.js — append a cumulative token-usage snapshot after every agent turn.
// Invoked by hooks/usage-ledger: node usage-ledger.js < event.json
//
// Reads the Stop event JSON from stdin (fields: cwd, session_id, transcript_path). Sums every
// message.usage object found in the transcript and appends ONE row to .claude/usage-ledger.jsonl —
// a running total as of now, not a delta. A session with 40 Stop events produces 40 rows, each
// superseding the last for that sessionId.
//
// Never denies anything. Any error, or a transcript with zero usage objects, writes nothing and
// exits 0 silently — a silent ledger is an honest signal (the expected shape disappeared), not a
// crash or a row of fabricated zeros.
const fs = require("fs");
const path = require("path");

let inp = {};
try { inp = JSON.parse(fs.readFileSync(0, "utf8")); } catch { process.exit(0); }

const cwd = String(inp.cwd || process.cwd());
const sessionId = String(inp.session_id || "");
const transcriptPath = String(inp.transcript_path || "");

// Precondition: only track usage inside a harness project.
if (!fs.existsSync(path.join(cwd, "feature_list.json"))) process.exit(0);
if (!transcriptPath || !fs.existsSync(transcriptPath)) process.exit(0);

let lines;
try { lines = fs.readFileSync(transcriptPath, "utf8").split("\n").filter(Boolean); } catch { process.exit(0); }

const totals = { input: 0, output: 0, cacheRead: 0, cacheCreation: 0 };
let sawUsage = false;

for (const l of lines) {
  let entry;
  try { entry = JSON.parse(l); } catch { continue; } // a transcript being actively written to can end mid-line
  const usage = entry && entry.message && entry.message.usage;
  if (!usage || typeof usage !== "object") continue;
  sawUsage = true;
  totals.input += Number(usage.input_tokens) || 0;
  totals.output += Number(usage.output_tokens) || 0;
  totals.cacheRead += Number(usage.cache_read_input_tokens) || 0;
  totals.cacheCreation += Number(usage.cache_creation_input_tokens) || 0;
}

// Graceful degradation: if the transcript's expected usage shape has disappeared (a schema change
// this hook has no contract against), write nothing rather than a row of fabricated zeros.
if (!sawUsage) process.exit(0);

const row = JSON.stringify({
  t: new Date().toISOString(),
  sessionId,
  input: totals.input,
  output: totals.output,
  cacheRead: totals.cacheRead,
  cacheCreation: totals.cacheCreation,
});

try {
  const ledgerDir = path.join(cwd, ".claude");
  fs.mkdirSync(ledgerDir, { recursive: true });
  fs.appendFileSync(path.join(ledgerDir, "usage-ledger.jsonl"), row + "\n");
} catch { /* best-effort — never crash the Stop event over a ledger write failure */ }

process.exit(0);
