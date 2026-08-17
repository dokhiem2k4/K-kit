// check-lang.mjs — the English-only invariant. See CLAUDE.md, section "Language".
//
//   node scripts/check-lang.mjs files    <skip-dirs> <max-kb>
//   node scripts/check-lang.mjs messages <text>
//
// Exit 0 = clean, 1 = something non-English was found.
//
// Split out of init.sh for the same reason verify-gate.js was split out of the bash hook: the word
// list below is data, and init.sh is a file every project is expected to edit. Keeping ~300 entries
// inline would drown the part users actually customize.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

// This file is the one place in the repo where Vietnamese words appear on purpose: the list below is
// data, not prose. Without this exclusion the validator reports itself on every run -- which it did,
// 27 lines of it, the first time this was executed. Excluding it is not a loophole: hiding text in
// the validator is the same act as deleting the validator, and init.sh already FAILs on that.
const SELF = path.resolve(fileURLToPath(import.meta.url));

// ---------------------------------------------------------------- signal 1: diacritics
// Vietnamese-distinctive code points: the Latin Extended Additional block (U+1EA0-U+1EF9, in practice
// only Vietnamese uses it), the letters a-breve / d-stroke / o-horn / u-horn, and the circumflex vowels.
// Written as \u escapes on purpose: spelling the characters out would make this very line the first
// thing the check reports.
const DIACRITIC = new RegExp("[\\u1EA0-\\u1EF9\\u0102\\u0103\\u0110\\u0111"
                           + "\\u01A0\\u01A1\\u01AF\\u01B0\\u00C2\\u00E2\\u00CA\\u00EA\\u00D4\\u00F4]");

// ---------------------------------------------------------------- signal 2: ASCII Vietnamese
// Vietnamese written without diacritics is plain ASCII, so no character class can see it. What CAN be
// seen is vocabulary: these syllables are not English words and do not collide with the identifiers a
// codebase normally contains.
//
// HOW THE LIST WAS BUILT, so it can be rebuilt rather than guessed at: take every token in a real
// Vietnamese-language version of this repo, keep the ones shaped like a Vietnamese syllable, drop
// everything present in an English dictionary, then drop everything that also appears in the English
// version of the same repo (those are identifiers and technical terms, not vocabulary).
//
// WHY A LINE NEEDS THREE DISTINCT HITS, not one. Individually several of these are plausible as an
// identifier or a proper noun somewhere in the world. Requiring three different ones on the SAME line
// is what separates prose from coincidence. Measured on 288k lines of English source (the Python
// standard library): 1 hit flags 314 lines, 2 hits flags 12 (all of them romanised Thai in a codec
// table), 3 hits flags 0. Measured against a real Vietnamese version of this repo, three hits still
// catches every affected file -- 31 of 31, with no clean file flagged. So the threshold is measured,
// not guessed, in both directions.
//
// The diacritic half is not perfectly silent either, and pretending otherwise would be the same sin
// this whole check exists to prevent: on that same 288k-line corpus it flags 2 lines, both of them a
// Latin-1 accented-character table (shlex.py). Accented letters shared with French are kept in the
// class anyway, because dropping them would blind the check to common words like "khong" and "co".
const MIN_HITS = 3;
const VN_WORDS = new Set(`
  ang anh bac bai bam bao bap bia bien biet binh boi
  bom bua buc buoc buoi cac cach cai canh cao cau cay
  cha chac cham chay chet chia chiem chieu chinh cho choi chon
  chong chot chu chua chuan chuoi chuy chuyen coi cua cuc cung
  cuoc cuoi cuon dai dang danh dao dap dau dep deu dia
  dich dien dieu dinh doan doi dong dua duoc duoi duong duy
  duyet gia giai gian giao giau gio gioi giu giua goc goi
  gom gon hai hanh het hiem hien hieu hinh hoa hoac hoan
  hoang hoat hoi huong huy kem keo ket kha khac khach khai
  khang khau khi khien kho khoa khoi khong khop khuy kich kiem
  kien kieu lach lai lan lau lech lenh lich liet loi lua
  luan luat luc luon luong luot luu mang manh mau minh moi
  mong mot muc nang nao nen neu ngam ngan ngau ngay nghe
  nghi nghia ngo ngoai ngon ngu ngui nguoc nguoi nguon nguong nguy
  nhac nham nhan nhanh nhap nhat nhau nhay nhi nhiem nhien nhiet
  nhieu nhin nho nhom nhu nhung noi nua nuot oan pha phai
  pham phan phap phat phep phi phia phien pho phoi phu phuc
  phuong phut quan quanh quen quet quy quyen quyet rac ranh rao
  rieng roi rong sach sai sao sau sinh som sua suy tac
  tach tai tay tha tham thang thao thap thay theo thi thich
  thiet thoa thoat thoi thu thua thuan thuat thuc thuoc thuong tien
  tieng tiep tiet tieu tinh toa toan toi tra trang tranh tren
  treo tri trieu trinh tro trong tru truc trung truoc truong truot
  truy tuan tuc tung tuong tuy tuyen ung uoc vai vao vay
  viec viet voi von vong vua xac xanh xay xem xin xoa
  xoay xong xuat xung xuy yeu
`.split(/\s+/).filter(Boolean));

