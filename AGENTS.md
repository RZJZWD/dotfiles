# AGENTS.md

给在此仓库工作的 AI agent 的常驻约束。按任务操作时再看 [docs/runbook.md](docs/runbook.md)。

## 这是什么仓库

公私分离的 dotfiles：

- **base**（本仓库，可公开）：通用配置 + `DFM.sh` + 文档
- **overlay**（每台机器**有且只有一个**私有仓库，如 `~/dotfiles-home`）：环境事实、私有工具
- `DFM.sh` 负责 GNU Stow 链接，以及（目标态）git 拉取/推送

设计见 [docs/design.md](docs/design.md)，旧机器迁移见 [docs/migration.md](docs/migration.md)。

## 硬性不变量

1. **base 不含环境事实**：`/mnt/...`、盘符、`/home/<用户名>`、内网域名、代理、安装器写的 PATH、任何密钥/token。
   判据：陌生人 clone 后直接用，会不会出错、泄露或困惑？会 → overlay。
2. **overlay 只做增量**：新增模块或 `~/.config/shell.d/*.sh` 片段，不覆盖 base 管理的文件。stow 冲突是护栏，不要绕过或强推。
3. **绝不自动 commit / push / merge**。改动做完让人确认后再提交。
4. **绝不自动执行仓库里的脚本**；`install-*` 一律提示人工 `sudo` 执行。
5. **shell 扩展只走 `~/.config/shell.d/`**；不要在 base 的 rc 里点名具体应用或环境。
6. **迁移已有机器必须「先 overlay、后 base」**（见 docs/migration.md）；不要用 `git stash` 暂存私有改动，文件消失会让软链悬空。

## 加载机制

`dfm-dotfiles/<模块>/dot-xxx` 经 `stow -d dfm-dotfiles -t ~ --dotfiles <模块>` 映射成 `~/.xxx`。
`dot-config/shell.d/*.sh` 由 base 的 bashrc/zshrc 按文件名顺序 source。

## 改完必须验证

- 新开 interactive bash 和 zsh：PATH、别名、函数正常
- `~` 下没有悬空软链（指向不存在文件的链接）
- 改过 git/凭据相关时：`printf 'protocol=https\nhost=github.com\n\n' | git credential fill` 能取到凭据
- `git status` 干净，只提交预期文件

## 当前实现状态

- `DFM.sh` 只有两个根：base（脚本所在目录）与 overlay（本机唯一的 `~/dotfiles-*`）；命令有 `link/unlink/list/status/repo/update/push/add/remove`
- 推送能力只存在于 git：`pushurl=DISABLED` 即只读，`dfm push` 会自动跳过
- 根只有两个角色：`base` / `overlay`；`--root` 接受这两个名字（兼容 overlay 目录名）
- `dfm add` 默认写 overlay 并立即链接；`dfm remove` 是其逆操作，把模块搬回 `$HOME`
- 本机 overlay：`~/dotfiles-home`，remote 为私有仓库 `https://github.com/RZJZWD/dotfiles-home.git`
