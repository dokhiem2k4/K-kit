// check-state.mjs — validate that progress.md does not carry a full, untagged Log entry for a
// feature that has already shipped (done/verified). A shipped feature's entry must be moved into
// progress-archive.md, leaving a one-line pointer in progress.md tagged with SHIPPED_TAG. This
// keeps progress.md bounded by "features currently in flight," not by the project's age.
// Run from the repo root: node scripts/check-state.mjs
// Exit 0 = valid, 1 = a [FAIL] occurred.
import fs from "node:fs";

const DONE = ["done", "verified"];
const SHIPPED_TAG = "(shipped — see progress-archive.md)";

let bad = 0;
let checked = 0;
const fail = (id, msg) => { console.log("   [FAIL] " + id + ": " + msg); bad = 1; };

const j = JSON.parse(fs.readFileSync("feature_list.json", "utf8"));
const progress = fs.existsSync("progress.md") ? fs.readFileSync("progress.md", "utf8") : "";
const lines = progress.split(/\r?\n/);

for (const f of j.features || []) {
  if (!DONE.includes(f.status)) continue;
  const id = f.id;
  if (typeof id !== "string" && typeof id !== "number") continue;

  // The heading convention is "### <date> — <id>: <title>". A trailing colon after the id keeps
  // "F1" from matching inside "F10" — the id must be followed immediately by ":".
  const marker = "— " + id + ":";
  const headingLines = lines.filter((l) => l.startsWith("###") && l.includes(marker));
  if (headingLines.length === 0) continue; // already archived away entirely, or never had an entry

  checked++;
  const untagged = headingLines.filter((l) => !l.includes(SHIPPED_TAG));
  if (untagged.length > 0) {
    fail(
      id,
      "progress.md still carries a full Log entry after shipping — move it into progress-archive.md " +
      "and leave a pointer line ending in \"" + SHIPPED_TAG + "\" (found: \"" + untagged[0].trim() + "\")",
    );
  }
}

if (checked === 0) console.log("   (nothing to archive yet)");
else if (!bad) console.log("   OK: " + checked + " shipped feature(s) with a Log entry are all archived or pointer-tagged");
process.exit(bad);
