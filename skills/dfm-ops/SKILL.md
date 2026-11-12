---
name: dfm-ops
description: 维护公私分离的 dotfiles 基座（base + 私有 overlay）：判断配置该放哪、新增或迁移 overlay、排查 shell/凭据/悬空链接问题、安全更新 base。
---

# DFM 运维

这个仓库是**基座（base）**，每台机器另有**私有 overlay** 仓库（如 `~/dotfiles-home`），由 GNU Stow 链接进 `$HOME`。

## 先读

- 硬性约束：[AGENTS.md](../../AGENTS.md)
- 按任务操作：[docs/runbook.md](../../docs/runbook.md)
- 设计与迁移：[docs/design.md](../../docs/design.md)、[docs/migration.md](../../docs/migration.md)

## 三条最容易犯的错

1. 把环境事实（`/mnt`、盘符、`/home/<用户名>`、代理、内网地址、安装器 PATH）写进 base。
   → 写进 overlay 的 `~/.config/shell.d/NN-*.sh`，或做成 overlay 模块。
2. 迁移旧机器时先拉新 base。→ 必须**先建 overlay 并链接，再拉 base**。
3. `git stash` 私有改动。→ 文件从工作树消失，stow 链接立刻悬空；应复制进 overlay。

## 最小验证

```sh
# 新开一个 interactive bash 和 zsh，确认 PATH / alias / 工具
# 悬空链接
find "$HOME" -maxdepth 4 -type l -lname '*dotfiles*' 2>/dev/null | while read -r l; do
  [ -e "$l" ] || echo "DANGLING: $l"
done
```

改过 git/凭据时，再确认 `git credential fill` 能取到凭据。

## 边界

- 不自动 commit / push / merge
- 不自动执行仓库里的 `install-*`（提示人工 `sudo`）
