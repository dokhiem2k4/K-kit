// check-docs.mjs — validate the dossier of every done/verified feature.
// Run from the repo root: node scripts/check-docs.mjs
// Exit 0 = valid, 1 = a [FAIL] occurred.
//
// Split out of init.sh for the same reason check-lang.mjs and verify-gate.js were: init.sh is a file
// every project is expected to edit, and single quotes cannot be used inside `node -e '...'` at all.
// This file is about to grow a frontmatter parser and tier branches; that does not belong inline.
import fs from "node:fs";

const DONE = ["done", "verified"];
const WANT = "1,2,3,4,5,6,7,8";

let bad = 0;
let n = 0;
const fail = (id, msg) => { console.log("   [FAIL] " + id + ": " + msg); bad = 1; };

const j = JSON.parse(fs.readFileSync("feature_list.json", "utf8"));

for (const f of j.features || []) {
  if (!DONE.includes(f.status)) continue;
  n++;
  const id = f.id || "(feature with no id)";
  const p = typeof f.doc === "string" ? f.doc.trim() : "";
  if (!p) { fail(id, "missing the \"doc\" field in feature_list.json"); continue; }
  if (!fs.existsSync(p)) { fail(id, "dossier not found: " + p); continue; }
  const t = fs.readFileSync(p, "utf8");

  const nums = t.split(/\r?\n/)
    .filter((l) => /^##\s+[1-8]\./.test(l))
    .map((l) => l.match(/^##\s+([1-8])\./)[1]);
  if (nums.join(",") !== WANT) {
    fail(id, p + " must have all 8 sections ## 1. .. ## 8. in order (currently: "
             + (nums.join(",") || "no sections at all") + ")");
    continue;
  }
  if (t.includes("<TODO:")) { fail(id, p + " still contains a <TODO: placeholder"); continue; }
  if (t.includes("<!--")) { fail(id, p + " still contains uncleaned HTML guidance comments"); continue; }
}

if (n === 0) console.log("   (no feature is done/verified yet — skip)");
else if (!bad) console.log("   OK: all " + n + " done/verified features have a valid dossier");
process.exit(bad);
