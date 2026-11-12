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
# 多根：base + overlay
# ===========================================
# base = 脚本所在目录；overlay = $HOME/dotfiles-<名字>（含 dfm-dotfiles/）。
# 只认这个命名约定，不扫描其它目录，也不维护任何配置文件。
declare -a ROOT_NAMES=()
declare -a ROOT_PATHS=()
# overlay 的目录名（如 dotfiles-home），仅用于展示；角色名固定为 base / overlay
OVERLAY_LABEL=""

# 根只有两个角色：base（脚本所在目录）与 overlay（本机唯一一个 ~/dotfiles-*）。
# overlay 一机一个；发现多个是配置错误，不做“让用户选一个”。
load_roots() {
    ROOT_NAMES=("base")
    ROOT_PATHS=("$SCRIPT_DIR")
    OVERLAY_LABEL=""
    local dir base_real
    local -a found=() found_paths=()
    base_real="$(cd "$SCRIPT_DIR" && pwd -P)"
    for dir in "$HOME"/dotfiles-*; do
        [ -d "$dir" ] || continue
        [ "$(cd "$dir" && pwd -P)" = "$base_real" ] && continue
        [ -d "$dir/dfm-dotfiles" ] || continue
        found+=("$(basename "$dir")")
        found_paths+=("$dir")
    done
    if [ "${#found[@]}" -gt 1 ]; then
        red "错误：检测到多个 overlay（${found[*]}）" >&2
        blue "设计上一台机器只有一个 overlay；请删掉多余的，或把内容合并进一个" >&2
        return 1
    fi
    if [ "${#found[@]}" -eq 1 ]; then
        OVERLAY_LABEL="${found[0]}"
        ROOT_NAMES+=("overlay")
        ROOT_PATHS+=("${found_paths[0]}")
    fi
    return 0
}

# 展示用：base / overlay (dotfiles-home)
root_label() {
    local i="$1"
    if [ "${ROOT_NAMES[$i]}" = "overlay" ] && [ -n "$OVERLAY_LABEL" ]; then
        echo "overlay ($OVERLAY_LABEL)"
    else
        echo "${ROOT_NAMES[$i]}"
    fi
}

root_index() {
    local want="$1" i
    # 允许用 overlay 的目录名作为别名（如 dotfiles-home）
    if [ -n "$OVERLAY_LABEL" ] && [ "$want" = "$OVERLAY_LABEL" ]; then
        want="overlay"
    fi
    for i in "${!ROOT_NAMES[@]}"; do
        if [ "${ROOT_NAMES[$i]}" = "$want" ]; then
            echo "$i"
            return 0
        fi
    done
    return 1
}

find_module_root() {
    local module="$1" i found=-1
    for i in "${!ROOT_PATHS[@]}"; do
        if [ -d "${ROOT_PATHS[$i]}/dfm-dotfiles/$module" ]; then
            if [ "$found" -ge 0 ]; then
                red "错误：模块 '$module' 同时存在于 ${ROOT_NAMES[$found]} 和 ${ROOT_NAMES[$i]}" >&2
                return 2
            fi
            found=$i
        fi
    done
    if [ "$found" -lt 0 ]; then
        red "错误：模块 '$module' 不存在于任何根（新配置请先 dfm add）" >&2
        return 1
    fi
    echo "$found"
}

