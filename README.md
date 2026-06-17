# BOW Skills

Bộ **Claude Code skills** dùng chung cho công ty, đóng gói thành một **plugin marketplace**.
Mỗi thành viên cài một lần là có chung quy trình làm việc với Claude.

Skill là *workflow* mà Claude tự kích hoạt theo ngữ cảnh — không phải tài liệu để đọc. Mỗi skill
có trigger riêng trong frontmatter; khi mô tả công việc khớp trigger, Claude áp dụng quy trình đó.

## Hai plugin

| Plugin | Phạm vi | Khi nào cài |
| :-- | :-- | :-- |
| **`bow-core`** | Trung lập, dùng cho **mọi dự án** | Luôn nên cài |
| **`octopus`** | Riêng dự án **Octopus** (app/monorepo) | Chỉ khi làm việc trên Octopus |

## Cài đặt

> Repo này là **private** — mỗi thành viên cần quyền đọc `Bow-T/bow-skills`.

```
/plugin marketplace add Bow-T/bow-skills
/plugin install bow-core@bow-skills
/plugin install octopus@bow-skills      # chỉ khi làm dự án Octopus
```

Sau khi cài, các skill tự xuất hiện và Claude tự chọn theo ngữ cảnh.

## bow-core — skill chung (9)

### Vòng đời phát triển (spec → ship)
| Skill | Khi nào dùng |
| :-- | :-- |
| `spec-driven-development` | Viết spec gắn ticket trước khi code. |
| `planning-and-task-breakdown` | Tách spec thành task, 1 feature branch / unit. |
| `test-driven-development` | TDD (`*_test.dart`, `*.spec.ts`…). |
| `debugging-and-error-recovery` | Truy root-cause; verify runtime, không chỉ static green. |
| `code-simplification` | Dọn code thừa, giữ nguyên hành vi. |
| `security-and-hardening` | Hardening **app-layer** (mobile/web/payment). DB-layer dùng skill review riêng. |

### Tích hợp Stripe
| Skill | Khi nào dùng |
| :-- | :-- |
| `stripe-best-practices` | Quyết định tích hợp Stripe (Checkout vs PaymentIntents, Connect, webhook, key…). |
| `stripe-projects` | Provision hạ tầng/dịch vụ qua Stripe Projects. |
| `upgrade-stripe` | Nâng cấp Stripe API version / SDK. |

## octopus — skill riêng dự án Octopus (3)

| Skill | Khi nào dùng |
| :-- | :-- |
| `octopus-commit` | Commit + push theo pipeline commit của Octopus (safety scan → analyze → Conventional Commit + ticket ref). |
| `octopus-ui` | Dựng/sửa UI & page Flutter theo kiến trúc MVVM (BaseViewModel + MixinBasePage). |
| `supabase-security-review` | Audit thay đổi Supabase (RLS, view, trigger, edge fn, SQL) trước khi commit. |

## Cấu trúc

```
.claude-plugin/
  marketplace.json          # định nghĩa marketplace + liệt kê 2 plugin
plugins/
  bow-core/
    .claude-plugin/plugin.json
    skills/<skill>/SKILL.md
  octopus/
    .claude-plugin/plugin.json
    skills/<skill>/SKILL.md
```

## Đóng góp

- Skill chung → `plugins/bow-core/skills/`. Skill riêng một dự án → tạo plugin riêng (như `octopus`).
- Mỗi skill = 1 thư mục chứa `SKILL.md` với frontmatter `name` + `description`.
- `description` phải nêu rõ **khi nào** kích hoạt (trigger) để Claude route đúng.
- **Không** nhúng thông tin nội bộ nhạy cảm vào `bow-core` (giữ trung lập, có thể public sau này).

Xem [ATTRIBUTION.md](ATTRIBUTION.md) cho nguồn gốc các skill bên thứ ba.
