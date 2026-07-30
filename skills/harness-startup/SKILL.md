---
name: harness-startup
description: Only in a project whose repo root has feature_list.json (a bootstrapped harness); never in any other repo. Use at the start of every session in a harness project, when resuming work, when the human says "continue"/"tiep tuc", or whenever you are unsure which feature is active - reads state files in a fixed order before any code is read or written
---

# Harness startup

<PRECONDITION>
Khong co `feature_list.json` o repo root? Project nay KHONG co harness.
Thoat skill nay ngay, noi ro mot dong "project chua bootstrap harness", roi lam viec binh thuong.
Dung ap workflow harness len mot repo khong co harness.
</PRECONDITION>

**Nguyen tac:** doc state truoc, doc code sau. Code khong noi cho ban biet feature nao dang active,
`done_when` la gi, hay phien truoc dung o dau.

## Doc theo dung thu tu nay

Doc het 5 buoc roi moi cham vao code. Tao todo cho tung buoc.

1. **`progress.md`** — Current State + bang chung lan cuoi. Day la "dang o dau".
2. **`session-handoff.md`** — Blockers, Files touched, Recommended Next Step. Day la "phien truoc dinh gi".
3. **`feature_list.json`** — lay `active_feature`, doc `scope`, `done_when`, `verify`, `dependencies` cua no.
4. **Blueprint** (duong dan o field `blueprint`) — doc dung muc lien quan feature dang active.
5. **Dossier cua feature lien quan** — xem duoi.

## Khi nao BAT BUOC doc dossier

Sap dung toi mot feature co status `done` hoac `verified`? Doc `docs/features/<ID>-<slug>.md`
(duong dan o field `doc`) **truoc khi mo file code**:

- **Muc 4 (Ben trong)** — luong chinh + bang files touched. Tiet kiem ca phien do lai.
- **Muc 6 (Cam bay khi sua)** — invariant phai giu, phu thuoc ngam. Day la thu se lam ban vo code neu khong doc.

Bo qua buoc nay la ly do pho bien nhat khien mot feature dang chay bi lam hong boi feature ke tiep.

## Kiem tra truoc khi bat dau

- [ ] `dependencies` cua `active_feature` **deu** `done`/`verified`? Neu chua → khong duoc bat dau, bao Homeowner.
- [ ] `done_when` co **testable** khong? Moi tieu chi phai tra loi duoc bang mot lenh hoac mot thao tac quan sat duoc. Neu khong → sua `done_when` truoc, dung code truoc.
- [ ] Co blocker nao dang cho Homeowner trong `session-handoff.md`? Neu blocker chan feature nay → hoi, dung tu quyet.
- [ ] Status hien tai cua `active_feature` la gi? `in_progress` nghia la co viec dang do — tim no trong `progress.md`, dung lam lai tu dau.

## Sau khi doc xong

Noi lai cho Homeowner trong **3 dong**: dang o feature nao, `done_when` con thieu gi, buoc ke tiep la gi.
Roi invoke `harness-kit:building-a-feature`.

## Red flags

| Ban nghi | Thuc te |
|---|---|
| "Toi doc code nhanh hon doc state" | Code khong chua `done_when`. Ban se build sai tieu chi. |
| "Phien truoc la toi, toi nho ma" | Context da bi compact. `progress.md` nho, ban thi khong. |
| "Feature nay don gian, khoi doc dossier" | Muc 6 ton tai chinh vi no khong don gian. |
| "Doc 5 file ton token qua" | Re hon build sai roi lam lai. |
| "`done_when` mo ho nhung toi hieu y" | Ban hieu y ≠ verify duoc. Sua `done_when`. |