check_duplicate_modules() {
    local -A seen=()
    local i m name
    for i in "${!ROOT_PATHS[@]}"; do
        for m in "${ROOT_PATHS[$i]}"/dfm-dotfiles/*/; do
            [ -d "$m" ] || continue
            name="$(basename "$m")"
            if [ -n "${seen[$name]:-}" ]; then
                red "错误：模块 '$name' 同时存在于 ${seen[$name]} 和 ${ROOT_NAMES[$i]}"
                return 1
            fi
            seen[$name]="${ROOT_NAMES[$i]}"
        done
    done
}

root_is_git() {
    git -C "$1" rev-parse --git-dir >/dev/null 2>&1
}

# 输出: not-git / no-remote / read-only / push
root_push_state() {
    local p="$1" url
    if ! root_is_git "$p"; then
        echo "not-git"
        return 0
    fi
    if ! git -C "$p" remote get-url origin >/dev/null 2>&1; then
        echo "no-remote"
        return 0
    fi
    url="$(git -C "$p" remote get-url --push origin 2>/dev/null || true)"
    if [ -z "$url" ] || [ "$url" = "DISABLED" ]; then
        echo "read-only"
    else
        echo "push"
    fi
}

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

# 逐文件链接（--no-folding）下，unlink 后清理模块留下的空目录
prune_empty_dirs_for_module() {
    local root_dir="$1" module="$2" rel d
    [ -d "$root_dir/dfm-dotfiles/$module" ] || return 0
    while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        d="$(dirname "$(home_path_of "$rel")")"
        while [ "$d" != "$HOME" ] && [ "${d#"$HOME"/}" != "$d" ]; do
            rmdir "$d" 2>/dev/null || break
            d="$(dirname "$d")"
        done
    done < <(cd "$root_dir/dfm-dotfiles/$module" && find . \( -type f -o -type l \) -printf '%P\n')
}

# 模块当前是否有链接（用于 unlink 的“未链接”判断）
module_has_links() {
    local root_dir="$1" module="$2" rel target
    [ -d "$root_dir/dfm-dotfiles/$module" ] || return 1
    while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        target="$(home_path_of "$rel")"
        [ -L "$target" ] && return 0
    done < <(cd "$root_dir/dfm-dotfiles/$module" && find . \( -type f -o -type l \) -printf '%P\n')
    return 1
}

# 把仓库内的相对路径（dot- 形式）还原成 $HOME 下的真实路径
home_path_of() {
    local rel="$1" comp out=""
    local -a comps=()
    IFS='/' read -r -a comps <<< "$rel"
    for comp in "${comps[@]}"; do
        case "$comp" in
            dot-*) comp=".${comp#dot-}" ;;
        esac
        out="${out:+$out/}$comp"
    done
    echo "$HOME/$out"
}

# ===========================================
# 命令函数
# ===========================================
# 初始化函数
init_dfm() {
    local alias_name="" push_base="" _arg
    for _arg in "$@"; do
        case "$_arg" in
            --push-base)    push_base=yes ;;
            --no-push-base) push_base=no ;;
            -h|--help)      show_help; return 0 ;;
            -*)             red "错误：未知参数 $_arg"; return 1 ;;
            *)              alias_name="$_arg" ;;
        esac
    done

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
    read -r confirm || confirm=""

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
            read -r add_alias_confirm || add_alias_confirm=""
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

    # 决定 base 的推送权：直接写进 git 的 pushurl，不存额外配置
    if [ -z "$push_base" ]; then
        if [ -t 0 ]; then
            yellow "\n这台机器允许推送 base 吗？(y/N)"
            read -r _ans || _ans=""
            case "$_ans" in
                [Yy]*) push_base=yes ;;
                *)     push_base=no ;;
            esac
        else
            push_base=no
        fi
    fi
    if root_is_git "$SCRIPT_DIR" && git -C "$SCRIPT_DIR" remote get-url origin >/dev/null 2>&1; then
        if [ "$push_base" = "yes" ]; then
            git -C "$SCRIPT_DIR" config --unset-all remote.origin.pushurl 2>/dev/null || true
            green "✓ base 可推送（origin 原样保留）"
        else
            git -C "$SCRIPT_DIR" remote set-url --push origin DISABLED
            green "✓ base 设为只读（pushurl=DISABLED）"
        fi
    fi
}

# 添加配置文件
add_dfm() {
    local -a _pos=()
    local root_name="base" root_given=0 _a
    while [ $# -gt 0 ]; do
        case "$1" in
            --root|-r)
                [ $# -ge 2 ] || { red "错误：--root 需要一个根名"; return 1; }
                root_name="$2"
                root_given=1
                shift 2
                ;;
            -h|--help)
                show_help
                return 0
                ;;
            -*)
                red "错误：未知参数 $1"
                return 1
                ;;
            *)
                _pos+=("$1")
                shift
                ;;
        esac
    done

    if [ ${#_pos[@]} -lt 1 ]; then
        red "错误：请指定源文件路径"
        echo "用法: dfm add [--root <根>] <源文件路径> [模块名]"
        echo "示例: dfm add ~/.config/company-tool company-tool   # 默认写 overlay"
        echo "示例: dfm add --root base ~/.bashrc bash            # 写 base 必须显式指定"
        return 1
    fi

    local source_path="${_pos[0]}"
    local module_name="${_pos[1]:-}"

    load_roots || return 1

    # 默认写 overlay（本机私有配置）；写 base 必须显式 --root base
    if [ "$root_given" -eq 0 ]; then
        if [ -z "$OVERLAY_LABEL" ]; then
            red "错误：本机没有 overlay，无法确定默认根"
            blue "要写入 base 请显式: dfm add --root base <源> [模块]"
            return 1
        fi
        root_name="overlay"
        blue "默认根: overlay ($OVERLAY_LABEL)（要写 base 请加 --root base）"
    fi

    local root_idx
    if ! root_idx="$(root_index "$root_name")"; then
        red "错误：未知根 '$root_name'（可用: ${ROOT_NAMES[*]}）"
        return 1
    fi
    local root_path="${ROOT_PATHS[$root_idx]}"
    local root_dir="$root_path/dfm-dotfiles"

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
    blue "配置仓库: $root_dir（$(root_label "$root_idx")）"

    # 5.5 源文件不能是已有的软链（说明已经被 DFM 管着）
    if [ -L "$source_path" ]; then
        red "错误：$source_path 是符号链接，可能已由 DFM 管理"
        blue "要改内容直接编辑它；要换模块请先 dfm unlink 再处理"
        return 1
    fi

    # 5.6 模块名不能和其它根重名
    local _i
    for _i in "${!ROOT_PATHS[@]}"; do
        [ "$_i" = "$root_idx" ] && continue
        if [ -d "${ROOT_PATHS[$_i]}/dfm-dotfiles/$module_name" ]; then
            red "错误：模块 '$module_name' 已存在于 ${ROOT_NAMES[$_i]}"
            return 1
        fi
    done

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
    local target_path="$root_dir/$module_name/$target_rel_path"
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

    yellow "链接模块 $module_name ..."
    if stow --no-folding -d "$root_dir" -t "$HOME" --dotfiles "$module_name"; then
        green "✓ 已链接（以后改动直接编辑链接即可，写入会落在 $(root_label "$root_idx")）"
    else
        red "✗ 链接失败，请手动执行: dfm link $module_name"
        return 1
    fi
}

# ===========================================
# 通用 Stow 操作（跨根链接 / 取消链接）
# ===========================================
stow_operation() {
    local action="$1" module="${2:-}"
    local verb opts i idx pkg name count=0

    if ! check_stow_version; then
        return 1
    fi

    case "$action" in
        link)   verb="链接";   opts="" ;;
        unlink) verb="取消链接"; opts="-D" ;;
        *) red "内部错误：未知动作 '$action'"; return 1 ;;
    esac

    load_roots || return 1
    check_duplicate_modules || return 1

    yellow "\n====== DFM ${verb}配置 ======"
    for i in "${!ROOT_PATHS[@]}"; do
        blue "  $(root_label "$i"): ${ROOT_PATHS[$i]}"
    done
    blue "目标目录: $HOME"

    if [ -n "$module" ]; then
        idx="$(find_module_root "$module")" || return $?
        if [ "$action" = "unlink" ] && ! module_has_links "${ROOT_PATHS[$idx]}" "$module"; then
            yellow "模块 '$module'（$(root_label "$idx")）当前未链接，无需操作"
            return 0
        fi
        yellow "\n${verb}模块: $module（$(root_label "$idx")）"
        set -x
        stow --no-folding $opts -d "${ROOT_PATHS[$idx]}/dfm-dotfiles" -t "$HOME" --dotfiles "$module"
        set +x
        if [ "$action" = "unlink" ]; then
            prune_empty_dirs_for_module "${ROOT_PATHS[$idx]}" "$module"
        fi
        green "✓ 模块 '$module' ${verb}成功"
        return 0
    fi

    for i in "${!ROOT_PATHS[@]}"; do
        for pkg in "${ROOT_PATHS[$i]}"/dfm-dotfiles/*/; do
            [ -d "$pkg" ] || continue
            name="$(basename "$pkg")"
            if [ "$action" = "unlink" ] && ! module_has_links "${ROOT_PATHS[$i]}" "$name"; then
                blue "模块 '$name'（$(root_label "$i")）未链接，跳过"
                continue
            fi
            yellow "\n${verb}模块: $name（$(root_label "$i")）"
            set -x
            stow --no-folding $opts -d "${ROOT_PATHS[$i]}/dfm-dotfiles" -t "$HOME" --dotfiles "$name"
            set +x
            if [ "$action" = "unlink" ]; then
                prune_empty_dirs_for_module "${ROOT_PATHS[$i]}" "$name"
            fi
            green "✓ 模块 '$name' ${verb}成功"
            count=$((count + 1))
        done
    done

    if [ "$count" -eq 0 ]; then
        yellow "没有找到任何模块"
    else
        green "\n✓ 共${verb} $count 个模块"
    fi
}

