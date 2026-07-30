---
name: planning-features
description: Only in a project whose repo root has feature_list.json (a bootstrapped harness); never in any other repo. Use when turning an approved blueprint or a rough idea into entries in feature_list.json, when done_when is vague or untestable, or when the human asks to add/split/reorder features - every criterion must name a command or an observable
---

# Planning features

<PRECONDITION>
Khong co `feature_list.json` o repo root? Project nay KHONG co harness.
Thoat skill nay ngay, noi ro mot dong "project chua bootstrap harness", roi lam viec binh thuong.
Dung ap workflow harness len mot repo khong co harness.
</PRECONDITION>

**Nguyen tac:** `done_when` sai thi moi gate phia sau vo dung. Verify chi manh bang tieu chi no kiem.

Skill nay o **truoc** BUILD. No bien design da duyet thanh state may doc duoc.

## Truoc khi viet feature

Harness gia dinh **Blueprint da co va da duyet**. Chua co?

- Chua ro lam gi / lam cho ai → chua den luot skill nay. Brainstorm truoc
  (`superpowers:brainstorming` neu co cai), viet Blueprint, roi quay lai.
- Co Blueprint nhung mo ho o dung cho ban sap code → L2: hoi Homeowner, dung tu doan.

Dung dung skill nay de *nghi ra* san pham. No de *phien dich* san pham da chot.

## Mot feature tot trong `feature_list.json`

Bat buoc (validator can): `id`, `name`, `description`, `status`.
Nen co: `scope`, `done_when`, `verify`, `dependencies`, `doc`.

```json
{
  "id": "F04",
  "name": "Reset mat khau qua email",
  "description": "Nguoi dung quen mat khau: nhan link het han 15 phut qua email, dat lai mat khau.",
  "dependencies": ["F03"],
  "status": "pending",
  "doc": "docs/features/F04-password-reset.md",
  "scope": ["endpoint request-reset", "endpoint confirm-reset", "template email", "bang reset_token"],
  "done_when": [
    "POST /auth/request-reset voi email co that -> 202, co 1 row trong reset_token",
    "POST /auth/request-reset voi email khong ton tai -> 202 (khong lo email nao da dang ky)",
    "token qua 15 phut -> confirm tra 410",
    "dung lai token da dung -> 410"
  ],
  "verify": ["npm test -- auth/reset", "./init.sh", "./init.sh docs"]
}
```

## `done_when` phai testable — day la phan de sai nhat

Moi tieu chi phai tra loi duoc bang **mot lenh** hoac **mot thao tac quan sat duoc**.
Cong thuc: **dieu kien dau vao → ket qua quan sat duoc**.

| Khong dung | Vi sao | Sua thanh |
|---|---|---|
| "Auth hoat dong" | Khong co lenh nao chung minh | "endpoint bao ve thieu token → 401" |
| "UI dep" | Khong quan sat khach quan duoc | "form hien loi validate ngay duoi field sai" |
| "Xu ly loi tot" | "Tot" khong do duoc | "DB timeout → tra 503 + retry-after, khong lo stack trace" |
| "Nhanh" | Khong co nguong | "p95 < 300ms tren 100 request tuan tu" |
| "Da test" | Vong tron | "`npm test -- auth` xanh, phu ca 4 case tren" |
| "Code sach" | Khong phai tieu chi feature | Bo. Do la review, khong phai `done_when`. |

Viet xong moi tieu chi, tu hoi: **"lenh nao chung minh cai nay sai?"**
Khong tra loi duoc → tieu chi do chua dung duoc.

## Nho cac case am

`done_when` chi liet ke duong hanh phuc la ly do refute pass o VERIFY luon tim ra loi.
Voi feature dung toi data hoac auth, them it nhat mot tieu chi cho:

- thieu / sai / het han token
- data cua user khac
- input rong / sai dinh dang / qua dai
- goi lai lan hai (idempotency)

## Chia feature cho dung kich thuoc

- **Qua to** — `done_when` hon 6–7 tieu chi, hoac `scope` cham nhieu tang khong lien quan → tach.
- **Qua nho** — khong ship doc lap duoc, khong dang mot dossier → gop vao feature cha.
- Thuoc do tot: **mot feature = mot dossier doc len co nghia**.

## `dependencies` va thu tu

- Chi ghi phu thuoc **that**: F nay khong build/test duoc neu F kia chua xong.
- Dung ghi phu thuoc chi vi "lam sau cho hop ly" — no khoa lich lam viec vo co.
- Khong duoc co vong: A phu thuoc B, B phu thuoc A → tach lai.
- `active_feature` phai tro toi mot feature co **moi** dependency da `done`/`verified`.
  Hook dau phien se canh bao `DEPS CHUA XONG` neu sai.

## Truy vet nguoc ve Blueprint

Moi REQ trong Blueprint phai duoc **it nhat mot** feature cover. Kiem theo ca hai chieu:

- REQ khong feature nao cover → thieu feature, hoac REQ do la out-of-scope (ghi ro).
- Feature khong map REQ nao → hoi Homeowner: day la scope creep hay Blueprint thieu?

## Truoc khi ket thuc

- [ ] Moi feature co `id`, `name`, `description`, `status`
- [ ] Moi `done_when` deu dat duoc cau "lenh nao chung minh cai nay sai?"
- [ ] Feature dung toi data/auth co it nhat 1 case am
- [ ] `dependencies` khong vong, khong gia
- [ ] `doc` tro dung `docs/features/<ID>-<slug>.md`
- [ ] `active_feature` co moi dep da xong
- [ ] Moi REQ Blueprint da map

## Red flags

| Ban nghi | Thuc te |
|---|---|
| "Viet `done_when` chung chung roi sau chinh" | Sau se khong chinh. Va verify se pass rong. |
| "Feature nay hien nhien, khoi `done_when`" | Khong co tieu chi thi khong co gi de verify. |
| "Cu code truoc, feature_list sua sau" | Sua sau = viet lai tieu chi cho khop code da lam. Nguoc. |
| "Chia nho ra ton cong quan ly" | Feature to = dossier vo nghia + review khong noi. |
| "Them dep cho chac" | Dep gia khoa viec vo co. Chi ghi dep that. |
| "Blueprint mo ho nhung toi hieu y" | L2. Hoi. Doan sai o day hong ca feature. |
| "Case am de VERIFY lo" | VERIFY se lo that, roi ban quay lai BUILD. Ghi tu bay gio. |
