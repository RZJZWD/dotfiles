# ======================================
# 📌 自定义补全注册（集中管理）
# ======================================
# 此文件在 .zshrc 中手动 source，时机在 Zinit 加载后、异步插件列表前。
# 每个补全格式：autoload -U _<command> && compdef _<command> <command>
# ======================================

autoload -U _tldr && compdef _tldr tldr

# 未来可在此添加其他补全，例如：
# autoload -U _kubectl && compdef _kubectl kubectl