# 仅添加别名
alias_dfm() {
    local alias_name="${1:-$DEFAULT_ALIAS_NAME}"
    add_aliases "$alias_name"
}

# 列出所有根的内容
list_dfm(){
    local max_depth="${1:-2}"
    if ! echo "$max_depth" | grep -qE '^[0-9]+$'; then
        yellow "警告：深度必须为数字，已恢复默认值 2"
        max_depth=2
    fi

    load_roots || return 1
    yellow "\n====== DFM 内容 ======"
    local i p
    for i in "${!ROOT_PATHS[@]}"; do
        p="${ROOT_PATHS[$i]}"
        echo ""
        blue "[$(root_label "$i")] $p"
        if [ ! -d "$p/dfm-dotfiles" ]; then
            yellow "  （没有 dfm-dotfiles/）"
            continue
        fi
        if command -v tree &>/dev/null; then
            tree -C --noreport -L "$max_depth" "$p/dfm-dotfiles"
        else
            ls "$p/dfm-dotfiles"
        fi
    done
}

# 状态：每个根的模块数、git 状态、推送能力
status_dfm() {
    load_roots || return 1
    check_duplicate_modules || true
    yellow "\n====== DFM 状态 ======"
    local i p state branch upstream dirty mods ab sync
    for i in "${!ROOT_PATHS[@]}"; do
        p="${ROOT_PATHS[$i]}"
        echo ""
        blue "[$(root_label "$i")] $p"
        mods=0
        if [ -d "$p/dfm-dotfiles" ]; then
            mods=$(find "$p/dfm-dotfiles" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
        fi
        echo "  模块: $mods"
        state="$(root_push_state "$p")"
        case "$state" in
            not-git)   echo "  git: 无（纯本地目录）" ;;
            no-remote) echo "  git: 有仓库但没有 origin" ;;
            read-only) echo "  git: 只读（pushurl=DISABLED）" ;;
            push)      echo "  git: 可推送" ;;
        esac
        if root_is_git "$p"; then
            branch="$(git -C "$p" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
            upstream="$(git -C "$p" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
            dirty="$(git -C "$p" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
            sync=""
            if [ -n "$upstream" ]; then
                ab="$(git -C "$p" rev-list --left-right --count "$upstream...HEAD" 2>/dev/null || true)"
                if [ -n "$ab" ]; then
                    sync="  (落后 ${ab%%$'\t'*} / 领先 ${ab##*$'\t'})"
                fi
            fi
            echo "  分支: $branch${upstream:+ → $upstream}$sync"
            if [ "$dirty" -gt 0 ]; then
                echo "  工作区: 脏（$dirty 项）"
            else
                echo "  工作区: 干净"
            fi
        fi
    done
    echo ""
}

