# 迁移指南：把已有机器切到公私分离

面向已经在用 DFM、且私有内容混在 base clone 里的机器（典型：公司电脑）。
结论先放前面：**顺序必须是「先建 overlay、后拉新 base」**，反过来就一定断。

---

## 1. 为什么会有鸡生蛋风险

旧机器的状态：

- `interop` 模块是未跟踪文件，但 `~/.config/interop`、`~/.local/bin/git-credential-wsl-gcm` 已经链到它
- conda 块写死在 base 的 `dot-bashrc` 里
- 可能还有其它本地改动（代理、公司路径、内网地址）

新 base 会：删掉 conda 块、把 rc 改成只 source `~/.config/shell.d/*.sh`。

于是：

| 先做的事 | 后果 |
|---|---|
| 先拉新 base | rc 不再加载 conda；interop 的 source 行消失 → PATH 白名单和 conda 立刻失效 |
| 先建 overlay | 只依赖旧 clone 里的文件，不依赖新 base；新 DFM 随 base 一起到，无需提前安装 |

所以正确顺序是 **overlay → 链接 → 清理 base → 拉 base → 新 dfm 接管**。

关键设计保证：**overlay 同时提供新旧两条加载路径**。

- 旧 rc 直接 source `~/.config/interop/interop-path.sh`
- 新 rc source `~/.config/shell.d/*.sh`
- overlay 里既有 `~/.config/interop/` 的实体，也有 `shell.d/20-windows-interop.sh` 垫片

因此切换过程中任何时刻都有东西可加载，不会出现“两边都没有”的空窗。

---

## 2. 新机器（干净环境）

```sh
git clone <base-url> ~/dotfiles
git clone <overlay-url> ~/dotfiles-<名字>
dfm init          # 询问这台机器能否推 base
dfm link
```

---

## 3. 旧机器（以公司电脑为例）

### 3.1 盘点本地私有内容

```sh
cd ~/dotfiles
git status          # 本地修改 / 未跟踪文件
git diff            # 逐行判断：这行是公司事实，还是通用配置？
```

归类原则：

- shell 里的一行/一段（代理、PATH、conda）→ 写成 `shell.d/NN-xxx.sh`
- 一整块文件或目录（interop、公司工具）→ 原样复制成 overlay 模块

> **不要用 `git stash` 暂存私有改动**：文件会从工作树消失，已经建好的软链会立刻悬空。
> 正确做法是复制到 overlay，再处理 base。

### 3.2 建 overlay 仓库（不需要新 DFM）

```sh
mkdir -p ~/dotfiles-company && cd ~/dotfiles-company
git init -b main
mkdir -p dfm-dotfiles/<模块>/dot-config/shell.d
# 把 interop、公司专属文件复制进来；shell 片段写成 NN-*.sh
git add -A && git commit -m "overlay: company seed"
```

约定：

- 模块名不要和 base 重名（base 用的是 bash/zsh/nvim/wezterm/tealdeer）
- overlay 不含 `DFM.sh`，统一用 base 那份

### 3.3 先把链接切到 overlay（此时 base 还没动）

```sh
cd ~/dotfiles
stow -D -d dfm-dotfiles -t ~ --dotfiles <旧私有模块>          # 摘掉 base 的链接
stow -d ~/dotfiles-company/dfm-dotfiles -t ~ --dotfiles <模块...>   # 换成 overlay 的
```

旧 dfm 也能摘链接（`dfm unlink <模块>`），但它不认识第二个根，所以链接 overlay 这步直接调 `stow`。

检查点：`ls -l ~/.config/<模块>` 已指向新 overlay；开一个新 shell，PATH、凭据、conda 都正常。

### 3.4 清掉 base 里的私有痕迹，再拉新 base

```sh
cd ~/dotfiles
git checkout -- .          # 丢弃已被 overlay 接管的本地改动
git clean -nd dfm-dotfiles # 先干跑，确认要删的只是已搬走的未跟踪文件
git clean -fd dfm-dotfiles # 确认无误再删
git fetch origin
git merge --ff-only origin/main
```

先清理再 pull，保证 fast-forward 不被本地改动挡住。

### 3.5 新 dfm 接管

```sh
dfm repo list      # 应该看到 base + overlay 两个根
dfm link           # 多根一起链接
```

新 dfm 尚未实现前，这一步等价于跑两次 `stow -d <根>/dfm-dotfiles -t ~ --dotfiles <模块...>`。

### 3.6 验证清单

- 新 shell：`PATH` 含 `/mnt/...` 白名单、`conda` 可用、`opencode` 可用、`dfm` alias 在
- `printf 'protocol=https\nhost=github.com\n\n' | git credential fill` 能取到凭据
- base 仓库 `git status` 干净；overlay 仓库干净
- `~` 下没有指向不存在文件的软链（悬空链接）

---

## 4. 失败模式与恢复

都不涉及数据丢失，最坏也能回到旧状态：

| 情况 | 现象 | 恢复 |
|---|---|---|
| 先拉了新 base | conda 不在 PATH、Windows 白名单失效 | overlay 仍在（或补建），加 `shell.d` 片段后开新 shell |
| overlay 建错 | 链接指向错误内容 | 删 overlay 目录，`stow -D` 摘掉，回到 base 旧提交（`git show c12fac8:dfm-dotfiles/bash/dot-bashrc`）重链 |
| 清理过早 | base 里已无私有文件 | overlay 里有一份；或从 `overlay-seed` 分支/历史里取回 |

---

## 5. 回滚

```sh
# base 回到瘦身前
git -C ~/dotfiles reset --hard c12fac8

# overlay 整体撤销
stow -D -d ~/dotfiles-<名字>/dfm-dotfiles -t ~ --dotfiles <模块...>
rm -rf ~/dotfiles-<名字>

# 系统侧 interop（内容未变，重装只是为了刷新 /usr/local/sbin 副本）
sudo bash ~/.config/interop/install-system.sh
```

---

## 6. 本机（home）已经走完的路径

作为参考，这台机器上实际执行的顺序是：

1. `git branch overlay-seed`：把 interop + conda + shell.d 垫片提交到一个只含 overlay 内容的分支
2. `git archive overlay-seed | tar -x -C ~/dotfiles-home` → `git init` → overlay 仓库（remote 已指向私有仓库）
3. `dfm unlink interop` + `stow -d ~/dotfiles-home/dfm-dotfiles -t ~ --dotfiles interop shell`
4. base 的 rc 加 `shell.d` 加载器、删 conda 块、`alias dfm` 用 `$HOME`、tealdeer 路径改 `~/.tldr`
5. 验证：interactive bash/zsh 都能拿到 conda、Windows 白名单、凭据

公司机器可以照抄，只是把 `home` 换成 `company`，并在 3.4 之前确认 overlay 已经能提供所有旧功能。