const TOKEN = /[A-Za-z]{2,}/g;

// A line is non-English if it carries a Vietnamese diacritic, or if it carries MIN_HITS distinct
// ASCII-Vietnamese words.
function offence(line) {
  if (DIACRITIC.test(line)) return "diacritics";
  const hits = new Set();
  for (const m of line.matchAll(TOKEN)) {
    const w = m[0].toLowerCase();
    if (VN_WORDS.has(w)) hits.add(w);
  }
  return hits.size >= MIN_HITS ? [...hits].sort().join(" ") : null;
}

function report(hits, what, hint) {
  console.log("   [FAIL] non-English text in " + hits.length + " " + what + ":");
  for (const h of hits.slice(0, 15)) console.log("      " + h);
  if (hits.length > 15) console.log("      ... and " + (hits.length - 15) + " more");
  console.log("   " + hint);
  process.exit(1);
}

const mode = process.argv[2];

// ---------------------------------------------------------------- mode: files
if (mode === "files") {
  const SKIP = new Set((process.argv[3] || "").split(" ").filter(Boolean));
  const MAXB = parseInt(process.argv[4] || "512", 10) * 1024;
  // Extensions that are binary by definition. Everything else is read and sniffed for a NUL byte, so
  // an unknown text format is scanned rather than quietly skipped.
  const BIN = new Set([".png", ".jpg", ".jpeg", ".gif", ".ico", ".webp", ".pdf", ".zip", ".gz", ".tgz",
                       ".woff", ".woff2", ".ttf", ".otf", ".eot", ".mp3", ".mp4", ".mov", ".wasm",
                       ".so", ".dylib", ".dll", ".exe", ".class", ".jar", ".bin"]);
  const hits = [];
  const walk = (dir) => {
    let entries;
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
    for (const e of entries) {
      const p = path.join(dir, e.name);
      if (e.isSymbolicLink()) continue;
      if (path.resolve(p) === SELF) continue;           // the word list is data, see SELF above
      if (e.isDirectory()) { if (!SKIP.has(e.name)) walk(p); continue; }
      if (BIN.has(path.extname(e.name).toLowerCase())) continue;
      let buf;
      try {
        if (fs.statSync(p).size > MAXB) continue;
        buf = fs.readFileSync(p);
      } catch { continue; }
      if (buf.includes(0)) continue;                     // binary whatever the name says
      buf.toString("utf8").split(/\r?\n/).forEach((line, i) => {
        const why = offence(line);
        if (why) hits.push(p.replace(/^\.[\\/]/, "") + ":" + (i + 1) + " [" + why + "] " + line.trim().slice(0, 70));
      });
    }
  };
  walk(".");
  if (hits.length) {
    report(hits, "line(s)", "Everything this repo contains is written in English. See CLAUDE.md, section \"Language\".");
  }
  // Say what a green result is worth. It is a screen, not a proof: the ASCII half recognises
  // vocabulary, so Vietnamese built from words outside this list, or spread thinly enough that no
  // line reaches the threshold, still passes — and other languages are not modelled at all. Reading
  // this line as "the repo is English" is exactly the mistake "SKIP is not a pass" warns about.
  console.log("   OK: 0 non-English lines (diacritics + " + VN_WORDS.size + "-word ASCII list, >="
              + MIN_HITS + " per line). A screen, this does NOT prove the whole invariant.");
  process.exit(0);
}

// ---------------------------------------------------------------- mode: messages
if (mode === "messages") {
  const hits = (process.argv[3] || "").split(/\r?\n/).filter((l) => offence(l));
  if (hits.length) {
    report(hits.map((h) => h.trim().slice(0, 100)), "unpushed commit message line(s)",
           "Reword them before pushing: git rebase -i @{u}");
  }
  console.log("   OK: unpushed commit messages are English");
  process.exit(0);
}

console.log("   [FAIL] check-lang.mjs: unknown mode \"" + mode + "\"");
process.exit(1);
