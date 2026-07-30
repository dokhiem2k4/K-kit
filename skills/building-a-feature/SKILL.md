---
name: building-a-feature
description: Only in a project whose repo root has feature_list.json (a bootstrapped harness); never in any other repo. Use before writing implementation code for a feature in a harness project - enforces scope boundaries from feature_list.json, live testing over code reading, and the escalation ladder when the spec is ambiguous
---

# Building a feature

<PRECONDITION>
Khong co `feature_list.json` o repo root? Project nay KHONG co harness.
Thoat skill nay ngay, noi ro mot dong "project chua bootstrap harness", roi lam viec binh thuong.
Dung ap workflow harness len mot repo khong co harness.
</PRECONDITION>

**Nguyen tac:** `scope` va `done_when` trong `feature_list.json` la hop dong. Code ngoai hop dong
la overreach, ke ca khi no "ro rang la can".

## Truoc khi go dong dau tien

- [ ] Da chay `harness-kit:harness-startup` trong phien nay.
- [ ] Doc `scope` cua feature — day la danh sach thu duoc phep dung toi.
- [ ] Doc `done_when` — day la thu ban phai lam cho dung, khong hon.
- [ ] Doc muc Blueprint tuong ung.
- [ ] Doc muc **Invariants** trong `CLAUDE.md` — do la thu khong duoc vi pham du spec co noi gi.

## Trong luc build

**Live testing — bat buoc.** Phan nao chay duoc thi phai *chay that*: curl endpoint, mo app,
build ra artifact, goi function trong REPL. Doc code roi ket luan "no se chay" khong tinh la test.

**Bugfix di kem test tai hien.** Sua bug ma khong co test do truoc-xanh sau thi bug se quay lai.
Neu khong viet duoc test tai hien → ban chua hieu bug → invoke skill debug truoc.

**`/freeze`.** Dang sua bug cua F nao thi chi cham file thuoc scope F do. Thay bug o cho khac →
ghi vao `progress.md` muc Open, khong sua tien tay.

**`/careful`.** Lenh pha huy (`rm -rf`, `DROP`, `TRUNCATE`, `force-push`, `reset --hard`,
xoa migration, ghi de file chua doc) → dung, hoi Homeowner. Khong co ngoai le "chac khong sao".

**Atomic commit.** Moi feature/bugfix = 1 commit gon. Message neu **ly do** + feature id.

## Escalation ladder — dung tu quyet sai bac

| Bac | Vi du | Lam gi |
|---|---|---|
| **L1** | Ten bien, code style, thu tu import, chia helper | Tu quyet, khong hoi |
| **L2** | Spec mo ho, chon giua 2 pattern, trade-off perf/doc | **Dung**, hoi trong report, de xuat 1 phuong an |
| **L3** | Doi scope / kien truc / business rule / bat cu thu gi cham security | **STOP**, escalate Homeowner, khong code tiep |

Nham L3 thanh L1 la cach nhanh nhat de phai lam lai ca feature.

## Ranh gioi scope — thu KHONG duoc lam

- Them feature khong co trong `feature_list.json` (du no "chi 5 dong").
- Doi kien truc da duyet trong Blueprint.
- Refactor file ngoai `scope` cua feature dang lam.
- Them dependency moi ma Blueprint khong nhac toi → L3.
- "Tien tay" sua bug khong lien quan → ghi lai, khong sua.

Thay thu can lam nhung ngoai scope → viet vao `progress.md` muc Open Questions,
de xuat mo feature moi. Khong lam len.

## Xong thi lam gi

Khong tu danh `done`. Invoke `harness-kit:verifying-a-feature`.

## Red flags

| Ban nghi | Thuc te |
|---|---|
| "Cai nay ro rang la can, them luon" | Ro rang voi ban ≠ trong scope. L3. |
| "Refactor luon cho sach" | Refactor ngoai scope lam diff khong review duoc. |
| "Doc code thay dung roi, khoi chay" | Doc code ≠ live testing. Chay di. |
| "Bug nay 1 dong, khoi viet test" | Bug 1 dong quay lai nhieu nhat. |
| "Spec mo ho, toi doan y Homeowner" | Doan = L2 lam thanh L1. Hoi. |
| "Sua tien tay bug ben canh" | `/freeze`. Ghi lai thoi. |
| "`rm -rf` cho nhanh, toi biet minh lam gi" | `/careful`. Hoi. |
