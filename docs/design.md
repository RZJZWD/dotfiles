# 设计：公私分离的 dotfiles 基座

一个**可公开的配置基座（base）** + 若干**私有的环境覆盖层（overlay）**，用 git 管理，用 DFM 组合到 `$HOME`。

一句话原则：**基座管通用，覆盖层管环境；配置管配置，应用管应用。**

> 设计已基本落地：`shell.d`、多根、`dfm repo/update/push/status` 均已实现。剩余项见 §9。

---

## 0. 适用范围与非目标

**面向**：熟悉自己的配置、需要把「公开通用部分」和「某台机器的私有部分」分开的人。

- 一台机器 = base + 本机私有 overlay（都是自己的仓库）
- 多台机器 = 同一个 base + 每台一个 overlay，各自演进、互不合并

**非目标**（明确不做）：

- **插件 / 配置分发**：overlay 不是第三方仓库，不提供插件 API、版本约束、签名校验
- 多人协作、团队共享配置
- 自动 commit / merge / 解决冲突
- 跨平台包管理（装软件仍是各机器自己的事）

**推论**：

- overlay 视为**受信**（它是你自己的仓库），DFM 不做隔离或审计
- `dfm repo add` 的语义是「在另一台机器上恢复我自己的 overlay」，不是「安装别人的配置包」
- `shell.d` 是加载顺序约定，不是插件接口
- overlay 本身在设计上可以当作插件用，但那超出本文范围

---

## 1. 核心思想

1. **公私分离**
   base 里只放"陌生人在自己机器上 clone 也能直接用"的东西；凡是环境事实（`/mnt/c`、盘符、`/etc` 改动、内网地址、安装目录、密钥）一律进私有 overlay。
   注意这是一条**纯度纪律**，不是分发目标：即使 base 不公开，也按"可公开"的标准要求它，杂物就自然会落进 overlay。

2. **基座与私有设置分离**
   base 不知道 overlay 的存在，只提供通用的扩展点（见 §4.2）。overlay 只做增量，不覆盖 base 管理的文件。

3. **配置管配置，应用管应用**
   shell 配置不点名具体应用的安装目录。应用通过标准目录（`~/.local/bin`）或自己的 drop-in 文件出现在环境里。

4. **git 是唯一持久层**
   每份配置都是一个普通 git 仓库，GitHub / 私有 GitHub / 自建 GitLab 只是 remote 的差别。同步 = fetch / pull；发布 = push。

5. **DFM 只做两件事**
   把仓库文件链接到 `$HOME`（GNU Stow）；把 git 的拉取与推送包装成一条命令。不做同步魔法，不自动提交。

---

## 2. 模型

```
              ┌───────────────────────────────┐
              │ base（public）                 │
              │ 通用默认值 + 扩展点             │
              └───────────┬───────────────────┘
                          │ fetch / push
                          ▼
              ┌───────────────────────────────┐
              │ overlay（本机唯一，私有 Git）    │
              │ 环境事实 / 私人工具             │
              └───────────────────────────────┘
```

每台机器**恰好两个根**：`base` 与 `overlay`，都经 DFM 链接进 `$HOME`。

- `overlay` 一机一个，出现第二个是**配置错误**，DFM 直接报错
- 目录名（`dotfiles-home` / `dotfiles-work`）只是这台机器的标识，角色固定是 `overlay`
- 根集合不再自由枚举：DFM 不区分“家里”“公司”，差异只有 overlay 的目录名和 base 的推送权
- 两个根各自独立演进，不需要分支、不需要 rebase

---

## 3. 归属契约

判据：**这条配置让陌生人在自己机器上 clone 下来，会不会出错、泄露或困惑？** 会 → overlay。

| 内容 | base | overlay |
|---|---|---|
| bash / zsh 通用设置、别名、补全 | ✅ | 只做增量 |
| `~/.local/bin` 加入 PATH | ✅ | — |
| nvim / wezterm / tealdeer 通用配置 | ✅ | 机器相关覆盖 |
| `/mnt/c/...`、盘符、`/etc` 改动 | ❌ | ✅ |
| conda、opencode、代理、内网镜像 | ❌ | ✅ |
| 机器名判断、hostname 分支 | ❌ | ✅ |
| 密钥、token、密码 | ❌ 永不 | ❌ 永不（用系统钥匙串 / 环境变量） |

base 的验收标准：

- 干净机器 `git clone` + `dfm link` 后 bash / zsh 可用
- base 内除文档外不出现 `/mnt`、`/home/<用户名>`、盘符、内网域名
- base 不执行脚本、不改系统文件

---

## 4. 组合机制

### 4.1 根 = 目录约定，能力 = git 状态

