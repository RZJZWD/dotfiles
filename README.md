# dotfiles

公私分离的配置管理：一个可公开的**基座（base）**，加上每台机器各自的**私有覆盖层（overlay）**，由 `DFM.sh` 负责链接与 git 操作。

```
~/dotfiles        base（通用配置 + DFM.sh）
~/dotfiles-<名字> overlay（机器私有配置，独立 git 仓库）
```

> 迭代中：多根、`dfm repo/update/push/status` 尚未实现。

文档：

- [docs/design.md](docs/design.md) — 设计（公私分离、契约、DFM 命令）
- [docs/migration.md](docs/migration.md) — 已有机器迁移（先 overlay 后 base）
- [docs/runbook.md](docs/runbook.md) — 按任务的操作手册
- [AGENTS.md](AGENTS.md) — 给 AI agent 的常驻约束
- [skills/dfm-ops/SKILL.md](skills/dfm-ops/SKILL.md) — 同一套规则的可加载技能
