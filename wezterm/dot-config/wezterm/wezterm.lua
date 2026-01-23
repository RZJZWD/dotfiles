local wezterm = require 'wezterm'
local config = wezterm.config_builder()  -- 使用配置构建器

-- 1. 字体与字号：中文环境的基本盘
config.font = wezterm.font_with_fallback({
    -- 'JetBrains Mono',
    'Maple Mono NF CN',                -- 主字体：Maple Mono NF CN（已安装）
    'LXGW Bright Code GB',             -- 备选：霞鹜等宽臻宋
    'Consolas',
    'Courier New',
    'monospace'
})
config.font_size = 12
config.line_height = 1.0
config.cell_width = 1.0

-- 字体样式规则
config.font_rules = {
    {
        italic = false,
        intensity = "Bold",
        font = wezterm.font("Maple Mono NF CN", { weight = "Bold" }),
    },
    {
        italic = true,
        intensity = "Normal",
        font = wezterm.font("Maple Mono NF CN", { style = "Italic" }),
    },
    {
        italic = true,
        intensity = "Bold",
        font = wezterm.font("Maple Mono NF CN", { weight = "Bold", style = "Italic" }),
    },
}

-- 背景图片设置（根据官方示例和图片要求）
-- 设置背景（多层背景，这里只设置一层）
config.background = {
  {
    source = {
        File = wezterm.config_dir .. '/miku_bg.png',
    },
    -- 设置为"均匀填充"：填满整个窗口
    width = '100%',
    height = '100%',
    -- 设置为"居中"
    horizontal_align = 'Center',
    vertical_align = 'Middle',
    -- 设置不透明度为 18%（通过调暗实现，保持颜色但降低亮度）
    -- 注意：这里使用 opacity 字段
    opacity = 0.18,
    -- 不使用重复，只显示一张图片
    repeat_x = 'NoRepeat',
    repeat_y = 'NoRepeat',
  },
}

-- 2. 主题与性能：好看也要流畅
-- 尝试以下几种方案，看哪个与你的 Zsh 主题最匹配
-- config.color_scheme = 'Ayu Mirage'  -- 原来的
config.color_scheme = 'Catppuccin Mocha'  -- 很多 Zsh 主题都适配这个
-- config.color_scheme = 'Dracula'      -- 经典暗色主题
-- config.color_scheme = 'Tokyo Night'  -- 现代主题
-- config.color_scheme = 'Gruvbox Dark' -- 复古风格个
config.max_fps = 120
config.front_end = 'WebGpu'
config.webgpu_power_preference = 'HighPerformance'


-- 3. 自动选择 Shell：Windows / Linux 一套配置通吃
if wezterm.target_triple:find("windows") ~= nil then
    -- Windows 系统：nu → pwsh → powershell → cmd
    local function command_exists(cmd)
        local success, stdout, stderr = wezterm.run_child_process({"where", cmd})
        return success and stdout and stdout ~= ""
    end
    if command_exists("nu.exe") then
        config.default_prog = {'nu.exe', '-l'}
    elseif command_exists("powershell.exe") then
        config.default_prog = {'powershell.exe', '-NoLogo'}
    else
        config.default_prog = {'cmd.exe'}
    end
else
    -- Unix 系统：zsh → bash → sh
    local function command_exists(cmd)
        local success, stdout, stderr = wezterm.run_child_process({
            "sh", "-c", "command -v " .. cmd
        })
        return success and stdout and stdout ~= ""
    end
    if command_exists("zsh") then
        config.default_prog = {'nu', '-i'}
    elseif command_exists("bash") then
        config.default_prog = {'bash', '-i'}
    else
        config.default_prog = {'sh', '-i'}
    end
end

-- 4. 窗口样式：兼顾美观与实用
config.window_decorations = "INTEGRATED_BUTTONS|RESIZE"
config.window_frame = {
    active_titlebar_bg = "#090909",
    inactive_titlebar_bg = "#090909"
}

config.integrated_title_button_alignment = "Right"
config.integrated_title_button_style = "Windows"
config.integrated_title_buttons = {"Hide", "Maximize", "Close"}
config.adjust_window_size_when_changing_font_size = false
config.window_close_confirmation = 'NeverPrompt'
config.window_padding = {
    left = 12,
    right = 12,
    top = 12,
    bottom = 12,
}
config.initial_cols = 96
config.initial_rows = 22