DFM 不维护任何配置文件。两件事都从已有事实里读：

**根（root）**：设计上只有两个角色，名字固定：

```
base     = DFM 脚本所在目录（约定 ~/dotfiles）
overlay  = 本机唯一一个 ~/dotfiles-<名字>
```

- `overlay` 一机一个；发现第二个 `~/dotfiles-*` 直接报错，不提供“选一个”的选项
- 目录名（`dotfiles-home` / `dotfiles-work`）只用于展示，角色仍是 `overlay`
- `--root` 只接受 `base` / `overlay`（兼容 overlay 的目录名作为别名）
- 加 overlay = `git clone <url> ~/dotfiles-<名字>`；本机已有 overlay 时 `dfm repo add` 会拒绝
- 每个目录都是**独立 git 仓库**，各自管理自己的 remote、分支和历史，互相不感知
- `~/dotfiles/.gitignore` 里把 `dotfiles-*/` 兜底忽略：同级目录本来就不在 base 的仓库里，这条只防有人把 overlay clone 进 base 工作树时污染 `git status`

**推送能力**：就是那个仓库自己的 `remote.*.pushurl`，git 原生表达。

```sh
git remote set-url --push origin DISABLED    # 只读
```

`git remote -v` 就是唯一真相，DFM 不另存一份声明；`dfm status` 直接显示每个根能否推送。

- **overlay 永远可推**：它就是你在这台机器上维护的私有仓库，origin 自带推送地址，不需要开关
- **base 的推送权是本机决策**：`dfm init` 时确定（`--push-base` / `--no-push-base`，默认询问且缺省不可推），之后随时用 `dfm repo readonly|writable base` 增删

**换一台机器**，只是 overlay 的目录名、以及 base 推不推不同，没有任何声明文件要改。

规则：

- `dfm update`：两个根各自 `git pull --ff-only`，非 git 根跳过
- `dfm push`：两个根各自尝试推送；pushurl 被禁用/为空时报告 `skipped (read-only)`，不算失败
- 没有 overlay 时只剩 base，命令照常（此时 `dfm add` 必须显式 `--root base`）
- 模块名在 base / overlay 之间唯一，重名直接报错
- 文件级冲突交给 stow 报错（护栏，不吞错）

### 4.2 扩展点：shell.d

base 的 rc 只留一个通用 hook，不知道里面是谁：

```sh
# bash
for _f in "$HOME"/.config/shell.d/*.sh; do
    [ -e "$_f" ] || continue
    . "$_f"
done
unset _f
```

```zsh
# zsh（空 glob 需 (N)，否则目录不存在会报错）
for _f in "$HOME"/.config/shell.d/*.sh(N); do
    . "$_f"
done
unset _f
```

overlay 往 `~/.config/shell.d/` 放文件即可，数字前缀决定加载顺序：

```
10-work.sh
20-windows-interop.sh
30-conda.sh
```

扩展点保持克制：**目前只有 `shell.d`**。新增扩展点需要先讨论它是否真的通用。

---

## 5. DFM 命令

| 命令 | 行为 |
|---|---|
| `dfm link [模块]` | 遍历所有根，链接全部模块或指定模块 |
| `dfm unlink [模块]` | 反向操作 |
| `dfm list` | 按根分组列出模块 |
| `dfm add [--root <根>] <源> [模块]` | 移入 overlay（默认）并立即链接；写 base 需 `--root base` |
| `dfm remove [--root <根>] [--force] <模块>` | 把模块移回 `$HOME`（`add` 的逆操作） |
| `dfm repo list` | 列出发现的根、分支、remote、能否推送 |
| `dfm repo add <url> [名字]` | clone 到 `~/dotfiles-<名字>`，随后 link（用于在新机器上恢复自己的 overlay） |
| `dfm repo pushurl <根> <url>` | 给根追加 push URL（fetch 与 push 分离） |
| `dfm repo readonly <根>` | 删除该根的推送（`pushurl=DISABLED`） |
| `dfm repo writable <根>` | 恢复该根的推送（去掉 pushurl 覆盖） |
| `dfm update [--dry-run]` | 每个根 `git pull --ff-only`，随后重新链接；输出报告 |
| `dfm push [--dry-run]` | 每个根 `git push`，只读根跳过；工作区脏则拒绝 |
| `dfm status` | 每个根的分支、ahead/behind、脏状态、推送能力、模块数 |
| `dfm init [别名] [--push-base\|--no-push-base]` | 初始化：写别名、建目录；同时确定 base 是否可推（默认询问，缺省不可推） |

硬性约束：

