// check-docs.mjs — validate the dossier of every done/verified feature.
// Run from the repo root: node scripts/check-docs.mjs
// Exit 0 = valid, 1 = a [FAIL] occurred. A [WARN] does not fail.
//
// Split out of init.sh for the same reason check-lang.mjs and verify-gate.js were: init.sh is a file
// every project is expected to edit, and single quotes cannot be used inside `node -e '...'` at all.
import fs from "node:fs";

const DONE = ["done", "verified"];
const TIERS = ["lite", "standard", "strict"];
const WANT = "1,2,3,4,5,6,7,8,9";
const MIRROR = ["feature", "status", "tier"];

// Section 9 anchors on three fixed bold labels, the same way the section scan anchors on "## N.".
const RB_HOW = "**How to revert:**";
const RB_LABELS = [RB_HOW, "**CANNOT be reverted:**", "**Signs a rollback is needed:**"];

let bad = 0;
let n = 0;
const fail = (id, msg) => { console.log("   [FAIL] " + id + ": " + msg); bad = 1; };
const warn = (id, msg) => { console.log("   [WARN] " + id + ": " + msg); };

// FLAT YAML — only key: value. No nesting, no lists. Returns null when there is no valid block.
// Hand-written on purpose: harness-kit needs node + bash and nothing else, and this is ten lines.
function frontmatter(text) {
  const lines = text.split(/\r?\n/);
  if (lines[0].trim() !== "---") return null;
  const end = lines.indexOf("---", 1);
  if (end < 0) return null;
  const out = {};
  for (const raw of lines.slice(1, end)) {
    const line = raw.trim();
    if (!line || line.startsWith("#")) continue;
    const i = line.indexOf(":");
    if (i < 0) continue;
    let val = line.slice(i + 1);
    const c = val.indexOf(" #");                  // an end-of-line comment
    if (c >= 0) val = val.slice(0, c);
    val = val.trim().replace(/^"(.*)"$/, "$1");
    out[line.slice(0, i).trim()] = val;
  }
  return out;
}

// The body of "## N." — from that heading to the next level-2 heading.
function section(text, num) {
  const lines = text.split(/\r?\n/);
  const start = lines.findIndex((l) => new RegExp("^##\\s+" + num + "\\.").test(l));
  if (start < 0) return "";
  const rest = lines.slice(start + 1);
  const end = rest.findIndex((l) => /^##\s/.test(l));
  return (end < 0 ? rest : rest.slice(0, end)).join("\n");
}

const j = JSON.parse(fs.readFileSync("feature_list.json", "utf8"));

for (const f of j.features || []) {
  if (!DONE.includes(f.status)) continue;
  const id = f.id || "(feature with no id)";
  const tier = typeof f.tier === "string" && f.tier.trim() ? f.tier.trim().toLowerCase() : "standard";

  if (!TIERS.includes(tier)) {
    fail(id, "tier \"" + tier + "\" is outside the scale (" + TIERS.join("|") + ")");
    continue;
  }

  // lite is exempt from the dossier entirely — its evidence lives in progress.md.
  // It is NOT exempt from verify; see the tier table in CLAUDE.md.
  if (tier === "lite") {
    console.log("   (" + id + ": tier lite — no dossier required, evidence belongs in progress.md)");
    continue;
  }

  n++;
  const p = typeof f.doc === "string" ? f.doc.trim() : "";
  if (!p) { fail(id, "missing the \"doc\" field in feature_list.json"); continue; }
  if (!fs.existsSync(p)) { fail(id, "dossier not found: " + p); continue; }
  const t = fs.readFileSync(p, "utf8");

  // Section structure first: a file cut short loses its frontmatter too, and reporting the
  // missing sections is more useful than reporting the symptom.
  const nums = t.split(/\r?\n/)
    .filter((l) => /^##\s+[1-9]\./.test(l))
    .map((l) => l.match(/^##\s+([1-9])\./)[1]);
  if (nums.join(",") !== WANT) {
    fail(id, p + " must have all 9 sections ## 1. .. ## 9. in order (currently: "
             + (nums.join(",") || "no sections at all") + ")");
    continue;
  }
  if (t.includes("<TODO:")) { fail(id, p + " still contains a <TODO: placeholder"); continue; }
  if (t.includes("<!--")) { fail(id, p + " still contains uncleaned HTML guidance comments"); continue; }

  const fm = frontmatter(t);
  if (!fm) { fail(id, p + " has no YAML frontmatter block (--- on the first line)"); continue; }
  const missing = MIRROR.filter((k) => !(k in fm));
  if (missing.length) { fail(id, p + " frontmatter is missing: " + missing.join(", ")); continue; }

  // The three mirrored fields are the whole point of having a frontmatter: the old prose line
  // duplicated the same values and nothing could check it. Drift is a FAIL, not a warning.
  const mismatch = [
    ["feature", fm.feature, id],
    ["status", fm.status, f.status],
    ["tier", fm.tier, tier],
  ].find(([, got, want]) => got !== want);
  if (mismatch) {
    fail(id, p + " frontmatter " + mismatch[0] + "=\"" + mismatch[1]
             + "\" disagrees with feature_list.json (\"" + mismatch[2] + "\")");
    continue;
  }

  if (tier === "strict") {
    const body = section(t, 9);
    const miss = RB_LABELS.filter((lb) => !body.includes(lb));
    if (miss.length) { fail(id, p + " section 9 is missing: " + miss.join("  ")); continue; }
    const how = (body.split(/\r?\n/).find((l) => l.startsWith(RB_HOW)) || "").slice(RB_HOW.length).trim();
    if (!how || how === "—") {
      fail(id, p + " section 9: \"How to revert\" must have real content at tier strict, not \"—\"");
      continue;
    }
    // A field the agent declares itself must never gate itself — making this a FAIL would only
    // teach the agent to write reversible: true. The stopping rule is an L3 escalation in
    // shipping-a-feature. Its value is at incident time: one grep for what cannot be undone.
    if (fm.reversible === "false") {
      warn(id, "reversible: false at tier strict — SHIP must escalate L3 and ask the Homeowner first");
    }
  }
}

if (n === 0) console.log("   (no feature needs a dossier yet — skip)");
else if (!bad) console.log("   OK: all " + n + " features needing a dossier are valid");
process.exit(bad);