-- 5. 标签栏与配色：默认隐藏，但随时可开
config.enable_tab_bar = true  -- 默认关闭标签栏
config.show_new_tab_button_in_tab_bar = true
config.show_tab_index_in_tab_bar = true
config.switch_to_last_active_tab_when_closing_tab = true
config.tab_max_width = 25
config.use_fancy_tab_bar = true
config.colors = {
    scrollbar_thumb = '#242936',
    tab_bar = {
        active_tab = {bg_color = '#090909', fg_color = '#ff6565'},
        inactive_tab = {bg_color = '#090909', fg_color = '#95e6cb'},
        inactive_tab_hover = {bg_color = '#0f1419', fg_color = '#95e6cb'},
        new_tab = {bg_color = '#090909', fg_color = '#95e6cb'},
        new_tab_hover = {bg_color = '#42a5f5', fg_color = '#ffffff'}
    }
}
-- 4. 设置状态栏更新间隔为1秒
config.status_update_interval = 1000
-- 5. 右侧状态栏（简单版本）
wezterm.on('update-right-status', function(window, pane)
    -- 获取电池信息
    local battery_text = ""
    local batteries = wezterm.battery_info()
    if batteries and #batteries > 0 then
        local b = batteries[1]
        local percent = math.floor(b.state_of_charge * 100)
        battery_text = "power: " .. percent .. "%"
    end
    
    -- 获取时间（只显示到分钟）
    local time = wezterm.strftime("%H:%M")
    local date = wezterm.strftime("%Y-%m-%d")
    
    -- 设置右侧状态
    window:set_right_status(wezterm.format({
        {Foreground = {Color = "#89b4fa"}},
        {Text = " " .. battery_text .. " | " .. date .. " " .. time .. " "},
    }))
end)

-- 6. 启动菜单：一键连 Bash / Zsh / SSH / WSL
config.launch_menu = {
    {label = "Bash", args = {"bash", "-l"}},
    {label = "Zsh", args = {"zsh", "-l"}},
    {
        label = "Pwsh",
        args = {"pwsh.exe", "-NoLogo"}
    },
    {
        label = "PowerShell",
        args = {"powershell.exe", "-NoLogo"}
    },
    {
        label = "SSH: orangepi",
        args = {"ssh", "-p 22", "orangepi@192.168.1.7"}
    },
    {
        label = "WSL: Ubuntu",
        args = {"wsl.exe", "--cd", "~"}
    }
}

-- 7. 键位设计：统一使用 Leader，减少冲突
config.disable_default_key_bindings = true
config.leader = {key = "a", mods = "CTRL", timeout_milliseconds = 1500}

-- 7.1 标签、分屏相关快捷键
config.keys = {
    -- F11：切换全屏
    {key = 'F11', mods = 'NONE', action = wezterm.action.ToggleFullScreen},
    -- Leader + m：隐藏窗口
    {key = 'm', mods = 'LEADER', action = wezterm.action.Hide},
    -- Leader + n：新建标签页
    {key = 'n', mods = 'LEADER', action = wezterm.action.SpawnTab('CurrentPaneDomain')},
    -- Leader + w：关闭当前标签页（不确认）
    {key = 'w', mods = 'LEADER', action = wezterm.action.CloseCurrentTab({confirm = false})},
    -- Leader + Tab：切换到下一个标签页
    {key = 'Tab', mods = 'LEADER', action = wezterm.action.ActivateTabRelative(1)},
    -- Leader + \\：水平分割
    {key = '\\', mods = 'LEADER', action = wezterm.action.SplitHorizontal({domain = 'CurrentPaneDomain'})},
    -- Leader + -：垂直分割
    {key = '-', mods = 'LEADER', action = wezterm.action.SplitVertical({domain = 'CurrentPaneDomain'})},
    -- Leader + 方向键：在窗格之间移动
    {key = "LeftArrow",  mods = 'LEADER', action = wezterm.action.ActivatePaneDirection('Left')},
    {key = "DownArrow",  mods = 'LEADER', action = wezterm.action.ActivatePaneDirection('Down')},
    {key = "UpArrow",    mods = 'LEADER', action = wezterm.action.ActivatePaneDirection('Up')},
    {key = "RightArrow", mods = 'LEADER', action = wezterm.action.ActivatePaneDirection('Right')},
    -- Ctrl + Shift + 方向键：调整窗格大小
    {key = "LeftArrow",  mods = 'CTRL|SHIFT', action = wezterm.action.AdjustPaneSize({'Left', 5})},
    {key = "DownArrow",  mods = 'CTRL|SHIFT', action = wezterm.action.AdjustPaneSize({'Down', 5})},
    {key = "UpArrow",    mods = 'CTRL|SHIFT', action = wezterm.action.AdjustPaneSize({'Up', 5})},
    {key = "RightArrow", mods = 'CTRL|SHIFT', action = wezterm.action.AdjustPaneSize({'Right', 5})},
    -- Ctrl + Shift + W：关闭当前窗格（带确认）
    {key = 'w', mods = 'CTRL|SHIFT', action = wezterm.action.CloseCurrentPane({confirm = true})},
    
    -- 7.2 搜索、清屏、命令面板
    {key = 'f', mods = 'LEADER', action = wezterm.action.Search('CurrentSelectionOrEmptyString')},
    {key = 'p', mods = 'LEADER', action = wezterm.action.ShowLauncher},
    {key = 'k', mods = 'LEADER', action = wezterm.action.ClearScrollback('ScrollbackAndViewport')},
    {key = "F1", action = wezterm.action.ShowLauncherArgs {
        flags = "FUZZY|LAUNCH_MENU_ITEMS|DOMAINS|KEY_ASSIGNMENTS"
    }},
    {key = 'Home', mods = 'LEADER', action = wezterm.action.ScrollToTop},
    {key = 'End',  mods = 'LEADER', action = wezterm.action.ScrollToBottom},
    
    -- 字体缩放快捷键（与之前配置保持一致）
    {key = '+', mods = 'CTRL', action = wezterm.action.IncreaseFontSize},
    {key = '-', mods = 'CTRL', action = wezterm.action.DecreaseFontSize},
    {key = '0', mods = 'CTRL', action = wezterm.action.ResetFontSize},
    
    -- 复制粘贴快捷键
    {key = 'c', mods = 'CTRL|SHIFT', action = wezterm.action.CopyTo 'Clipboard'},
    {key = 'v', mods = 'CTRL|SHIFT', action = wezterm.action.PasteFrom 'Clipboard'},
}


