# 操作手册

按任务查。设计背景见 [design.md](design.md)，旧机器迁移见 [migration.md](migration.md)。
给 AI 的常驻约束见仓库根目录的 [AGENTS.md](../AGENTS.md)。

## 0. 当前实现状态

- `DFM.sh` 仍是单根：`init / add / link / unlink / alias / list`
- `dfm repo` / `update` / `push` / `status` 尚未实现
- 因此 **overlay 目前用裸 stow 链接**：

```sh
stow -d ~/dotfiles-<名字>/dfm-dotfiles -t ~ --dotfiles <模块...>
```

等 DFM 多根落地后，统一改成 `dfm link`。

---

## 任务 A：给本机新增一个 overlay

```sh
mkdir -p ~/dotfiles-<名字> && cd ~/dotfiles-<名字>
git init -b main
mkdir -p dfm-dotfiles/<模块>/dot-config/shell.d
# 放入片段，例如 dfm-dotfiles/<模块>/dot-config/shell.d/10-<名字>.sh
git add -A && git commit -m "overlay: <名字> seed"
stow -d dfm-dotfiles -t ~ --dotfiles <模块>
```

验证：新开 shell，`echo $PATH`、`alias`、`command -v <工具>` 符合预期。

## 任务 B：加一条「环境相关」的配置

判断：这条配置换台机器就对吗？不对 → overlay。

1. 在 `~/dotfiles-<名字>/dfm-dotfiles/<模块>/dot-config/shell.d/` 新建 `NN-<名字>.sh`
2. 片段里只写本机事实（路径、代理、内网地址）
3. 提交 overlay 仓库，然后 `stow -d ... -t ~ --dotfiles <模块>` 重链（或直接改已链接的文件）

**不要**去改 base 的 `dot-bashrc` / `dot-zshrc`。

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