# 拉取：每个 git 根 ff-only，随后重新链接
update_dfm() {
    local dry="${1:-}"
    load_roots || return 1
    if ! check_stow_version; then
        return 1
    fi
    local i p rc=0
    yellow "\n====== DFM 更新 ======"
    for i in "${!ROOT_PATHS[@]}"; do
        p="${ROOT_PATHS[$i]}"
        if ! root_is_git "$p"; then
            blue "[$(root_label "$i")] 非 git 仓库，跳过"
            continue
        fi
        if [ -n "$(git -C "$p" status --porcelain 2>/dev/null)" ]; then
            yellow "[$(root_label "$i")] 工作区脏，跳过拉取"
            rc=1
            continue
        fi
        if ! git -C "$p" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
            yellow "[$(root_label "$i")] 没有 upstream，跳过拉取"
            rc=1
            continue
        fi
        if [ "$dry" = "--dry-run" ]; then
            blue "[$(root_label "$i")] 将执行: git -C $p pull --ff-only"
            continue
        fi
        yellow "[$(root_label "$i")] git pull --ff-only"
        if git -C "$p" pull --ff-only; then
            green "✓ 已更新"
        else
            red "✗ 更新失败"
            rc=1
        fi
    done
    if [ "$dry" = "--dry-run" ]; then
        return $rc
    fi
    echo ""
    yellow "重新链接所有模块..."
    stow_operation link || rc=1
    return $rc
}