- **不维护第二份状态**：根从文件系统发现，推送能力从 `pushurl` 读，DFM 不存任何清单
- **只接受 fast-forward**：`update` 绝不 merge / rebase / force
- **不执行仓库脚本**：pull 下来的内容只当数据，不自动运行（安全）
- **不自动提交**：提交永远手动，避免把临时改动一并吞掉
- **不碰 `/etc`**：系统级安装永远是显式 `sudo` 手工步骤
- **默认不联网**：只有 `update` / `push` 会访问 remote

可选"无感更新"：WSL 已启用 systemd，可加 user timer 周期性执行 `dfm update --quiet`。

---

## 6. 目录结构

base：

```
dotfiles/
├── DFM.sh
├── README.md         # 仓库介绍（实现稳定后补写）
├── docs/design.md    # 本文
├── .gitignore        # 兜底忽略 dotfiles-*/
└── dfm-dotfiles/
    ├── bash/dot-bashrc
    ├── zsh/dot-zshrc, dot-p10k.zsh, ...
    ├── nvim/dot-config/nvim/...
    ├── wezterm/dot-config/wezterm/...
    └── tealdeer/dot-config/tealdeer/...
```

overlay（本机唯一；目录名随机器不同，内容只放这台机器的事实）：

```
dotfiles-home/
└── dfm-dotfiles/
    ├── interop/
    │   ├── dot-config/interop/{interop-path.sh,install-system.sh}
    │   └── dot-local/bin/git-credential-wsl-gcm
    └── shell/
        └── dot-config/shell.d/{20-windows-interop.sh,30-conda.sh}
```

overlay 仓库**不包含 `DFM.sh`**，统一使用 base 里那一份；overlay 只有 `dfm-dotfiles/<模块>/`。

---

## 7. 日常流程

**首次（任意机器）**

```sh
git clone <base-url> ~/dotfiles
git clone <overlay-url> ~/dotfiles-home

dfm init          # 询问：这台机器可以推 base 吗？（默认 N）
dfm link          # 自动发现所有根并链接
```

init 的答案直接落到 git 上，之后随时可改：

```sh
dfm repo readonly base     # 删除推送（等价于 git remote set-url --push origin DISABLED）
dfm repo writable base     # 恢复推送（去掉 pushurl 覆盖）
```

**基座更新（有 base 推送权的机器）**

```sh
dfm status        # 看各根是否干净
dfm push          # 逐根推送，只读根自动跳过
```

**base 只读的机器**

```sh
dfm update        # 所有 git 根统一拉取
dfm push          # 只推可写的根；base 报 skipped
```

**从只读机器回流通用改进**
只读机器上对 base 的改动推不出去，所以通用改动先在本机 overlay 里提交，
再用 `git format-patch` / `git am` 搬到有推送权的机器——这是 pull-only 的固有限制，也是 patch 唯一合理的用途。

---

## 8. 安全边界

- 所有仓库都不存放密钥；密钥走系统钥匙串或环境变量
- base 是受信输入（它最终会进 `~/.bashrc`），因此只允许 fast-forward，且不自动执行
- 公开仓库历史永久可见：私有内容只能进私有仓库，且要假设"推上去即泄露"
- overlay 里的 `install-*` 脚本一律手动执行，DFM 不代跑

---

## 9. 迁移清单

从当前单仓状态迁移到本设计：

- [x] base 去掉 `/home/djs` 硬编码（conda 块、`alias dfm`、tealdeer 路径）
- [x] base 的 rc 换成 `shell.d` 循环，删除 interop 的 source 行
- [x] base 的私有内容移入 overlay 种子分支 `overlay-seed`；本机 overlay 仓库已建（`~/dotfiles-home`，暂无 remote）
- [x] 系统侧 interop 内容未变，`/usr/local/sbin/wsl-interop-apply` 无需重跑
- [x] DFM 增加根发现、`repo` 子命令与 `update` / `push` / `status`
- [ ] 其它机器（如公司电脑）照 [migration.md](migration.md) 迁移，并建各自 overlay
- [ ] 实现稳定后补写仓库 README（安装、用法、目录说明）

---

## 10. 取舍

- **stow `--no-folding`**：放弃目录折叠，链接拓扑固定（逐文件）；代价是模块内新增文件后要 `dfm link <模块>`
- **多仓 vs 多分支**：每个根是独立仓库，没有 rebase，各自演进；代价是多一个 remote、多一次 push
- **不用 submodule**：submodule 把 overlay 钉在 base 的某个 commit 上，而两者需要独立演进
- **不自动 commit / push**：宁可多一步，也不替用户做决定
- **扩展点宁少勿多**：`shell.d` 够用之前，不加第二个 hook
