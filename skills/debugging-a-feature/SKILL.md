---
name: debugging-a-feature
description: Only in a project whose repo root has feature_list.json (a bootstrapped harness); never in any other repo. Use when a test fails, verify fails, a shipped feature regresses, or the fix loop in verifying-a-feature has spun twice - decides scope, state and dossier consequences; defers the debugging method itself to a debugging skill
---

# Debugging a feature

<PRECONDITION>
Khong co `feature_list.json` o repo root? Project nay KHONG co harness.
Thoat skill nay ngay, noi ro mot dong "project chua bootstrap harness", roi lam viec binh thuong.
Dung ap workflow harness len mot repo khong co harness.
</PRECONDITION>

**Skill nay khong day ban cach debug.** No tra loi cau hoi harness dat ra khi co bug:
sua o dau, tinh vao feature nao, state va dossier phai doi gi.

**Phuong phap debug:** dung `superpowers:systematic-debugging` neu co cai.
Khong co → toi thieu phai lam theo muc "Phuong phap toi thieu" ben duoi. Dung nhay thang vao sua.

## Buoc 1 — bug nay thuoc ve dau

Tra loi truoc khi sua mot dong nao.

| Tinh huong | Xu ly |
|---|---|
| Bug trong feature **dang active** | Sua trong scope feature do. Khong doi status. |
| Bug trong feature da `done`/`verified`, ban vua lam no vo | Van la loi cua feature dang active. Sua, va them dong vao **muc 8** dossier cua F cu. |
| Bug co san trong feature da ship, khong lien quan viec dang lam | **Khong sua len.** Mo feature fix moi trong `feature_list.json`. Ghi vao `progress.md`. |
| Bug o cho hoan toan ngoai scope | Ghi Open Question. Khong dung toi. |

**`/freeze` luon bat khi debug:** chi sua file thuoc scope cua feature dang lam.
Thay bug khac tren duong đi → ghi lai, khong tien tay sua. Diff lan lon khong review duoc,
va khong ai biet thay doi nao that su vá duoc bug.

## Buoc 2 — doc dossier truoc khi doc code

Bug o feature da ship? Doc `docs/features/<ID>-<slug>.md` truoc:

- **Muc 6 (Cam bay khi sua)** — thuong da ghi san dung cho ban sap vo.
- **Muc 4 (Ben trong)** — luong chinh + files touched, khoi do lai.
- **Muc 5 (Quyet dinh)** — cai gi **co y** khong lam. Rat nhieu "bug" thuc ra la out-of-scope da chot.

Bo qua buoc nay roi "sua" mot thu von la quyet dinh co chu dich la cach lam hong feature dang chay.

## Phuong phap toi thieu (khi khong co skill debug chuyen)

1. **Tai hien** — mot lenh chay lai duoc bug. Chua tai hien duoc thi chua duoc sua.
2. **Thu hep** — bug con o dau khi bo bot dau vao? Tim don vi nho nhat con hong.
3. **Giai thich** — viet ra mot cau: *nguyen nhan la X, nen Y xay ra*. Chua viet duoc thi chua hieu.
4. **Sua nguyen nhan** — khong vá trieu chung, khong them try/catch nuot loi.
5. **Chung minh** — test do TRUOC khi sua, xanh SAU khi sua. Chua thay no do thi khong biet no kiem gi.

## Buoc 3 — bugfix di kem test tai hien

Bat buoc. Va phai thay no **do** truoc:

```
viet test → chay (PHAI DO) → sua → chay (PHAI XANH) → revert ban sua → chay (PHAI DO LAI) → khoi phuc
```

Bo buoc revert thi ban khong biet test co that su kiem cai bug do khong.
Rat nhieu "regression test" thuc ra xanh ca truoc lan sau khi sua.

Khong viet duoc test tai hien → ban chua hieu bug → quay lai buoc 2 cua phuong phap.

## Buoc 4 — cap nhat state

- **`progress.md`** — bug la gi, nguyen nhan, cach vá, output test. Day la thu phien sau can.
- **`feature_list.json`** — mo feature fix neu bug thuoc F da ship va khong lien quan viec dang lam.
- **Dossier muc 8** — feature da ship bi doi hanh vi → them dong co ngay. Ngay bay gio.
- **Dossier muc 6** — bug nay lo ra mot cam bay chua ai ghi? Them vao. Day la cach muc 6 day len.

Roi quay lai `harness-kit:verifying-a-feature` chay lai gate.

## Khi vong fix da xoay

`verifying-a-feature` dem vong fix. Sang vong 3 ma van chua qua nghia la gia thiet cua ban sai,
khong phai ban sua chua du. Dung sua tiep — viet ra gia thiet nao sai, hoac spawn subagent
context sach doc lai tu dau. Vong 5 la breaker: escalate.

## Red flags

| Ban nghi | Thuc te |
|---|---|
| "Thay ngay loi roi, sua luon" | Chua tai hien thi chua biet do co phai loi khong. |
| "Bug nho, khoi viet test" | Bug nho quay lai nhieu nhat. |
| "Test xanh roi, khoi revert thu" | Chua thay no do thi khong biet no kiem gi. |
| "Tien tay sua luon bug ben canh" | `/freeze`. Ghi lai thoi. |
| "Bug o F cu, sua len cho nhanh" | Khong bang chung, khong dossier. Mo feature fix. |
| "Them try/catch cho het loi" | Nuot loi khong phai vá. Trieu chung bien mat, bug o lai. |
| "Doc dossier ton thoi gian" | Muc 6 thuong da ghi dung cho ban sap vo. |
| "Sua 3 lan chua duoc, thu cach 4" | Vong 3 = gia thiet sai. Dung sua, doc lai tu dau. |
