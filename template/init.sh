#!/usr/bin/env bash
# Verification runner — {{PROJECT_NAME}}
# Dung: ./init.sh [scaffold|build|secret|all]   (mac dinh: all)
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

case "$TARGET" in
  scaffold) check_scaffold ;;
  build)    check_build ;;
  secret)   check_secret ;;
  all)      check_scaffold; check_build; check_secret ;;
  *) echo "unknown target: $TARGET"; exit 2 ;;
esac

echo ""
if [ "$FAIL" -eq 0 ]; then echo "VERIFY OK ($TARGET)"; else echo "VERIFY FAILED ($TARGET)"; fi
exit $FAIL
