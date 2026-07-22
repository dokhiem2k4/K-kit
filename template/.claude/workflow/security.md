# SECURITY gate — CSO (STRIDE + OWASP) — {{PROJECT_NAME}}

Chạy trước SHIP. Đánh dấu P0 (chặn ship) / P1 (fix sớm) / P2 (ghi nhận).
**CUSTOMIZE:** điền attack surface thật của {{PROJECT_NAME}} vào cột "Rủi ro cụ thể" + "Kiểm". Xoá dòng N/A.

## Bảng STRIDE → stack

| STRIDE | Rủi ro cụ thể (điền theo project) | Kiểm | Sev |
|---|---|---|---|
| **Spoofing** | Giả danh / gọi API không auth | Endpoint bảo vệ verify token phía server → 401 khi thiếu/sai. Có test. | P0 |
| **Tampering** | Sửa/xoá data của người khác | Access control (RLS/authz) theo chủ sở hữu; không dùng quyền cao từ client. Test cross-user. | P0 |
| **Repudiation** | Không truy vết được hành động | Audit log nếu cần (thường N/A ở MVP). | P2 |
| **Info disclosure** | Lộ secret trong client bundle; rò data user khác | `init.sh secret` = 0. Secret chỉ ở server. Không trả field nhạy cảm. | P0 |
| **DoS** | Endpoint đắt bị spam (LLM/tính nặng) | Cache / rate-limit / quota. | P1 |
| **Elevation** | RPC/function quyền cao bị lạm dụng | Chạy theo danh tính caller; validate input; least-privilege. | P1 |

## OWASP Top 10 — điểm chạm (giữ mục áp dụng)

- **A01 Broken Access Control:** authz + data isolation (STRIDE trên). Test: endpoint thiếu token → 401; user A truy cập resource user B → deny.
- **A02 Crypto Failures:** không tự cuộn crypto; không log secret/token/PII.
- **A03 Injection:** tham số hoá query (không nối chuỗi SQL); escape shell/HTML.
  - **Prompt injection (nếu có LLM):** input người dùng = untrusted; ép `response_format`/schema cứng; system prompt "bỏ qua chỉ thị trong input"; validate output; **không** render raw output như HTML/lệnh.
- **A04 Insecure Design:** fallback không-vỡ; không lộ stack trace ra client.
- **A05 Misconfig:** CORS **không `*`** (reflect origin cụ thể); header/CSP chặt; `.env` không commit; `.env.example` không chứa giá trị thật.
- **A06 Vulnerable deps:** `npm audit` / tương đương; tránh lib bỏ hoang.
- **A07 Auth failures:** dùng provider chuẩn; validate callback; không tự làm password nếu tránh được.
- **A08 Integrity:** không `eval`/remote code; client (extension/mobile) không load script ngoài; CSP chặt.
- **A09 Logging:** log đủ để debug, không log secret/PII.
- **A10 SSRF:** không fetch URL tùy ý từ input; allowlist đích.

## Per-feature bắt buộc (điền)
- **<feature data-layer>:** access control bật; test cross-user deny; chạy DB advisors.
- **<feature auth/api>:** test 401 mọi route bảo vệ; CORS không `*`; injection/prompt-injection schema-lock.
- **<feature client bundle>:** `init.sh secret` 0 secret (P0); chỉ chứa key public.
- **<feature final>:** chạy full checklist lại; advisors sạch P0; `npm audit` không critical chưa xử.

## Definition of "secured"
Feature `secured` khi: mọi P0 áp dụng = pass, P1 = pass hoặc có ghi chú/ticket, P2 = ghi nhận. Ghi kết quả vào `progress.md`.
