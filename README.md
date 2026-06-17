# DUOCT Agent Skills

Bộ **Claude Code skills** dùng chung cho team DUOCT (Digital Unicorn Octopus) khi làm việc
trên monorepo (`apps/mobile` Flutter, `apps/admin` Next.js, `supabase/`, `packages/`).

Skill là *workflow* mà Claude tự kích hoạt theo ngữ cảnh — không phải tài liệu để đọc. Mỗi skill
có trigger riêng trong frontmatter; khi mô tả công việc khớp trigger, Claude sẽ áp dụng quy trình đó.

## Cài đặt

> Repo này là **private**. Mỗi thành viên cần quyền đọc repo `Bow-T/duoct-agent-skills`.

Trong Claude Code:

```
/plugin marketplace add Bow-T/duoct-agent-skills
/plugin install duoct-skills@duoct-agent-skills
```

Sau khi cài, các skill tự xuất hiện và Claude tự chọn theo ngữ cảnh. Có thể gọi tay qua tên skill.

## Danh sách skill (12)

### Đặc thù DUOCT (company conventions)
| Skill | Khi nào dùng |
| :-- | :-- |
| `octopus-commit` | Commit + push theo pipeline "Octopus Mode" (safety scan → flutter analyze → Conventional Commit + Jira ref). |
| `octopus-ui` | Dựng/sửa UI & page Flutter theo kiến trúc MVVM (BaseViewModel + MixinBasePage). |
| `supabase-security-review` | Audit thay đổi Supabase (RLS, view, trigger, edge fn, SQL) trước khi commit. |

### Vòng đời phát triển (spec → ship)
| Skill | Khi nào dùng |
| :-- | :-- |
| `spec-driven-development` | Viết spec gắn ticket DUOCT-XXX trước khi code. |
| `planning-and-task-breakdown` | Tách spec thành task, 1 branch `feat/DUOCT-XXX` / unit. |
| `test-driven-development` | TDD cho `*_test.dart` / `*.spec.ts`; hỗ trợ chỉ số Test Discipline. |
| `debugging-and-error-recovery` | Truy root-cause xuyên stack; verify runtime, không chỉ static green. |
| `code-simplification` | Dọn code thừa, giữ hành vi; hỗ trợ chỉ số Codebase Impact. |
| `security-and-hardening` | Hardening **app-layer** (Flutter/Next/Stripe). KHÔNG dùng cho Supabase SQL — xem `supabase-security-review`. |

### Tích hợp Stripe
| Skill | Khi nào dùng |
| :-- | :-- |
| `stripe-best-practices` | Quyết định tích hợp Stripe (Checkout vs PaymentIntents, Connect, webhook, key…). |
| `stripe-projects` | Provision hạ tầng/dịch vụ qua Stripe Projects. |
| `upgrade-stripe` | Nâng cấp Stripe API version / SDK. |

## Cấu trúc

```
.claude-plugin/
  marketplace.json   # định nghĩa marketplace + plugin
  plugin.json        # manifest plugin (trỏ ./skills)
skills/
  <skill>/SKILL.md   # mỗi skill 1 thư mục
```

## Đóng góp

- Mỗi skill = 1 thư mục dưới `skills/`, chứa `SKILL.md` với frontmatter `name` + `description`.
- `description` phải nêu rõ **khi nào** kích hoạt (trigger) để Claude route đúng.
- Sửa skill đặc thù DUOCT thì giữ đồng bộ với `.claude/CLAUDE.md` trong monorepo.

Xem [ATTRIBUTION.md](ATTRIBUTION.md) cho nguồn gốc các skill bên thứ ba.
