#!/usr/bin/env bash
# Verification runner — {{PROJECT_NAME}}
# Dung: ./init.sh [scaffold|build|secret|docs|all]   (mac dinh: all)
# CUSTOMIZE: sua bien CONFIG + ham check_build/check_secret theo stack cua ban.
# Fail-fast: build/typecheck hard-error dung ngay trong tung target (set -e semantics);
# runner tong hop FAIL de bao cao het cac check con lai.
set -uo pipefail
cd "$(dirname "$0")"
TARGET="${1:-all}"
FAIL=0
step() { echo ""; echo "==> $1"; }

# ---- CONFIG (sua theo project) ----------------------------------------------
# Thu muc code chay tren client (bundle KHONG duoc chua secret): web dist, extension dist, mobile build...
CLIENT_DIRS=("dist" "build" "web/.next" "extension/dist")
# Pattern secret khong duoc lo trong client bundle:
SECRET_REGEX='service_role|BEGIN [A-Z ]*PRIVATE KEY|sk-[A-Za-z0-9]{20}|AKIA[0-9A-Z]{16}|xox[baprs]-'
# -----------------------------------------------------------------------------

check_scaffold() {
  step "SCAFFOLD"
  [ -f package.json ] && echo "   package.json: OK" || echo "   (chua co package.json — sua neu stack khac)"
  [ -f .env.example ] && echo "   .env.example: OK" || echo "   (chua co .env.example)"
  [ -f README.md ]    && echo "   README.md: OK"    || echo "   (chua co README.md)"
}

# CUSTOMIZE: doi sang lenh build/test thuc te cua stack (npm/pnpm/cargo/go/gradle/dotnet...)
check_build() {
  step "BUILD / TYPECHECK / LINT / TEST"
  if [ ! -f package.json ]; then echo "   (khong phai node project — sua check_build)"; return; fi
  npm run --silent lint      2>/dev/null || echo "   (no lint script)"
  npm run --silent typecheck 2>/dev/null || npx --yes tsc --noEmit 2>/dev/null || echo "   (no typecheck)"
  npm run --silent build     || { echo "   [FAIL] build"; FAIL=1; }
  npm run --silent test      2>/dev/null || echo "   (no test script)"
}

# P0 invariant: bundle client KHONG duoc lo secret.
check_secret() {
  step "SECRET LEAK: grep client bundle"
  local found=0 scanned=0
  for d in "${CLIENT_DIRS[@]}"; do
    [ -d "$d" ] || continue
    scanned=1
    if grep -RniE "$SECRET_REGEX" "$d" 2>/dev/null; then
      echo "   [FAIL] SECRET trong $d — KHONG duoc ship"; found=1
    fi
  done
  [ "$scanned" -eq 0 ] && { echo "   (chua co bundle nao — skip)"; return; }
  [ "$found" -eq 1 ] && FAIL=1 || echo "   OK: 0 secret trong client bundle"
}

# Moi feature done/verified phai co dossier docs/features/<ID>-<slug>.md du 8 muc.
check_docs() {
  step "FEATURE DOCS (dossier cho feature done/verified)"
  command -v node >/dev/null 2>&1 || { echo "   (khong co node — SKIP, khong xac nhan duoc)"; return; }
  [ -f feature_list.json ] || { echo "   (khong co feature_list.json — skip)"; return; }
  node -e '
const fs = require("fs");
const j = JSON.parse(fs.readFileSync("feature_list.json", "utf8"));
const DONE = ["done", "verified"];
const WANT = "1,2,3,4,5,6,7,8";
let bad = 0, n = 0;
const fail = (id, msg) => { console.log("   [FAIL] " + id + ": " + msg); bad = 1; };
for (const f of (j.features || [])) {
  if (!DONE.includes(f.status)) continue;
  n++;
  const id = f.id || "(feature khong co id)";
  const p = typeof f.doc === "string" ? f.doc.trim() : "";
  if (!p) { fail(id, "thieu field \"doc\" trong feature_list.json"); continue; }
  if (!fs.existsSync(p)) { fail(id, "khong tim thay dossier " + p); continue; }
  const t = fs.readFileSync(p, "utf8");
  const nums = t.split(/\r?\n/)
    .filter(l => /^##\s+[1-8]\./.test(l))
    .map(l => l.match(/^##\s+([1-8])\./)[1]);
  if (nums.join(",") !== WANT) {
    fail(id, p + " phai co du 8 muc ## 1. .. ## 8. dung thu tu (dang co: " + (nums.join(",") || "khong co muc nao") + ")");
    continue;
  }
  if (t.indexOf("<TODO:") >= 0) { fail(id, p + " con placeholder <TODO:"); continue; }
  if (t.indexOf("<!--") >= 0) { fail(id, p + " con chu thich huong dan HTML chua xoa"); continue; }
}
if (n === 0) console.log("   (chua feature nao done/verified — skip)");
else if (!bad) console.log("   OK: " + n + " feature done/verified deu co dossier hop le");
process.exit(bad);
' || FAIL=1
}

case "$TARGET" in
  scaffold) check_scaffold ;;
  build)    check_build ;;
  secret)   check_secret ;;
  docs)     check_docs ;;
  all)      check_scaffold; check_build; check_secret; check_docs ;;
  *) echo "unknown target: $TARGET"; exit 2 ;;
esac

echo ""
if [ "$FAIL" -eq 0 ]; then echo "VERIFY OK ($TARGET)"; else echo "VERIFY FAILED ($TARGET)"; fi
exit $FAIL
