---
name: shipping-a-feature
description: Only in a project whose repo root has feature_list.json (a bootstrapped harness); never in any other repo. Use at the ship gate once a feature passes verify and security, before committing or opening a PR, and at the end of every session - runs the blocking ship checklist, the post-ship monitor step, and the clean-restart handoff
---

# Shipping a feature

<PRECONDITION>
Khong co `feature_list.json` o repo root? Project nay KHONG co harness.
Thoat skill nay ngay, noi ro mot dong "project chua bootstrap harness", roi lam viec binh thuong.
Dung ap workflow harness len mot repo khong co harness.
</PRECONDITION>

**Nguyen tac:** SHIP la gate, khong phai nghi thuc. Moi o chua tick la mot ly do khong ship.

## Checklist SHIP — moi muc phai co bang chung

- [ ] **`./init.sh` phan lien quan all green** — output moi, dan vao `progress.md`.
- [ ] **Review diff da chay** — `Workflow({ name:'parallel-review' })` neu co opt-in, hoac spawn `Agent` review thu cong. **0 P0 confirmed.**
- [ ] **SECURITY gate pass** — `harness-kit:security-gate` chay xong, moi P0 ap dung xanh.
- [ ] **Client bundle 0 secret** — `./init.sh secret`.
- [ ] **State cap nhat** — `feature_list.json` status + field `doc`; `progress.md` co bang chung.
- [ ] **Dossier xong** — `docs/features/<ID>-<slug>.md` du 8 muc, `./init.sh docs` xanh. Xem `harness-kit:writing-feature-dossier`.
- [ ] **Docs theo diff (Diataxis)** — *Reference* (API/config/schema), *How-to* (setup/deploy), *Tutorial* (flow chinh), *Explanation* (vi sao). Chi viet muc nao diff thuc su cham toi.
- [ ] **Commit/PR** neu feature id + REQ da cover; PR body liet ke `done_when` da pass.

Con **bat ky** o nao trong → chua ship. Khong co "ship truoc, tick sau".

## DevEx — 2 cau hoi truoc khi ship

- **TTHW:** clone repo sach → chay duoc mat bao lau? README + `.env.example` du chua?
- **Friction:** loi mo ho, thieu script, buoc thu cong an? Ghi lai; va luon neu re.

## Lan toa sang F cu

Feature nay doi hanh vi cua mot F da ship? Them dong co ngay vao **muc 8** dossier cua F do.
Ngay bay gio, trong SHIP nay.

## MONITOR — sau khi ship

Ship xong chua phai xong:

- Health check sau deploy.
- Smoke test flow chinh.
- Kiem tra ha tang: DB advisors, logs, error rate.
- Ghi ket qua vao `progress.md`.
- Co hoi quy → **mo feature fix moi**, khong sua len.

## End of Session — de phien sau restart sach

Truoc khi dung phien, du feature chua xong:

1. **`feature_list.json`** — status dung thuc te + field `doc` neu vua ship.
2. **`progress.md`** — Current State + bang chung (output lenh, khong phai tom tat).
3. **`session-handoff.md`** — Blockers, Files touched, **Recommended Next Step**.
   Next Step phai cu the den muc phien sau doc xong la lam duoc ngay: ten file, ten lenh, ten feature.
   "Tiep tuc F03" khong phai next step.
4. **Memory** — ghi vao harness memory nhung thu **khong suy ra duoc tu code**: quyet dinh kien truc phat sinh, cam bay da gap, trade-off da chon va ly do. Dung ghi lai thu code da noi.

## Red flags

| Ban nghi | Thuc te |
|---|---|
| "Con 1 o chua tick nhung khong quan trong" | Moi o la mot gate. Tick het hoac khong ship. |
| "Dossier de mai viet" | `./init.sh docs` FAIL. Va mai se khong den. |
| "Review diff ton token, bo qua" | Re hon mot P0 tren prod. |
| "Ship roi monitor sau" | Monitor la buoc 10, khong phai tuy chon. |
| "Hoi quy nho, sua len thoi" | Sua len = khong co bang chung, khong co dossier. Mo feature fix. |
| "Next step ghi 'tiep tuc F03' la du" | Phien sau se mat nua tieng do lai. Ghi ten file + ten lenh. |
| "Phien nay ngan, khoi handoff" | Compaction khong quan tam phien dai hay ngan. |
| "P0 nay minor" | P0 khong minor. Do la dinh nghia cua P0. |