# 推送：只推可写根，只读根跳过
push_dfm() {
    local dry="${1:-}"
    load_roots || return 1
    local i p state rc=0
    yellow "\n====== DFM 推送 ======"
    for i in "${!ROOT_PATHS[@]}"; do
        p="${ROOT_PATHS[$i]}"
        state="$(root_push_state "$p")"
        case "$state" in
            not-git|no-remote)
                blue "[$(root_label "$i")] $state，跳过"
                continue
                ;;
            read-only)
                yellow "[$(root_label "$i")] skipped (read-only)"
                continue
                ;;
        esac
        if [ -n "$(git -C "$p" status --porcelain 2>/dev/null)" ]; then
            red "[$(root_label "$i")] 工作区脏，拒绝推送"
            rc=1
            continue
        fi
        if ! git -C "$p" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
            yellow "[$(root_label "$i")] 没有 upstream，跳过推送"
            rc=1
            continue
        fi
        if [ "$dry" = "--dry-run" ]; then
            blue "[$(root_label "$i")] 将执行: git -C $p push"
            continue
        fi
        yellow "[$(root_label "$i")] git push"
        if git -C "$p" push; then
            green "✓ 已推送"
        else
            red "✗ 推送失败"
            rc=1
        fi
    done
    return $rc
}

