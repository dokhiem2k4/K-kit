---
name: security-gate
description: Only in a project whose repo root has feature_list.json (a bootstrapped harness); never in any other repo. Use before shipping any feature, and whenever code touches authentication, authorization, user data, secrets, untrusted input, CORS, or an LLM prompt - runs the STRIDE and OWASP checklist and blocks the ship on any P0
---

# Security gate (CSO)

<PRECONDITION>
Khong co `feature_list.json` o repo root? Project nay KHONG co harness.
Thoat skill nay ngay, noi ro mot dong "project chua bootstrap harness", roi lam viec binh thuong.
Dung ap workflow harness len mot repo khong co harness.
</PRECONDITION>

**Nguyen tac:** P0 chan ship. Khong co "P0 nhung ma".

Checklist day du + attack surface rieng cua project o `.claude/workflow/security.md`.
Skill nay la thu ban chay; file kia la thu ban doc.

## Khi nao bat buoc chay

- Truoc SHIP moi feature — khong co ngoai le.
- Ngay khi diff cham vao: auth, authz, query DB, doc/ghi data user, bien env, secret,
  CORS, header, input tu nguoi dung, prompt LLM, fetch URL, exec/eval.

## STRIDE — 6 cau hoi, tra loi bang bang chung

| STRIDE | Cau hoi | Cach chung minh | Sev |
|---|---|---|---|
| **Spoofing** | Goi endpoint bao ve ma khong co token thi sao? | Chay that: thieu token → 401, sai token → 401. Co test. | **P0** |
| **Tampering** | User A sua duoc data user B khong? | Chay that cross-user → deny. Authz o **server**, khong o client. | **P0** |
| **Repudiation** | Co can truy vet hanh dong nay khong? | Audit log neu can; MVP thuong N/A — ghi ro N/A. | P2 |
| **Info disclosure** | Secret co lot vao client bundle khong? Response co thua field nhay cam khong? | `./init.sh secret` = 0. Doc lai shape cua response. | **P0** |
| **DoS** | Endpoint nay dat tien khong? Spam duoc khong? | Cache / rate-limit / quota. | P1 |
| **Elevation** | RPC/function quyen cao co chay theo danh tinh caller khong? | Least-privilege; validate input. | P1 |

## OWASP — diem cham hay bi bo sot

- **A01 Access control** — endpoint thieu token → 401; user A doc resource user B → deny. **Test that, khong suy luan.**
- **A02 Crypto** — khong tu cuon crypto; khong log secret/token/PII.
- **A03 Injection** — tham so hoa query (khong noi chuoi SQL); escape shell/HTML.
  - **Prompt injection (neu co LLM):** input nguoi dung = du lieu, khong phai chi thi. Ep schema cung cho output. Khong render raw output thanh HTML/lenh. Chi thi nam trong input phai bi bo qua.
- **A04 Design** — loi dich vu ngoai → fallback, khong throw 500 ra nguoi dung; khong lo stack trace.
- **A05 Misconfig** — CORS **khong `*`**; CSP/header chat; `.env` khong commit; `.env.example` khong chua gia tri that.
- **A06 Deps** — `npm audit` (hoac tuong duong) khong con critical chua xu.
- **A07 Auth** — dung provider chuan; validate callback.
- **A08 Integrity** — khong `eval`, khong load script ngoai vao client.
- **A09 Logging** — du de debug, khong co secret/PII.
- **A10 SSRF** — khong fetch URL tuy y tu input; allowlist dich.

## Definition of "secured"

- Moi **P0** ap dung: **pass**, co bang chung.
- Moi **P1**: pass, hoac co ghi chu + ticket va Homeowner biet.
- Moi **P2**: ghi nhan.
- Muc nao khong ap dung: ghi **N/A kem ly do**. "Khong ap dung" khong co ly do la bo qua tra hinh.

Ghi ket qua vao `progress.md` va tom tat vao muc 7 cua dossier.

## Con P0 thi sao

Khong ship. Quay lai BUILD. Khong "ship roi vá sau" — mot P0 da ship la mot su co,
khong phai mot ticket.

## Red flags

| Ban nghi | Thuc te |
|---|---|
| "Project noi bo, khong ai tan cong" | Noi bo cung ro data. P0 van la P0. |
| "MVP thoi, security sau" | Auth va data isolation khong retrofit duoc re. |
| "Code nay chac chan safe" | Chac chan ≠ da test. Chay cross-user test di. |
| "CORS `*` cho de dev" | No se di thang len prod. Reflect origin cu the. |
| "Secret nay la key public thoi" | Kiem tra lai. `./init.sh secret` khong quan tam ban nghi gi. |
| "LLM khong nghe loi input dau" | Prompt injection ton tai chinh vi no nghe. Ep schema. |
| "Ship truoc, P0 vá sau" | P0 da ship = su co. |
| "Bo qua muc nay, khong ap dung" | Viet **N/A kem ly do**, hoac no chua duoc kiem. |
