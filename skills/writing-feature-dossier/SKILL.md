---
name: writing-feature-dossier
description: Only in a project whose repo root has feature_list.json (a bootstrapped harness); never in any other repo. Use at the ship gate after a feature passes verify and security, when creating docs/features/<ID>-<slug>.md, or when a new feature changes the behaviour of an already-shipped one - enforces the 8 fixed sections that ./init.sh docs checks mechanically
---

# Writing a feature dossier

<PRECONDITION>
Khong co `feature_list.json` o repo root? Project nay KHONG co harness.
Thoat skill nay ngay, noi ro mot dong "project chua bootstrap harness", roi lam viec binh thuong.
Dung ap workflow harness len mot repo khong co harness.
</PRECONDITION>

**Nguyen tac:** `feature_list.json` tra loi "xong chua". `progress.md` tra loi "dang o dau".
Dossier tra loi **"F do rot cuoc la cai gi, chay ra sao, vi sao lam vay"** — thu ma phien sau
phai doc lai code moi biet neu khong co no.

Mot feature = **dung mot** file `docs/features/<ID>-<slug>.md`. Khong gop, khong tach.

## Khi nao viet

Tai **SHIP gate**, sau khi VERIFY + SECURITY + DEVEX da pass. Khong viet truoc (chua co bang chung),
khong viet sau (se khong bao gio viet).

Bat dau bang cach copy `docs/features/_TEMPLATE.md`. Roi tro field `doc` trong `feature_list.json`
toi duong dan vua tao.

## 8 muc — dung thu tu, dung chu

`./init.sh docs` bam vao heading. Muc khong ap dung thi ghi `—`, **khong xoa heading**.

| # | Heading | Tra loi | Cho ai |
|---|---|---|---|
| 1 | `## 1. Ý nghĩa với dự án` | Vai tro trong buc tranh chung; unlock F nao; khong co no thi thieu gi; cover REQ nao | ca hai |
| 2 | `## 2. Làm được gì` | Hanh vi quan sat duoc: bam/goi gi thi ra gi | nguoi |
| 3 | `## 3. Cách dùng` | Buoc cu the / endpoint / man hinh / lenh + vi du that | nguoi |
| 4 | `## 4. Bên trong` | Luong A→B→C; bang **files touched**; schema; bien env | **agent** |
| 5 | `## 5. Quyết định & trade-off` | Chon gi, bo gi, vi sao; cai gi **co y khong lam** | ca hai |
| 6 | `## 6. Cạm bẫy khi sửa` | Cho de vo, invariant phai giu, phu thuoc ngam | **agent** |
| 7 | `## 7. Bằng chứng` | Tung `done_when` → cach verify → ket qua; ket qua SECURITY | ca hai |
| 8 | `## 8. Cập nhật` | Dong co ngay, ghi khi F sau doi hanh vi F nay | ca hai |

## Ranh gioi muc 1 va muc 2 — dung viet trung

- **Muc 1 = zoom out.** Vai tro cua feature trong he thong. Vi sao du an CAN no.
- **Muc 2 = zoom in.** Hanh vi quan sat duoc. Bam/goi gi thi ra gi.

Viet muc 1 ma toan cau "nguoi dung bam nut X thi thay Y" la ban da viet muc 2 hai lan.

## Muc 4 va 6 la phan gia tri nhat

Day la hai muc phien sau doc de khoi do lai ca buoi:

- **Muc 4** phai co bang `| File | Vai tro |` — moi file da cham, mot dong mo ta. Khong liet ke tat ca file trong repo, chi file thuoc feature nay.
- **Muc 6** phai cu the: "doi thu tu 2 middleware nay se lam session mat", chu khong phai "can than khi sua".

Muc 6 viet chung chung = muc 6 vo dung.

## Truoc khi ship: don sach

- [ ] Xoa het placeholder `<TODO: ...>`
- [ ] Xoa het chu thich huong dan `<!-- ... -->`
- [ ] Header co Status / Ngay / Commit / Blueprint
- [ ] `feature_list.json` co field `doc` tro dung duong dan
- [ ] `./init.sh docs` **xanh**

`./init.sh docs` FAIL neu thieu muc, sai thu tu, con `<TODO:` hoac con `<!--`. Khong cai duoc gate nay.

## Lan toa — luat de bi no nhat

Feature dang ship **doi hanh vi cua mot F cu**? Phai them **mot dong co ngay vao muc 8**
trong dossier cua F cu do. Lam ngay trong SHIP nay, khong de no.

Dossier lech voi code con te hon khong co dossier — vi phien sau se tin no.

## Red flags

| Ban nghi | Thuc te |
|---|---|
| "Viet dossier sau khi ship cho nhanh" | Sau khi ship = khong bao giờ. Viet trong gate. |
| "Muc nay khong ap dung, xoa heading" | Ghi `—`. Xoa heading lam `init.sh docs` FAIL. |
| "Copy mo ta tu feature_list.json sang" | Dossier de tra loi cai ma feature_list khong tra loi duoc. |
| "Muc 6 ghi 'can than khi sua' la du" | Vo dung. Ghi chinh xac cho nao vo va vi sao. |
| "F cu chac khong anh huong" | Ban vua doi hanh vi cua no. Them dong vao muc 8. |
| "De `<TODO:` do sua sau" | `./init.sh docs` FAIL. Va ban se khong sua. |
| "Tom tat het output verify vao muc 7" | Muc 7 tom tat + tro toi `progress.md`. Output day o do. |