# 移出：add 的逆操作，把模块里的文件搬回 $HOME，并删掉仓库里的模块
remove_dfm() {
    local root_name="overlay" root_given=0 force=0 _a
    local -a _pos=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --root|-r)  root_name="$2"; root_given=1; shift 2 ;;
            --force|-f) force=1; shift ;;
            -h|--help)  show_help; return 0 ;;
            -*)         red "错误：未知参数 $1"; return 1 ;;
            *)          _pos+=("$1"); shift ;;
        esac
    done

    if [ ${#_pos[@]} -lt 1 ]; then
        red "错误：请指定要移出的模块"
        echo "用法: dfm remove [--root <根>] [--force] <模块名>"
        echo "示例: dfm remove company-tool             # 从 overlay 移出"
        echo "示例: dfm remove --root base bash          # 从 base 移出"
        return 1
    fi
    local module="${_pos[0]}"

    load_roots || return 1
    if [ "$root_given" -eq 0 ] && [ -z "$OVERLAY_LABEL" ]; then
        red "错误：本机没有 overlay，无法确定默认根"
        blue "要移出 base 的模块请显式: dfm remove --root base <模块>"
        return 1
    fi

    local idx root_dir module_dir
    idx="$(root_index "$root_name")" || { red "错误：未知根 '$root_name'（可用: ${ROOT_NAMES[*]}）"; return 1; }
    root_dir="${ROOT_PATHS[$idx]}"
    module_dir="$root_dir/dfm-dotfiles/$module"
    if [ ! -d "$module_dir" ]; then
        red "错误：模块 '$module' 不存在于 $(root_label "$idx")"
        return 1
    fi

    # 目标位置冲突检查（$HOME 下已有同名真实文件/目录）
    local rel target conflicts=0 hard=0
    while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        target="$(home_path_of "$rel")"
        if [ -d "$target" ] && [ ! -L "$target" ]; then
            red "冲突：$target 是目录，remove 不会覆盖目录"
            hard=$((hard + 1))
        elif [ -e "$target" ] && [ ! -L "$target" ]; then
            red "冲突：$target 已存在且不是软链"
            conflicts=$((conflicts + 1))
        fi
    done < <(cd "$module_dir" && find . \( -type f -o -type l \) -printf '%P\n')

    if [ "$hard" -gt 0 ]; then
        blue "请先手动处理这些目录（改名或删除），再执行 remove"
        return 1
    fi
    if [ "$conflicts" -gt 0 ] && [ "$force" -eq 0 ]; then
        red "有 $conflicts 个冲突，确认要覆盖请加 --force"
        return 1
    fi

    # 先摘链接，再把文件搬回 $HOME
    stow --no-folding -D -d "$root_dir/dfm-dotfiles" -t "$HOME" --dotfiles "$module" >/dev/null 2>&1 || true

    local count=0
    while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        target="$(home_path_of "$rel")"
        mkdir -p "$(dirname "$target")"
        mv "$module_dir/$rel" "$target"
        count=$((count + 1))
    done < <(cd "$module_dir" && find . \( -type f -o -type l \) -printf '%P\n')

    find "$module_dir" -depth -type d -empty -delete 2>/dev/null || true
    if [ -d "$module_dir" ]; then
        rm -rf "$module_dir"
    fi

    green "✓ 已从 $(root_label "$idx") 移出 $count 个文件到 \$HOME"
    blue "仓库里的删除是未提交状态；确认无误后自己 commit"
}

# repo 子命令：根与推送能力都直接读写 git，不存额外状态
repo_cmd() {
    local sub="${1:-list}"
    shift || true
    case "$sub" in
        list)
            load_roots || return 1
            yellow "\n====== DFM 根 ======"
            local i p state remote branch
            for i in "${!ROOT_PATHS[@]}"; do
                p="${ROOT_PATHS[$i]}"
                state="$(root_push_state "$p")"
                printf '  %-26s %-40s %s\n' "$(root_label "$i")" "$p" "$state"
                if root_is_git "$p"; then
                    remote="$(git -C "$p" config --get remote.origin.url 2>/dev/null || echo '-')"
                    branch="$(git -C "$p" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '-')"
                    printf '  %-26s remote: %s  branch: %s\n' "" "$remote" "$branch"
                fi
            done
            ;;
        add)
            local url="${1:-}" name="${2:-}" dest idx pkg
            [ -n "$url" ] || { red "用法: dfm repo add <git-url> [名字]"; return 1; }
            load_roots || return 1
            if [ -n "$OVERLAY_LABEL" ]; then
                red "错误：本机已经有 overlay（$OVERLAY_LABEL）"
                blue "设计上一台机器只有一个 overlay；请先删除旧的，或直接在旧仓库里更新"
                return 1
            fi
            if [ -z "$name" ]; then
                name="$(basename "$url" .git)"
                name="${name#dotfiles-}"
            fi
            dest="$HOME/dotfiles-$name"
            if [ -e "$dest" ]; then
                red "错误：目标已存在 - $dest"
                return 1
            fi
            git clone "$url" "$dest"
            green "✓ 已克隆到 $dest"
            load_roots || return 1
            for pkg in "$dest"/dfm-dotfiles/*/; do
                [ -d "$pkg" ] || continue
                stow --no-folding -d "$dest/dfm-dotfiles" -t "$HOME" --dotfiles "$(basename "$pkg")"
            done
            green "✓ 已链接新根的模块"
            ;;
        readonly)
            local name="${1:-}" idx
            [ -n "$name" ] || { red "用法: dfm repo readonly <根>"; return 1; }
            load_roots || return 1
            idx="$(root_index "$name")" || { red "错误：未知根 '$name'（可用: ${ROOT_NAMES[*]}）"; return 1; }
            if ! root_is_git "${ROOT_PATHS[$idx]}"; then
                red "错误：该根不是 git 仓库"
                return 1
            fi
            local _cur
            _cur="$(git -C "${ROOT_PATHS[$idx]}" config --get remote.origin.pushurl 2>/dev/null || true)"
            if [ -n "$_cur" ] && [ "$_cur" != "DISABLED" ]; then
                yellow "注意：会覆盖已有的 pushurl（$_cur）；恢复时请重新 repo pushurl"
            fi
            git -C "${ROOT_PATHS[$idx]}" remote set-url --push origin DISABLED
            green "✓ $(root_label "$idx") 已设为只读（pushurl=DISABLED）"
            ;;
        writable)
            local name="${1:-}" idx
            [ -n "$name" ] || { red "用法: dfm repo writable <根>"; return 1; }
            load_roots || return 1
            idx="$(root_index "$name")" || { red "错误：未知根 '$name'（可用: ${ROOT_NAMES[*]}）"; return 1; }
            if ! root_is_git "${ROOT_PATHS[$idx]}"; then
                red "错误：该根不是 git 仓库"
                return 1
            fi
            local -a _urls=()
            if [ -n "$(git -C "${ROOT_PATHS[$idx]}" config --get-all remote.origin.pushurl 2>/dev/null || true)" ]; then
                mapfile -t _urls < <(git -C "${ROOT_PATHS[$idx]}" config --get-all remote.origin.pushurl 2>/dev/null || true)
            fi
            if [ "${#_urls[@]}" -eq 0 ]; then
                green "✓ $(root_label "$idx") 本来就是可推送状态"
            elif [ "${#_urls[@]}" -eq 1 ] && [ "${_urls[0]}" = "DISABLED" ]; then
                git -C "${ROOT_PATHS[$idx]}" config --unset-all remote.origin.pushurl 2>/dev/null || true
                green "✓ $(root_label "$idx") 已恢复推送"
            else
                yellow "已有自定义 pushurl（${_urls[*]}），保持不动"
            fi
            ;;
        pushurl)
            local name="${1:-}" url="${2:-}" idx
            [ -n "$name" ] && [ -n "$url" ] || { red "用法: dfm repo pushurl <根> <url>"; return 1; }
            load_roots || return 1
            idx="$(root_index "$name")" || { red "错误：未知根 '$name'（可用: ${ROOT_NAMES[*]}）"; return 1; }
            if ! root_is_git "${ROOT_PATHS[$idx]}"; then
                red "错误：该根不是 git 仓库"
                return 1
            fi
            git -C "${ROOT_PATHS[$idx]}" config --unset-all remote.origin.pushurl 2>/dev/null || true
            git -C "${ROOT_PATHS[$idx]}" remote set-url --add --push origin "$url"
            green "✓ $(root_label "$idx") 的 push URL 已设为 $url"
            ;;
        *)
            red "未知 repo 子命令: $sub"
            echo "用法: dfm repo list|add|readonly|writable|pushurl"
            return 1
            ;;
    esac
}

# 显示帮助信息
show_help() {
    cat << EOF
DFM - Dotfiles Manager（基于 GNU Stow，多根：base + overlay）

用法: $SCRIPT_NAME <命令> [参数]

根（root）：
  base      = 本脚本所在目录（通常是 ~/dotfiles）
  overlay   = $HOME/dotfiles-<名字>（含 dfm-dotfiles/，各自独立的 git 仓库）
  DFM 不维护任何配置文件：根按目录约定发现，推送能力读各仓库的 pushurl。

命令:
  init [别名] [--push-base|--no-push-base]
                        初始化；同时决定这台机器能否推送 base
  link [模块名]         链接所有根的全部模块，或只链接指定模块
  unlink [模块名]       取消链接（用法同 link）
  list|ls|tree [深度]   按根列出内容（默认深度 2）
  status                每个根的模块数、git 状态、推送能力
  repo list             列出发现的根
  repo add <url> [名字]  clone 到 ~/dotfiles-<名字> 并链接
  repo readonly <根>    禁用该根推送（pushurl=DISABLED）
  repo writable <根>    恢复该根推送
  repo pushurl <根> <url> 设置独立的推送地址
  update [--dry-run]    每个 git 根 pull --ff-only，随后重新链接
  push [--dry-run]      每个根推送；只读根报 skipped
  add [--root <根>] <源文件路径> [模块名]
                        移入 overlay（默认）并立即链接；写 base 必须 --root base
  remove [--root <根>] [--force] <模块名>
                        把模块移回 \$HOME（add 的逆操作）；--force 只覆盖文件
  alias [别名]          仅添加别名
  help|--help|-h        显示帮助

示例:
  $SCRIPT_NAME status                    看各根状态
  $SCRIPT_NAME link                      链接 base 和所有 overlay
  $SCRIPT_NAME link interop              只链 interop（自动定位到所在根）
  $SCRIPT_NAME repo readonly base        这台机器不允许推 base
  $SCRIPT_NAME update                    拉取所有根后重新链接

约定:
  dfm-dotfiles/<模块>/dot-xxx   经 stow --dotfiles 映射为 ~/.xxx
  ~/.config/shell.d/*.sh        由 base 的 rc 按文件名顺序 source（环境相关的扩展点）
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
            shift
            list_dfm "$@"
            ;;
        "status")
            shift
            status_dfm "$@"
            ;;
        "update")
            shift
            update_dfm "$@"
            ;;
        "push")
            shift
            push_dfm "$@"
            ;;
        "remove"|"rm")
            shift
            remove_dfm "$@"
            ;;
        "repo")
            shift
            repo_cmd "$@"
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