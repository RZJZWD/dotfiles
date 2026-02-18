#!/bin/bash
echo "DFM is (D)dot(F)files(M)anager by stow"

# 提升健壮性
set -euo pipefail

# 颜色定义
RED='\033[0;31m'    # 错误
GREEN='\033[0;32m'  # 成功
YELLOW='\033[1;33m' # 提示
BLUE='\033[0;34m'   # 信息
NC='\033[0m' # No Color
# 颜色打印
green() { echo -e "${GREEN}$*${NC}"; }
red() { echo -e "${RED}$*${NC}"; }
yellow() { echo -e "${YELLOW}$*${NC}"; }
blue() { echo -e "${BLUE}$*${NC}"; }

# ===========================================
# 全局变量
# ===========================================
# 获取脚本的绝对路径（简化跨平台方案）
if command -v realpath &>/dev/null; then
    SCRIPT_PATH=$(realpath "$0")
elif command -v readlink &>/dev/null && readlink -f . &>/dev/null; then
    SCRIPT_PATH=$(readlink -f "$0")
else
    # 手动构造绝对路径
    SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
fi
# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
DOTFILES_DIR="${SCRIPT_DIR}/dfm-dotfiles"
SCRIPT_NAME="$(basename "$SCRIPT_PATH")"
# GNU Stow 版本要求
STOW_MIN_VERSION="2.4.0"
# 注释块标识
DFM_COMMENT_START="# ===== DFM Dotfiles Manager - Start ===== #"
DFM_COMMENT_END="# ===== DFM Dotfiles Manager - End ===== #"
# 脚本别名
DEFAULT_ALIAS_NAME="dfm"

# ===========================================
# 工具函数
# ===========================================
# 检查 GNU Stow 版本
check_stow_version() {
    if ! command -v stow &> /dev/null; then
        red "错误：未安装 GNU Stow"
        blue "请安装 GNU Stow ≥ $STOW_MIN_VERSION"
        blue "  Ubuntu/Debian: sudo apt install stow"
        blue "  Fedora/RHEL: sudo dnf install stow"
        blue "  Archlinux: sudo pacman -S stow"
        blue "  macOS (Homebrew): brew install stow"
        return 1
    fi
    
    local stow_version
    # stow_version=$(stow --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' || echo "0")
    # 查看stow版本，并将标准错误输出到黑洞，然后将结果用head取出第一行，再用grep匹配版本号x.x.x或者x.x形式，如果左边命令失败则为0
    stow_version=$(stow --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' || echo "0")

    # if [ "$(printf '%s\n' "$STOW_MIN_VERSION" "$stow_version" | sort -V | head -n1)" != "$STOW_MIN_VERSION" ]; then

    # 各自输出最低版本号和实际版本号到一行，使用sort按顺序排序版本号，head取出第一行也就是两个版本号中最小的。
    # 将最低版本号和处理后的版本号比较，如果最小版本号等于最低版本号，那就没问题，不处理错误
    # 假设最低2.4.0 实际2.3.0，排序结果为2.3.0，2.3.0不等于2.4.0，错误处理
    # 假设最低2.4.0 实际2.5.0，排序结果为2.4.0，2.4.0等于2.4.0，无错误
    if [ "$(printf '%s\n' "$STOW_MIN_VERSION" "$stow_version" | sort -V | head -n1)" != "$STOW_MIN_VERSION" ]; then
        red "错误：GNU Stow 版本过低 ($stow_version < $STOW_MIN_VERSION)"
        blue "请升级 GNU Stow 到 $STOW_MIN_VERSION 或更高版本"
        return 1
    fi
    
    green "✓ GNU Stow 版本检查通过: $stow_version"
    return 0
}

# 移除DFM注释块
remove_dfm_block() {
    local file="$1"
    if [ ! -f "$file" ];then
        return 0
    fi

    # 移除注释块之间的内容（包含注释标记）
    sed -i "/$DFM_COMMENT_START/,/$DFM_COMMENT_END/d" "$file" 2>/dev/null || true
}

# 添加别名到shell配置文件
add_aliases() {
    local alias_name="${1:-dfm}"
    local script_abs_path="$SCRIPT_PATH"
    local alias_cmd="alias $alias_name='$script_abs_path'"
    
    yellow "\n====== 添加别名 ======"
    blue "将为 shell 配置文件添加别名:"
    blue "  $alias_cmd"

    local files_added=0

    # 处理.bashrc
    if [ -f "$HOME/.bashrc" ]; then
        #移除旧的DFM别名块
         remove_dfm_block "$HOME/.bashrc"
        # 添加新的别名块
        {
            echo ""
            echo "$DFM_COMMENT_START"
            echo "$alias_cmd"
            echo "$DFM_COMMENT_END"
            echo ""
        } >> "$HOME/.bashrc"

        green "✓ 已添加别名到 ~/.bashrc"
        files_added=$((files_added + 1))
    else
        yellow "⚠️  未找到 ~/.bashrc 文件"
    fi

    # 处理 .zshrc
    if [ -f "$HOME/.zshrc" ]; then
        # 移除旧的DFM别名块
        remove_dfm_block "$HOME/.zshrc"
        
        # 添加新的别名块
        {
            echo ""
            echo "$DFM_COMMENT_START"
            echo "$alias_cmd"
            echo "$DFM_COMMENT_END"
            echo ""
        } >> "$HOME/.zshrc"
        
        green "✓ 已添加别名到 ~/.zshrc"
        files_added=$((files_added + 1))
    else
        yellow "⚠️  未找到 ~/.zshrc 文件"
    fi

    # 处理 .profile
    if [ -f "$HOME/.profile" ]; then
        # 移除旧的DFM别名块
        remove_dfm_block "$HOME/.profile"
        
        # 添加新的别名块
        {
            echo ""
            echo "$DFM_COMMENT_START"
            echo "$alias_cmd"
            echo "$DFM_COMMENT_END"
            echo ""
        } >> "$HOME/.profile"
        
        green "✓ 已添加别名到 ~/.profile"
        files_added=$((files_added + 1))
    else
        yellow "⚠️  未找到 ~/.profile 文件"
    fi

    # 显示结果
    if [ $files_added -gt 0 ]; then
        yellow "\n====== 别名添加成功 ======"
        blue "注释块标记:"
        echo "  开始: $DFM_COMMENT_START"
        echo "  结束: $DFM_COMMENT_END"
        
        blue "\n使用以下命令使别名生效:"
        local current_shell=$(basename "$SHELL")
        case "$current_shell" in
            "bash")
                green "  source ~/.bashrc"
                ;;
            "zsh")
                green "  source ~/.zshrc"
                ;;
            *)
                yellow "当前 shell: $current_shell"
                blue "请根据您的配置文件执行:"
                [ -f "$HOME/.bashrc" ] && green "  source ~/.bashrc"
                [ -f "$HOME/.zshrc" ] && green "  source ~/.zshrc"
                [ -f "$HOME/.profile" ] && green "  source ~/.profile"
                ;;
        esac
        
    else
        yellow "\n没有成功添加任何别名"
        blue "您可以在 shell 配置文件中手动添加:"
        blue "  $DFM_COMMENT_START"
        blue "  $alias_cmd"
        blue "  $DFM_COMMENT_END"
    fi
    
    return $files_added    
}

