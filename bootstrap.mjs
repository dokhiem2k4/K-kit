#!/usr/bin/env node
// harness-kit bootstrap — copy the template harness into a target project and fill tokens.
// Usage:
//   node bootstrap.mjs --target /path/to/project --name "My Project" \
//        [--tagline "one-liner"] [--stack "Next.js + Postgres"] \
//        [--blueprint docs/specs/blueprint.md] [--memory-dir .claude/memory/] [--force]
//
// Non-clobbering by default: existing files are skipped (reported) unless --force.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const TEMPLATE_DIR = path.join(__dirname, 'template');

function parseArgs(argv) {
  const out = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const key = a.slice(2);
      const next = argv[i + 1];
      if (next === undefined || next.startsWith('--')) { out[key] = true; }
      else { out[key] = next; i++; }
    } else out._.push(a);
  }
  return out;
}

const args = parseArgs(process.argv.slice(2));

if (args.help || !args.target || !args.name) {
  console.log(`harness-kit bootstrap
Required: --target <dir>  --name "<Project Name>"
Optional: --tagline "..."  --stack "..."  --blueprint <path>  --memory-dir <path>  --force  --dry-run`);
  process.exit(args.help ? 0 : 1);
}

const target = path.resolve(String(args.target));
if (!fs.existsSync(target)) { console.error(`target not found: ${target}`); process.exit(1); }

const today = new Date().toISOString().slice(0, 10);
const tokens = {
  '{{PROJECT_NAME}}': String(args.name),
  '{{TAGLINE}}': String(args.tagline || 'TODO: mô tả 1 dòng đề tài.'),
  '{{STACK}}': String(args.stack || 'TODO: tech stack'),
  '{{BLUEPRINT_PATH}}': String(args.blueprint || 'docs/specs/blueprint.md'),
  '{{MEMORY_DIR}}': String(args['memory-dir'] || '.claude/memory/'),
  '{{DATE}}': today,
};

function fill(text) {
  let out = text;
  for (const [k, v] of Object.entries(tokens)) out = out.split(k).join(v);
  return out;
}

// Binary-ish extensions we copy verbatim (none in this template, but future-proof).
const BINARY = new Set(['.png', '.jpg', '.jpeg', '.gif', '.ico', '.pdf', '.zip', '.woff', '.woff2']);

function walk(dir) {
  const entries = [];
  for (const name of fs.readdirSync(dir)) {
    const full = path.join(dir, name);
    if (fs.statSync(full).isDirectory()) entries.push(...walk(full));
    else entries.push(full);
  }
  return entries;
}

const dryRun = !!args['dry-run'];
const files = walk(TEMPLATE_DIR);
let written = 0, skipped = 0;

for (const src of files) {
  const rel = path.relative(TEMPLATE_DIR, src);
  const dest = path.join(target, rel);
  if (fs.existsSync(dest) && !args.force) { console.log(`  SKIP (exists)  ${rel}`); skipped++; continue; }
  const ext = path.extname(src).toLowerCase();
  if (dryRun) { console.log(`  WOULD WRITE    ${rel}`); written++; continue; }
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  if (BINARY.has(ext)) fs.copyFileSync(src, dest);
  else fs.writeFileSync(dest, fill(fs.readFileSync(src, 'utf8')));
  if (rel.endsWith('init.sh')) { try { fs.chmodSync(dest, 0o755); } catch {} }
  console.log(`  WRITE          ${rel}`);
  written++;
}

console.log(`\nharness-kit → ${target}`);
console.log(`  project : ${tokens['{{PROJECT_NAME}}']}`);
console.log(`  written : ${written}   skipped(existing): ${skipped}${dryRun ? '  [dry-run]' : ''}`);
console.log(`\nNext:
  1) Điền Blueprint tại ${tokens['{{BLUEPRINT_PATH}}']} (hoặc trỏ --blueprint sang file có sẵn).
  2) Sửa feature_list.json (thay F01..F0x bằng feature thật) + Invariants trong CLAUDE.md + security.md + init.sh CONFIG theo stack.
  3) Audit: node <harness-creator>/scripts/validate-harness.mjs --target ${target}  (kỳ vọng 100/100)
  4) Bắt đầu BUILD theo .claude/workflow/pipeline.md.`);
