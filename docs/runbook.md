# 操作手册

按任务查。设计背景见 [design.md](design.md)，旧机器迁移见 [migration.md](migration.md)。
给 AI 的常驻约束见仓库根目录的 [AGENTS.md](../AGENTS.md)。

## 0. 当前实现状态

- `DFM.sh` 只有两个根：base + 本机唯一的 overlay（`~/dotfiles-*`）
- overlay 和 base 一样用 `dfm link` 链接；`dfm status` 看各根状态
- 推送能力由各仓库的 `pushurl` 决定，`dfm push` 自动跳过只读根

---

## 任务 A：给本机新增 overlay

一台机器**只能有一个** overlay；已经有 `~/dotfiles-*` 时，`dfm repo add` 会拒绝，应直接在旧仓库里更新。

```sh
mkdir -p ~/dotfiles-<名字> && cd ~/dotfiles-<名字>
git init -b main
mkdir -p dfm-dotfiles/<模块>/dot-config/shell.d
# 放入片段，例如 dfm-dotfiles/<模块>/dot-config/shell.d/10-<名字>.sh
git add -A && git commit -m "overlay: <名字> seed"
dfm link <模块>
```

验证：新开 shell，`echo $PATH`、`alias`、`command -v <工具>` 符合预期。

## 任务 B：在 overlay 里加 / 改配置

判断：这条配置换台机器就对吗？不对 → overlay。

**改已有配置**：直接编辑 `~` 下的链接即可，写入落在 overlay：

```sh
$EDITOR ~/.config/shell.d/30-conda.sh
git -C ~/dotfiles-<名字> add -A && git -C ~/dotfiles-<名字> commit -m "overlay: ..."
dfm push          # 只推可写的根
```

**新增文件**：默认就写进 overlay，不用指定根：

```sh
dfm add ~/.config/<工具> <模块>      # 移入 overlay 并立即链接
git -C ~/dotfiles-<名字> add -A && git -C ~/dotfiles-<名字> commit -m "overlay: ..."
dfm push
```

只有真要改 base 时才需要 `--root base`。

**新增一条 shell 片段**：在 overlay 的 `<模块>/dot-config/shell.d/` 下建 `NN-<名字>.sh`，
然后 `dfm link <模块>` 重链。

> 链接是**逐文件**的（stow `--no-folding`），所以任何模块里新增/删除/改名文件，都要跑一次
> `dfm link <模块>`；`dfm unlink` 会顺带清掉空的目录骨架。

**移出模块**（`add` 的逆操作，文件搬回 `$HOME`）：

```sh
dfm remove <模块>                # 默认从 overlay 移出
dfm remove --root base <模块>    # 从 base 移出
# 目标位置已有真实文件时会拒绝；确认覆盖加 --force
```

移出后仓库里是未提交的删除，确认无误再 commit。

**不要**去改 base 的 `dot-bashrc` / `dot-zshrc`；`dfm add` 默认写 overlay，写 base 必须 `--root base`。

## 任务 C：加一条「通用」的配置

改 base，提交前过一遍：

```sh
git grep -nE '/mnt/|/home/[a-z]+/|[A-Za-z]:\\\\|token|secret' || true
```

命中就说明有环境事实混进来了，挪去 overlay。

## 任务 D：迁移一台旧机器

完整步骤见 [migration.md](migration.md)。浓缩成顺序：

```sh
# 1. 盘点
cd ~/dotfiles && git status && git diff

# 2. 建 overlay，把私有内容复制进去（不要 stash！）
# 3. 摘掉 base 旧链接，换成 overlay 链接
stow -D -d ~/dotfiles/dfm-dotfiles -t ~ --dotfiles <旧私有模块>
stow -d ~/dotfiles-<名字>/dfm-dotfiles -t ~ --dotfiles <模块>

# 4. 清掉 base 的本地改动/未跟踪私有文件，再 ff-only 拉新 base
git checkout -- . && git clean -nd dfm-dotfiles && git clean -fd dfm-dotfiles
git fetch origin && git merge --ff-only origin/main

# 5. 验证
```

## 任务 E：排查

| 现象 | 先查什么 | 常见原因 |
|---|---|---|
| 新 shell 里 `/mnt/...` 不见了 | `ls -l ~/.config/shell.d`、`ls -l ~/.config/interop` | shell.d 没链上；overlay 没链 |
| `conda` 找不到 | `~/.config/shell.d/30-conda.sh` 是否存在、`$HOME/miniconda3` 是否存在 | overlay 未链接；conda 装在别的路径 |
| `git` 拉私有仓库失败 / 弹凭据 | `git config --get credential.helper`、`ls -l ~/.local/bin/git-credential-wsl-gcm` | GCM 桥没链上 |
| 有悬空软链 | 见下方检查脚本 | 模块被删/改名，链接没摘 |
| `dfm` 报错 | `dfm` alias 指向的路径是否存在 | base 挪了位置 |
| `remove` 报「是目录，不会覆盖目录」 | `$HOME` 下目标路径被真实目录占用 | 先改名/删除该目录，再 `remove` |
| `unlink` 说「当前未链接」 | 模块本来就没链上 | 无需处理，属正常提示 |

悬空链接检查：

```sh
find "$HOME" -maxdepth 4 -type l -lname '*dotfiles*' 2>/dev/null | while read -r l; do
    [ -e "$l" ] || echo "DANGLING: $l"
done
```

## 任务 F：更新 base 并验证

```sh
cd ~/dotfiles
git status                 # 必须干净；脏就先处理，不要直接 pull
git pull --ff-only
```

拉完开两个新 shell（bash、zsh）确认 PATH / 别名 / 工具都在；有 `shell.d` 变化时再看一眼 `ls ~/.config/shell.d`。