-- 8. 鼠标行为：复制粘贴更符合桌面习惯
config.disable_default_mouse_bindings = false
config.mouse_bindings = {
    {  -- 左键选择文本并复制到剪贴板
        event = {Up = {streak = 1, button = 'Left'}},
        mods = 'NONE',
        action = wezterm.action.CompleteSelection('Clipboard')
    },
    {  -- 右键粘贴剪贴板内容
        event = {Down = {streak = 1, button = 'Right'}},
        mods = 'NONE',
        action = wezterm.action.PasteFrom('Clipboard')
    },
    {
        -- 按住 Ctrl+Alt 拖动左键移动窗口
        event = {Drag = {streak = 1, button = 'Left'}},
        mods = 'CTRL|ALT',
        action = wezterm.action.StartWindowDrag
    },
    {
        -- 按住 Ctrl 点击左键打开超链接
        event = {Up = {streak = 1, button = 'Left'}},
        mods = 'CTRL',
        action = wezterm.action.OpenLinkAtMouseCursor
    },
}

-- 9. 高级功能：滚动、自动重载、超链接识别
config.enable_scroll_bar = true
config.scrollback_lines = 20000
config.automatically_reload_config = true
config.exit_behavior = 'CloseOnCleanExit'
config.exit_behavior_messaging = 'Verbose'
-- config.status_update_interval = 50000

-- 超链接处理规则
config.hyperlink_rules = {
    -- {regex = '\', format = '1', highlight = 1},
    {regex = '\\{(\\w+://\\S+)\\}', format = '1', highlight = 1},
    {regex = '\\b\\w+://\\S+[)/a-zA-Z0-9-]+', format = '0'},
}

-- 其他优化
config.warn_about_missing_glyphs = false
config.freetype_load_target = "Light"
config.freetype_render_target = "HorizontalLcd"

-- 光标设置
config.default_cursor_style = "BlinkingBar"
config.cursor_blink_rate = 800
config.cursor_blink_ease_in = "Constant"
config.cursor_blink_ease_out = "Constant"

-- ============================================
-- 事件处理：窗口启动时居中显示
-- ============================================
wezterm.on("window-config-reloaded", function(window, pane)
	local id = tostring(window:window_id())
	local seen = wezterm.GLOBAL.seen_windows or {}
	local is_new_window = not seen[id]
	seen[id] = true
	wezterm.GLOBAL.seen_windows = seen
	if is_new_window then
		window:set_position(500, 100)
	end
end)

-- 动态切换标签栏显示/隐藏的事件处理器
wezterm.on('toggle-tab-bar', function(window, pane)
    local overrides = window:get_config_overrides() or {}
    if overrides.enable_tab_bar == nil then
        overrides.enable_tab_bar = false
    else
        overrides.enable_tab_bar = not overrides.enable_tab_bar
    end
    window:set_config_overrides(overrides)
end)
-- 添加切换标签栏的快捷键
table.insert(config.keys, {key = "t", mods = 'LEADER', action = wezterm.action.EmitEvent('toggle-tab-bar')})

return config
