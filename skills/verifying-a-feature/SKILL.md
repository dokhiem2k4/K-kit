---
name: verifying-a-feature
description: Only in a project whose repo root has feature_list.json (a bootstrapped harness); never in any other repo. Use when you think a feature is finished and before marking it done/verified in feature_list.json - requires fresh command output as evidence, an adversarial refute pass over every done_when, and a bounded fix loop that escalates instead of spinning
---

# Verifying a feature

<PRECONDITION>
Khong co `feature_list.json` o repo root? Project nay KHONG co harness.
Thoat skill nay ngay, noi ro mot dong "project chua bootstrap harness", roi lam viec binh thuong.
Dung ap workflow harness len mot repo khong co harness.
</PRECONDITION>

**Nguyen tac:** bang chung truoc, tuyen bo sau. Luon luon.

```
KHONG TUYEN BO XONG MA KHONG CO EXIT CODE CHAY TRONG LUOT NAY
```

## Ham gate — chay truoc moi tuyen bo

```
1. XAC DINH: lenh nao chung minh dieu nay?  (lay tu field `verify` cua feature)
2. CHAY:     chay DAY DU lenh do, moi, khong dung ket qua cu
3. DOC:      doc het output, xem exit code, dem so failure
4. DOI CHIEU: output co xac nhan dung dieu ban sap noi khong?
   - KHONG → bao trang thai THAT kem output
   - CO    → tuyen bo KEM output lam bang chung
5. CHI KHI DO moi duoc noi "xong"
```

Bo bat ky buoc nao = noi doi, khong phai verify.

## Buoc 1 — bang chung co hoc

Chay `./init.sh` phan lien quan (thuong la `all`). **Dan nguyen output vao `progress.md`**,
khong tom tat. Exit code khac 0 → chua xong, quay lai BUILD.

Neu `init.sh` in SKIP hoac "(no ... script)" cho mot check ma feature nay CAN — do khong phai pass.
Do la check khong chay. Sua `init.sh` hoac chay tay va dan output.

## Buoc 2 — refute pass doi khang

Self-review mot chieu bo sot loi mot cach he thong: ban di tim ly do de tin la minh dung.
Refute pass dao nguoc: di tim mot dau vao lam no sai.

Co opt-in `Workflow` → dung saved workflow `adversarial-verify`:

```
Workflow({ name:'adversarial-verify', args:{
  featureId:'F0X',
  criteria:[ ...done_when... ],
  securityChecks:[ ...tu security.md... ]
}})
```

Khong opt-in → spawn `Agent` (Explore) thu cong voi cung tinh than: **mac dinh la REFUTED
tru khi khang dinh duoc dieu nguoc lai**. Voi moi `done_when`, di tim mot trong nhung thu nay:

- input rong / sai dinh dang / qua dai
- data cua user khac
- thieu token, token het han, token cua user khac
- cache cu hoac khong co cache
- CORS de dai, secret lot vao client bundle
- input chua tin cay cham toi sink (SQL / shell / prompt LLM)
- race giua 2 request
- **code don gian la chua duoc build**

`confirmedFailures` >= 1 → **chua done**, quay lai BUILD.

## Buoc 3 — truy vet yeu cau

Moi REQ trong Blueprint thuoc pham vi feature nay da map toi thu gi do trong code chua?
Thieu → ghi Open Question, khong lang lang bo qua.

## Vong fix co gioi han — dung xoay vong

Verify truot thi dem vong. Khong duoc lap vo han.

| Vong | Lam gi |
|---|---|
| 1–2 | Sua truc tiep, chay lai buoc 1 + 2 |
| 3 | **Dung sua.** Viet ra: gia thiet nao cua ban sai? Neu chua tra loi duoc → invoke skill debug he thong truoc khi sua tiep |
| 4 | Spawn subagent moi (context sach) doc lai feature tu dau — context cua ban da nhiem gia thiet sai |
| 5 | **BREAKER.** Dung. Voi tung finding con lai: no co load-bearing khong? |
| | · Co finding load-bearing → bao **BLOCKED** cho Homeowner, khong ship |
| | · Khong → ghi tung finding + ly do bo qua vao `progress.md`, xin Homeowner duyet |

Sang vong 6 ma khong escalate la loi cua ban, khong phai cua code.

## Chi khi ca 3 buoc xanh

Cap nhat `feature_list.json` status → `done`, kem bang chung trong `progress.md`.
Roi invoke `harness-kit:security-gate`.

`verified` la bac khac: chi Homeowner chay qua flow that moi duoc dat. Ban khong tu dat `verified`.

## Red flags

| Ban nghi | Thuc te |
|---|---|
| "Build xanh luc nay chac van xanh" | Chay lai. Ban vua sua code. |
| "Test pass roi, khoi refute" | Test kiem thu ban nghi toi. Refute tim thu ban khong nghi toi. |
| "Subagent bao OK" | Kiem tra doc lap. Bao cao cua agent khong phai bang chung. |
| "Linter xanh nghia la build duoc" | Linter khong compile. Chay build. |
| "`init.sh` in SKIP, coi nhu pass" | SKIP = khong chay. Khong phai pass. |
| "Tom tat output cho gon" | Dan nguyen van. Tom tat la cho ban giau con so. |
| "Toi tu tin no dung" | Tu tin ≠ bang chung. |
| "Vong thu 5 roi nhung sap duoc" | Breaker da nhay. Escalate. |
| "Lan nay ngoai le thoi" | Khong co ngoai le. |
