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
SKIPPED=0
step() { echo ""; echo "==> $1"; }
# Check khong chay duoc thi phai dem — mot lan chay toan SKIP khong duoc doc thanh "da kiem het".
skip() { echo "   (SKIP: $1)"; SKIPPED=$((SKIPPED + 1)); }

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

# package.json co script <name> khong?
# KHONG duoc dua vao exit code cua `npm run <name>` de doan: no tra non-zero ca khi script
# thieu LAN khi script chay va fail. Gop hai truong hop do lai la cach mot lan lint do
# di qua gate ma khong ai biet.
has_script() {
  node -e '
const p = require("./package.json");
process.exit((p.scripts && p.scripts[process.argv[1]]) ? 0 : 1);
' "$1" 2>/dev/null
}

# run_script <name> [required]
#   script thieu  -> SKIP (co dem), tru khi required=yes thi FAIL
#   script fail   -> FAIL, va IN NGUYEN output (dung nuot stderr — ban can biet vi sao)
run_script() {
  local name="$1" required="${2:-no}"
  if ! command -v node >/dev/null 2>&1; then skip "khong co node — khong biet package.json co script \"$name\" khong"; return; fi
  if ! has_script "$name"; then
    if [ "$required" = "yes" ]; then echo "   [FAIL] thieu script \"$name\" trong package.json"; FAIL=1
    else skip "khong co script \"$name\" trong package.json"; fi
    return
  fi
  echo "   -> npm run $name"
  if npm run --silent "$name"; then echo "   OK: $name"; else echo "   [FAIL] $name"; FAIL=1; fi
}

# CUSTOMIZE: doi sang lenh build/test thuc te cua stack (npm/pnpm/cargo/go/gradle/dotnet...)
check_build() {
  step "BUILD / TYPECHECK / LINT / TEST"
  if [ ! -f package.json ]; then
    skip "khong phai node project — CUSTOMIZE check_build cho stack cua ban"
    echo "   (khong lenh nao chay — day KHONG phai pass)"
    return
  fi

  run_script lint

  # typecheck: uu tien script cua project; khong co thi dung tsc LOCAL neu co tsconfig.
  # Khong dung `npx --yes tsc`: no tai typescript tu mang, cham va co the khac ban project.
  if has_script typecheck; then
    run_script typecheck
  elif [ -f tsconfig.json ] && [ -x node_modules/.bin/tsc ]; then
    echo "   -> node_modules/.bin/tsc --noEmit"
    if node_modules/.bin/tsc --noEmit; then echo "   OK: typecheck (tsc)"; else echo "   [FAIL] typecheck (tsc)"; FAIL=1; fi
  else
    skip "khong co script \"typecheck\" va khong co tsc local"
  fi

  run_script build yes   # build la bat buoc: khong build duoc thi khong the done
  run_script test
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
  [ "$scanned" -eq 0 ] && { skip "chua co client bundle nao de quet (${CLIENT_DIRS[*]})"; return; }
  [ "$found" -eq 1 ] && FAIL=1 || echo "   OK: 0 secret trong client bundle"
}

# Moi feature done/verified phai co dossier docs/features/<ID>-<slug>.md du 8 muc.
check_docs() {
  step "FEATURE DOCS (dossier cho feature done/verified)"
  command -v node >/dev/null 2>&1 || { skip "khong co node — khong xac nhan duoc dossier"; return; }
  [ -f feature_list.json ] || { skip "khong co feature_list.json"; return; }
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

# ==== HOP DONG VOI verify-gate — KHONG DUOC DOI HAI CHUOI DUOI DAY =====================
# hooks/verify-gate doc output cua file nay de biet mot lan verify da chay va ket qua ra sao:
#   "VERIFY OK"     -> dat marker, cho phep ghi status done vao feature_list.json
#   "VERIFY FAILED" -> huy marker
# Doi/xoa hai chuoi nay se lam gate mat kha nang quan sat. Gate se phat hien va CHO QUA
# (kem canh bao stderr) chu khong khoa cung phien lam viec — nhung luc do no khong con
# bao ve gi nua. tests/run-tests.sh co assertion khoa hai chuoi nay lai.
# =======================================================================================
echo ""
if [ "$FAIL" -ne 0 ]; then
  echo "VERIFY FAILED ($TARGET)"
elif [ "$SKIPPED" -gt 0 ]; then
  # Xanh nhung khong day du. Noi ro, dung de mot lan chay toan SKIP duoc dan vao
  # progress.md nhu la bang chung "all green".
  echo "VERIFY OK ($TARGET) — nhung $SKIPPED check bi SKIP, KHONG phai da kiem het."
  echo "Truoc khi danh done: hoac lam cho check do chay duoc, hoac chay tay va dan output."
else
  echo "VERIFY OK ($TARGET) — moi check deu chay."
fi
exit $FAIL
