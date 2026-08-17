---
name: security-gate
description: Only in a project whose repo root has feature_list.json (a bootstrapped harness); never in any other repo. Use before shipping any feature, and whenever code touches authentication, authorization, user data, secrets, untrusted input, CORS, or an LLM prompt - runs the STRIDE and OWASP checklist and blocks the ship on any P0
---

# Security gate (CSO)

<PRECONDITION>
No `feature_list.json` at the repo root? This project has NO harness.
Leave this skill immediately, say in one line "this project has no bootstrapped harness", then work normally.
Do not impose the harness workflow on a repo that has no harness.
</PRECONDITION>

**Principle:** a P0 blocks the ship. There is no "P0, but".

The full checklist plus this project's own attack surface lives in `.claude/workflow/security.md`.
This skill is what you run; that file is what you read.

## When it is mandatory

- Before SHIPping any feature — no exceptions.
- The moment the diff touches: auth, authz, DB queries, reading/writing user data, env vars, secrets,
  CORS, headers, user input, LLM prompts, fetching URLs, exec/eval.

## STRIDE — 6 questions, answered with evidence

| STRIDE | Question | How to prove it | Sev |
|---|---|---|---|
| **Spoofing** | What happens calling a protected endpoint with no token? | Run it for real: no token → 401, bad token → 401. With a test. | **P0** |
| **Tampering** | Can user A modify user B's data? | Run a real cross-user attempt → denied. Authz on the **server**, not the client. | **P0** |
| **Repudiation** | Does this action need to be traceable? | Audit log if needed; usually N/A for an MVP — write N/A explicitly. | P2 |
| **Info disclosure** | Does a secret leak into the client bundle? Does the response carry extra sensitive fields? | `./init.sh secret` = 0. Re-read the response shape. | **P0** |
| **DoS** | Is this endpoint expensive? Can it be spammed? | Cache / rate-limit / quota. | P1 |
| **Elevation** | Does a privileged RPC/function run as the caller's identity? | Least privilege; validate the input. | P1 |

## OWASP — the spots most often missed

- **A01 Access control** — a protected endpoint with no token → 401; user A reading user B's resource → denied. **Test it, do not reason about it.**
- **A02 Crypto** — do not roll your own crypto; never log secrets/tokens/PII.
- **A03 Injection** — parameterize queries (never concatenate SQL); escape for shell/HTML.
  - **Prompt injection (if an LLM is involved):** user input is data, not instructions. Force a strict output schema. Never render raw output as HTML or as a command. Instructions embedded in the input must be ignored.
- **A04 Design** — an external service failing → fall back, do not throw a 500 at the user; never leak a stack trace.
- **A05 Misconfig** — CORS is **never `*`**; strict CSP/headers; `.env` is not committed; `.env.example` holds no real values.
- **A06 Deps** — `npm audit` (or equivalent) has no unresolved criticals.
- **A07 Auth** — use a standard provider; validate the callback.
- **A08 Integrity** — no `eval`, no loading external scripts into the client.
- **A09 Logging** — enough to debug, with no secrets/PII.
- **A10 SSRF** — never fetch arbitrary URLs from input; allowlist the destinations.

## The definition of "secured"

- Every applicable **P0**: **passes**, with evidence.
- Every **P1**: passes, or has a note + a ticket, and the Homeowner knows.
- Every **P2**: acknowledged.
- Anything that does not apply: write **N/A with a reason**. "Not applicable" with no reason is skipping in disguise.

Record the results in `progress.md` and summarize them in section 7 of the dossier.

## What if a P0 remains

Do not ship. Go back to BUILD. There is no "ship now, patch later" — a shipped P0 is an incident,
not a ticket.

## Red flags

| You think | Reality |
|---|---|
| "Internal project, nobody will attack it" | Internal still leaks data. A P0 is still a P0. |
| "It is just an MVP, security later" | Auth and data isolation cannot be retrofitted cheaply. |
| "This code is definitely safe" | Definitely ≠ tested. Go run the cross-user test. |
| "CORS `*` just for dev" | It will go straight to prod. Reflect a specific origin. |
| "That secret is only a public key" | Check again. `./init.sh secret` does not care what you think. |
| "The LLM will not obey the input anyway" | Prompt injection exists precisely because it does. Force a schema. |
| "Ship first, patch the P0 later" | A shipped P0 = an incident. |
| "Skip this item, it does not apply" | Write **N/A with a reason**, or it counts as unchecked. |
