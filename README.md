# dotfiles

公私分离的配置管理：一个可公开的**基座（base）**，加上每台机器各自的**私有覆盖层（overlay）**，由 `DFM.sh` 负责链接与 git 操作。

```
~/dotfiles        base（通用配置 + DFM.sh）
~/dotfiles-<名字> overlay（机器私有配置，独立 git 仓库）
```

> 迭代中：多根、`dfm repo/update/push/status` 尚未实现。
> 设计依据见 [docs/design.md](docs/design.md)；仓库介绍、安装步骤与用法等实现稳定后再补。
