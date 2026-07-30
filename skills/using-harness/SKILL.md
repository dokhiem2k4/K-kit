---
name: using-harness
description: Only in a project whose repo root has feature_list.json (a bootstrapped harness); never in any other repo. Use when starting any session in a project that has a harness (feature_list.json + .claude/workflow/) - routes every pipeline moment to its gate skill and forbids marking work done without machine evidence
---

# Using the harness

<PRECONDITION>
Khong co `feature_list.json` o repo root? Project nay KHONG co harness.
Thoat skill nay ngay, noi ro mot dong "project chua bootstrap harness", roi lam viec binh thuong.
Dung ap workflow harness len mot repo khong co harness.
</PRECONDITION>

<SUBAGENT-STOP>
Neu ban duoc dispatch lam subagent cho mot task cu the, bo qua skill nay.
</SUBAGENT-STOP>

<EXTREMELY-IMPORTANT>
Trong project co harness, **state file la su that, khong phai tri nho cua ban**.
Neu co 1% kha nang mot gate skill duoi day ap dung, BAT BUOC invoke no truoc khi hanh dong.
</EXTREMELY-IMPORTANT>

## Luat cot loi

```
KHONG TUYEN BO XONG MA KHONG CO EXIT CODE
```

Feature chi `done` khi lenh trong `verify` cua no chay **trong luot nay** va tra exit 0.
"Chac pass", "logic dung roi", "build truoc do xanh" — deu khong tinh.

## Chon gate skill

| Thoi diem | Skill |
|---|---|
| Bat dau phien / "tiep tuc di" / khong ro dang o dau | `harness-kit:harness-startup` |
| Bien Blueprint thanh feature, hoac `done_when` mo ho | `harness-kit:planning-features` |
| Sap viet code cho mot feature | `harness-kit:building-a-feature` |
| Test do / verify truot / feature da ship bi hoi quy | `harness-kit:debugging-a-feature` |
| Nghi la feature xong, sap danh `done` | `harness-kit:verifying-a-feature` |
| Truoc SHIP, hoac dung toi auth / data / secret / input nguoi dung | `harness-kit:security-gate` |
| Feature da qua VERIFY + SECURITY, sap ship | `harness-kit:shipping-a-feature` |
| Viet ho so cho feature vua ship | `harness-kit:writing-feature-dossier` |
| Ket thuc phien | `harness-kit:shipping-a-feature` (muc End of Session) |

Announce `Dung [skill] de [muc dich]` roi lam theo dung skill do. Skill co checklist → tao todo cho tung muc.

> Ten o tren la dang plugin. Neu harness duoc cai theo kieu project-local (`.claude/skills/`),
> bo tien to: `harness-startup`, `building-a-feature`, ...

## Ba guardrail luon bat

- **`/freeze`** — dang sua bug cua F nao thi chi dung file thuoc scope F do.
- **`/careful`** — truoc lenh pha huy (`rm -rf`, `DROP`, `force-push`, `reset --hard`): dung, hoi Homeowner.
- **One feature at a time** — `active_feature` trong `feature_list.json` la feature duy nhat duoc dung toi.

## Red flags — nhung cau nay nghia la ban dang tu bao chua

| Ban nghi | Thuc te |
|---|---|
| "Viec nay nho, khong can gate" | Gate re hon mot phien debug. Invoke skill. |
| "De toi doc code truoc da" | `harness-startup` day ban doc CAI GI truoc. Doc no truoc. |
| "Toi nho harness noi gi roi" | Harness cua project nay co the da doi. Doc file that. |
| "Feature nay khong co gi de test" | Vay `done_when` cua no sai. Sua `done_when`, dung bo qua verify. |
| "Lam luon cho nhanh, gate sau" | Gate sau = khong bao gio gate. |
| "Homeowner dang voi" | Ship do vo ton nhieu thoi gian hon gate. |
| "Toi vua sua 1 dong thoi" | 1 dong van la diff. Diff nao cung qua SHIP gate. |

## Thu tu uu tien

Gate skill di truoc skill ky thuat. `verifying-a-feature` quyet dinh *khi nao* duoc goi la xong;
skill ngon ngu/framework quyet dinh *lam the nao*. Dung de skill thu hai lan at skill thu nhat.

## Quyen uu tien cua con nguoi

Chi thi truc tiep cua Homeowner > skill > hanh vi mac dinh. Chi bo qua workflow khi Homeowner
noi ro rang la bo qua — khong tu suy dien tu viec ho dang voi.