# 生成目标相对路径（从绝对路径转换为适合仓库存储的路径）
# 严格遵循 stow --dotfiles 规则：将路径中所有以点开头的组件替换为 dot- 前缀
generate_target_rel_path() {
    local abs_path="$1"
    local rel_path

    # 1. 剥离家目录前缀，得到相对路径
    if [[ "$abs_path" == "$HOME"/* ]]; then
        rel_path="${abs_path#$HOME/}"
    else
        # 如果不在 $HOME 下，直接返回原路径（但调用者应保证在 $HOME 下）
        red "错误：源文件不在用户目录下，会导致链接出错"
        rel_path="${abs_path#/}"
    fi

    # 2. 按 '/' 分割组件，处理每个以点开头的组件
    # IFS='/' read -ra components <<< "$rel_path"
    # local converted=""
    # for comp in "${components[@]}"; do
    #     # 如果组件以点开头，替换为 dot- 前缀
    #     if [[ "$comp" == .* ]]; then
    #         comp="dot-${comp#.}"
    #     fi
    #     if [ -z "$converted" ]; then
    #         converted="$comp"
    #     else
    #         converted="$converted/$comp"
    #     fi
    # done
    converted=$(echo "$rel_path" | sed -E 's@(^|/)\.([^/]*)@\1dot-\2@g')

    echo "$converted"
}

# ===========================================
# 命令函数
# ===========================================
# 初始化函数
init_dfm() {
    local alias_name="${1:-}"

    yellow "\n====== DFM 初始化向导 ======"
    # 基本信息打印
    blue "脚本路径：$SCRIPT_PATH"
    blue "脚本目录：$SCRIPT_DIR"
    blue "配置文件目录(即将创建)：$DOTFILES_DIR"

    # 如果指定了别名参数，显示别名信息
    if [ -n "$alias_name" ]; then
        blue "自定义别名: $alias_name"
    else
        blue "默认别名: $DEFAULT_ALIAS_NAME"
    fi

    # 提示打印
    yellow "\n====== 初始化前提示 ======"
    blue "配置文件将存储在：$DOTFILES_DIR"
    blue "这个目录位于脚本所在位置"

    yellow "\n推荐做法（任选其一）:"
    green "方案1 - 保持现状（简单）:"
    green "  ✓ 直接在脚本所在目录使用"
    green "  ✓ 配置目录: $DOTFILES_DIR"
    
    green "\n方案2 - 整理到用户目录（推荐）:"
    green "  • 创建专用目录（可选）:"
    green "    如：mkdir -p ~/.dotfiles"
    green "  • 将脚本移动到该目录（可选）:"
    green "    mv \"$SCRIPT_PATH\" ~/.dotfiles/"
    green "  • 配置目录会自动创建在 ~/.dotfiles/dfm-dotfiles"

    # 检查 GNU Stow
    if ! check_stow_version; then
        red "初始化失败：缺少必要的依赖"
        return 1
    fi

    # 显示计划操作并请求确认
    yellow "\n====== 计划操作 ======"
    blue "将在以下位置创建配置目录："
    blue " $DOTFILES_DIR"

    if [ -d "$DOTFILES_DIR" ]; then
        yellow "\n⚠️  注意：该目录已存在"
        blue "目录内容不会被删除，新的配置文件将添加到其中"
    else
        yellow "\n📁 该目录不存在，将被创建"
    fi

    # 显示别名设置
    if [ -n "$alias_name" ]; then
        blue "\n将设置别名: $alias_name"
    else
        blue "\n将设置默认别名: dfm"
    fi

    yellow "\n是否继续执行？(y/n)"
    read -r confirm

    case "$confirm" in
        [Yy]*)
            # 用户确认，执行创建目录操作
            if [ ! -d "$DOTFILES_DIR" ]; then
                yellow "\n创建配置目录..."
                mkdir -p "$DOTFILES_DIR"
                if [ $? -eq 0 ]; then
                    green "✓ 配置目录创建成功: $DOTFILES_DIR"
                else
                    red "✗ 配置目录创建失败！请检查权限"
                    exit 1
                fi
            else
                green "\n✓ 配置目录已存在: $DOTFILES_DIR"
            fi

            # 初始化确认后询问是否添加别名
            yellow "\n是否要将 $alias_name 命令添加到 shell 配置文件？(y/n)"
            read -r add_alias_confirm
            case "$add_alias_confirm" in
                [Yy]*)
                    # 使用指定的别名或默认值
                    if [ -n "$alias_name" ]; then
                        add_aliases "$alias_name"
                    else
                        add_aliases "$DEFAULT_ALIAS_NAME"
                    fi
                    ;;
                *)
                    yellow "\n跳过添加别名"
                    blue "您可以稍后手动添加别名"
                    ;;
            esac
            ;;
        [Nn]*)
            yellow "\n用户取消操作"
            echo "初始化已中止"
            exit 0
            ;;
        *)
            red "\n无效输入，默认取消操作"
            echo "初始化已中止"
            exit 1
            ;;
    esac

    # 初始化完成提示
    yellow "\n====== 初始化完成 ======"
    green "✓ 配置目录已就绪: $DOTFILES_DIR"

    # 显示正确的命令名称
    local cmd_name
    if [ -n "$alias_name" ]; then
        cmd_name="$alias_name"
    else
        cmd_name="$DEFAULT_ALIAS_NAME"
    fi
    yellow "使用 '$cmd_name add' 命令添加配置文件"
    yellow "示例: $cmd_name add ~/.bashrc bash"

    blue "\n配置目录结构示例:"
    echo "  $DOTFILES_DIR/"
    echo "  ├── bash/"
    echo "  │   └── dot-bashrc"
    echo "  ├── nvim/"
    echo "  │   └── dot-config/"
    echo "  │       └── nvim/"
    echo "  └── zsh/"
    echo "      ├── dot-zshrc"
    echo "      └── dot-oh-my-zsh/"
}

# 添加配置文件
add_dfm() {
    if [ $# -lt 1 ];then
        red "错误：请指定源文件路径"
        echo "用法: dfm add <源文件路径> [模块名]"
        echo "示例: dfm add ~/.bashrc bash"
        echo "示例: dfm add ~/.config/nvim nvim"
        return 1
    fi
    local source_path="$1"
    local module_name="${2:-}"

    # 1. 路径预处理：展开 ~ 并转为绝对路径
    source_path="${source_path/#\~/$HOME}"
    if [[ "$source_path" != /* ]]; then
        source_path="$(cd "$(dirname "$source_path")" && pwd)/$(basename "$source_path")"
    fi

    # 2. 校验源文件存在性
    if [ ! -e "$source_path" ]; then
        red "错误：源文件不存在 - $source_path"
        return 1
    fi

    # 3. 检查源路径是否在 $HOME 下（DFM 只管理家目录下的配置）
    if [[ "$source_path" != "$HOME"/* ]]; then
        red "错误：源路径必须在 \$HOME 目录下"
        blue "DFM 仅用于管理家目录下的配置文件，当前路径: $source_path"
        return 1
    fi

    # 4. 自动推断模块名（若未指定）
    if [ -z "$module_name" ]; then
        # 取 basename 并移除开头的点（如 .bashrc → bashrc）
        module_name=$(basename "$source_path" | sed 's/^\.//')
        green "自动推断模块名: $module_name"
    fi

    # 5. 打印操作信息
    green "\n====== DFM 添加配置 ======"
    blue "源文件路径: $source_path"
    blue "模块名称: $module_name"
    blue "配置仓库: $DOTFILES_DIR"

    # 6. 创建备份文件 源文件+.bak
    local backup_path="${source_path}.bak"
    yellow "\n创建备份文件..."
    if [ -d "$source_path" ];then
        cp -r "$source_path" "$backup_path"  # 目录备份（递归拷贝）
        green "✓ 目录备份成功: $backup_path"
    else
        cp "$source_path" "$backup_path"  # 文件备份
        green "✓ 文件备份成功: $backup_path"
    fi

    # 7. 路径组件处理（核心：将所有点开头的组件替换为 dot- 前缀）
    local target_rel_path
    target_rel_path=$(generate_target_rel_path "$source_path")

    # 8. 构建目标路径（模块目录下）
    local target_path="$DOTFILES_DIR/$module_name/$target_rel_path"
    local target_dir=$(dirname "$target_path")

    # 检查目标路径是否已存在（避免重复添加）
    if [ -e "$target_path" ]; then
        red "错误：目标路径已存在 - $target_path"
        blue "可能该配置已经添加过，请检查或手动删除"
        return 1
    fi

    # 确保目标目录存在
    mkdir -p "$target_dir" || {
        red "错误：无法创建目标目录 - $target_dir"
        return 1
    }

    # 9. 移动源文件到目标路径
    yellow "\n移动源文件到配置仓库..."
    if [ -d "$source_path" ];then
        mv "$source_path" "$target_path"
        green "✓ 目录移动成功: $source_path → $target_path/"
        blue "结构: $module_name/$target_rel_path/"
    else
        mv "$source_path" "$target_path"
        green "✓ 文件移动成功: $source_path → $target_path"
        blue "结构: $module_name/$target_rel_path"
    fi

    yellow "\n文件已移至仓库，原位置已备份为 .bak"
    blue "现在可以使用 'dfm link $module_name' 创建符号链接"
}

# ===========================================
# 通用 Stow 操作（封装链接或取消链接）
# ===========================================
stow_operation() {
    local action="$1"      # "link" 或 "unlink"
    local module="${2:-}"

    # 检查 stow 版本
    if ! check_stow_version; then
        return 1
    fi

    # 检查仓库是否存在
    if [ ! -d "$DOTFILES_DIR" ]; then
        red "错误：配置仓库不存在 - $DOTFILES_DIR"
        blue "请先运行 'dfm init' 初始化"
        return 1
    fi

    # 根据动作设置提示信息和 Stow 命令选项
    local action_verb
    local stow_opts=""
    if [ "$action" = "link" ]; then
        action_verb="链接"
        stow_opts=""  # link 不需要额外选项
    elif [ "$action" = "unlink" ]; then
        action_verb="取消链接"
        stow_opts="-D"
    else
        red "内部错误：未知动作 '$action'"
        return 1
    fi

    yellow "\n====== DFM ${action_verb}配置 ======"
    blue "仓库目录: $DOTFILES_DIR"
    blue "目标目录: $HOME"
    blue "Stow 模式: --dotfiles (自动将 dot- 前缀映射为 .)"

    if [ -n "$module" ]; then
        # 操作单个模块
        if [ ! -d "$DOTFILES_DIR/$module" ]; then
            red "错误：模块 '$module' 不存在于仓库中"
            return 1
        fi
        yellow "\n${action_verb}模块: $module"
        set -x
        stow $stow_opts -d "$DOTFILES_DIR" -t "$HOME" --dotfiles "$module"
        set +x
        green "✓ 模块 '$module' ${action_verb}成功"
    else
        # 操作所有模块
        local count=0
        for pkg in "$DOTFILES_DIR"/*/; do
            if [ -d "$pkg" ]; then
                module_name=$(basename "$pkg")
                yellow "\n${action_verb}模块: $module_name"
                set -x
                stow $stow_opts -d "$DOTFILES_DIR" -t "$HOME" --dotfiles "$module_name"
                set +x
                green "✓ 模块 '$module_name' ${action_verb}成功"
                count=$((count + 1))
            fi
        done
        if [ $count -eq 0 ]; then
            yellow "仓库中没有找到任何模块"
        else
            green "\n✓ 共${action_verb} $count 个模块"
        fi
    fi
}
# 仅添加别名
alias_dfm() {
    local alias_name="${1:-$DEFAULT_ALIAS_NAME}"
    add_aliases "$alias_name"
}

# 列出添加的配置文件
list_dfm(){
    # 检查仓库是否存在
    if [ ! -d "$DOTFILES_DIR" ];then
        red "错误：配置仓库不存在 - $DOTFILES_DIR"
        blue "请先运行 'dfm init' 初始化"
    fi

    yellow "\n====== DFM 仓库内容 ======"
    blue "仓库目录: $DOTFILES_DIR"
    echo ""

    if command -v tree &>/dev/null; then
        # 使用 tree 显示目录树（更美观）
        tree -C --noreport "$DOTFILES_DIR"
    else
        blue "提示: 安装 'tree' 可获得更详细的树形结构"
        echo ""
        # 检查仓库是否为空
        if [ -z "$(ls -A "$DOTFILES_DIR" 2>dev/null)" ];then
            yellow "仓库为空，还没有添加任何配置文件"
        else
            # 使用 ls 列出根目录内容（即各个模块）
            ls -l --color=auto "$DOTFILES_DIR"
        fi

    fi
}

# 显示帮助信息
show_help() {
    cat << EOF
DFM - Dotfiles Manager (基于 GNU Stow)

用法: $SCRIPT_NAME <命令> [参数]

注意: DFM只能管理用户家目录下的配置文件，如果添加非家目录的配置文件会退出脚本

命令:
  init [别名]           初始化 DFM 配置目录（可指定别名，默认 dfm）
  add <源文件路径> [模块名]  添加配置文件到指定模块（模块名可选，自动推断）
  link [模块名]         使用 stow 链接配置文件（不指定模块则链接所有）
  alias [别名]          仅为脚本添加别名（不初始化仓库）
  help                  显示此帮助信息

示例:
  $SCRIPT_NAME init                     初始化，使用默认别名 dfm
  $SCRIPT_NAME init mydfm               初始化，使用别名 mydfm
  $SCRIPT_NAME add ~/.bashrc bash       添加 .bashrc 到 bash 模块
  $SCRIPT_NAME add ~/.config/nvim nvim  添加 nvim 配置到 nvim 模块
  $SCRIPT_NAME add ~/.oh-my-zsh zsh     添加 oh-my-zsh 插件到 zsh 模块
  $SCRIPT_NAME link nvim                 仅链接 nvim 模块
  $SCRIPT_NAME link                       链接所有模块
  $SCRIPT_NAME alias                       添加默认别名 dfm
  $SCRIPT_NAME alias dot                   添加别名 dot

目录结构说明:
  dfm-dotfiles/         配置根目录
    ├── nvim/           模块目录
    │   └── dot-config/
    │       └── nvim/   原始配置目录（对应 ~/.config/nvim）
    ├── bash/
    │   └── dot-bashrc  点文件（仓库中为 dot- 前缀，链接后变为 .bashrc）
    └── zsh/
        ├── dot-zshrc
        └── dot-oh-my-zsh/   （对应 ~/.oh-my-zsh）

Stow 集成:
  所有 link 操作均启用 --dotfiles 选项，自动将仓库中的 dot- 前缀映射为实际点号。
  例如：dot-bashrc → ~/.bashrc，dot-config/nvim → ~/.config/nvim
EOF
}

# 主函数
main() {
    if [ $# -eq 0 ]; then
        show_help
        exit 0
    fi

    case "$1" in
        "init")
            shift
            init_dfm "$@"
            ;;
        "add")
            shift
            add_dfm "$@"
            ;;
        "link")
            shift
            stow_operation "link" "$@"
            ;;
        "unlink")
            shift
            stow_operation "unlink" "$@"
            ;;
        "alias")
            shift
            alias_dfm "$@"
            ;;
        "list"|"ls"|"tree")
            list_dfm
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        *)
            red "错误：未知命令 '$1'"
            echo "使用 '$SCRIPT_NAME help' 查看可用命令"
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"