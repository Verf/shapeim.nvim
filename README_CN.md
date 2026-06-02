# shapeim.nvim

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

一款零依赖的 Neovim 输入法插件，面向**形码**中文输入（五笔、仓颉、郑码等）。

纯 Lua 实现，在 Neovim 内部原生提供形码输入体验 — 编码累积、候选补全、自动上屏、
完整 undo 支持 — 无需外部进程或 RPC。支持任何 Rime `.dict.yaml` 格式的形码码表。

> For English documentation, see [README.md](./README.md)

## 特性

- 🚀 **零依赖** — 纯 Lua，无外部二进制文件
- ⚡ **极速响应** — 基于 mpack 缓存的 O(1) 词典查询
- 📦 **兼容 Rime 词库** — 支持标准 Rime `.dict.yaml` 码表（五笔、仓颉、郑码等）
- 🔌 **blink.cmp 集成** — 原生补全菜单，数字键选择候选
- 🛟 **内置降级方案** — 兼容原生 Neovim、mini.completion、nvim-cmp
- ⌨️ **完整形码输入规则** — 空格上屏、4码唯一自动上屏、5码顶字上屏
- 🔄 **原子 Undo** — 每次上屏为单步撤销
- 💾 **状态持久化** — 跨会话记忆输入法开关状态
- 📊 **状态栏支持** — 在 lualine 或 statusline 中显示 中/EN

## 环境要求

- Neovim ≥ 0.10
- 形码码表（Rime `.dict.yaml` 格式，如 [wubi86](https://github.com/rime/rime-wubi)、[cangjie5](https://github.com/rime/rime-cangjie)）
- [blink.cmp](https://github.com/Saghen/blink.cmp)（可选，用于增强补全界面）

## 安装

### lazy.nvim

```lua
{
  "yourname/shapeim.nvim",
  opts = {
    dict_path = "~/rime/wubi86.dict.yaml",
  },
}
```

### packer.nvim

```lua
use {
  "yourname/shapeim.nvim",
  config = function()
    require("shapeim").setup({
      dict_path = "~/rime/wubi86.dict.yaml",
    })
  end,
}
```

### 手动安装

```lua
require("shapeim").setup({
  dict_path = "~/rime/wubi86.dict.yaml",
})
```

首次加载时，shapeim 将**自动编译** `dict_path` 指向的码表为快速 mpack 缓存，
保存在 `stdpath("data")/shapeim_cache.mpack`。

## 快速开始

1. 使用你喜欢的插件管理器安装。
2. 通过 `dict_path` 指定形码码表路径。
3. 按 `<C-\>` 切换形码输入（状态显示 `中` 表示已开启）。
4. 输入形码编码（小写字母 `a`-`y`）。
5. 按 `<Space>` 上屏第一个候选，或使用 blink.cmp 时按数字键 `1`-`9` 选择候选。

```
切换:    <C-\>          →  中 (形码开启) / EN (英文模式)
输入:    ggll           →  补全菜单显示候选
上屏:    <Space>        →  第一个候选替换编码
自动:    4码唯一候选    →  立即自动上屏
顶字:    输入第5码      →  前4码上屏，第5码开始新一轮
```

## 配置

```lua
require("shapeim").setup({
  -- Rime .dict.yaml 码表路径（首次加载自动编译）
  dict_path = nil,

  -- 切换输入法的快捷键
  toggle_key = "<C-\\>",

  -- 跨 Neovim 会话记忆输入法状态
  persist_state = true,

  -- 显示详细提示信息（切换、补全检测、编译进度等）
  debug = false,

  -- 自动上屏码长（五笔=4，仓颉=5）
  max_code_length = 4,

  -- 到达最大码长时始终上屏第一个候选（即使有重码）
  auto_select = false,

  -- 到达最大码长且只有唯一候选时自动上屏
  auto_select_unique_candidate = true,

  -- 立即清除无效编码
  auto_clear = true,
})
```

| 选项 | 类型 | 默认值 | 说明 |
|--------|------|---------|-------------|
| `dict_path` | `string\|nil` | `nil` | `.dict.yaml` 码表路径，首次加载自动编译 |
| `toggle_key` | `string` | `"<C-\\>"` | 输入法切换快捷键 |
| `persist_state` | `boolean` | `true` | 开关状态持久化到磁盘，下次启动恢复 |
| `debug` | `boolean` | `false` | 显示 info 级别的通知消息 |
| `max_code_length` | `number` | `4` | 自动上屏码长。五笔=4，仓颉=5 |
| `auto_select` | `boolean` | `false` | 到达最大码长时始终上屏第一个候选（有重码也上屏） |
| `auto_select_unique_candidate` | `boolean` | `true` | 到达最大码长且仅有唯一候选时自动上屏 |
| `auto_clear` | `boolean` | `true` | 立即清除无效编码。设为 false 允许手动修正 |

## 命令

| 命令 | 说明 |
|---------|-------------|
| `:ShapeimCompile {path}` | 编译 Rime `.dict.yaml` 为 mpack 缓存 |

如果你在 `setup()` 中没有设置 `dict_path`，或更新码表后需要重新编译，可使用此命令。

## 输入规则

shapeim 实现了标准形码输入行为：

| 规则 | 触发条件 | 行为 |
|------|----------|------|
| **A: 空格上屏** | 按 `<Space>` | 提交第一个候选，编码替换为中文 |
| **B: 4码唯一自动上屏** | 输入第4个 `[a-y]` 键 | 若编码仅有唯一候选，立即自动上屏 |
| **C: 5码顶字上屏** | 输入第5个 `[a-y]` 键 | 前4码第一个候选上屏，第5码开始新编码 |
| **D: 非法码清除** | 输入无匹配编码 | 删除非法字符，显示警告 |

部分编码（少于 4 码）若无精确匹配但是更长编码的有效前缀，则被容忍 — 不清除。
这允许逐步构建编码（例如输入 `vk` 来构建 4 码词 `vkjs`）。

任何非 `[a-y]` 操作（光标移动、`<Enter>`、`<Esc>`、数字键）都会重置当前编码。

## 补全后端

### blink.cmp（主方案）

自动检测并注册为补全源，`score_offset = 100`。数字键 `1`-`9` 按序号选择候选。

```lua
-- 在 blink.cmp 配置中自定义
sources.providers.shapeim = {
  name = "shapeim",
  module = "shapeim.source",
  score_offset = 100,
  min_keyword_length = 1,
}
```

### 内置补全（降级方案）

若未安装 blink.cmp，shapeim 使用 Neovim 内置的 `completefunc` 机制。
使用 `<C-n>` / `<C-p>` 导航候选，`<C-y>` 确认。
兼容 [mini.completion](https://github.com/echasnovski/mini.completion)
和 [nvim-cmp](https://github.com/hrsh7th/nvim-cmp)。

## 状态栏

```lua
-- lualine
require("lualine").setup({
  sections = {
    lualine_x = { require("shapeim").status },
  },
})

-- 手动设置 statusline
vim.opt.statusline = "%{v:lua.require('shapeim').status()}"
```

形码输入开启时返回 `中`，关闭时返回 `EN`。

要让状态栏在 `<C-\>` 切换时实时更新，需要订阅 `User ShapeimToggle` 事件：

```lua
-- 加到你的 init.lua 或 autocmd 配置中
vim.api.nvim_create_autocmd("User", {
  pattern = "ShapeimToggle",
  callback = function() vim.cmd.redrawstatus() end,
  desc = "Redraw statusline on shapeim toggle",
})
```

`vim.opt.statusline` 只在 mode 切换或事件触发时重绘，不订阅事件则不会自动刷新。
lualine 用户如果设置了刷新间隔可能不需要，但加上 autocmd 能保证即时更新。

## 工作原理

```
码表:       .dict.yaml  ──compiler──▶  .mpack 缓存 (O(1) 查询)
                                          │
输入:       a-y 按键    ──buffer──▶  engine.get_candidates(code)
                                          │
补全:       blink.cmp / completefunc ◀───┘
                                          │
上屏:       空格 / 自动  ──▶  nvim_buf_set_text (原子 undo)
```

1. **编译:** `:ShapeimCompile` 解析 Rime `.dict.yaml` 并序列化为 `.mpack` 缓存，实现 O(1) 启动。
2. **输入:** `a`-`y` 字符原生进入 buffer，补全引擎可检测光标前的文本。
3. **补全:** 通过 blink.cmp 或 Neovim 内置补全查找并显示候选。
4. **上屏:** 空格或自动上屏将编码替换为中文文本，使用 `<C-g>u` 实现原子 undo。

## 文档

- `:help shapeim` — Vim 帮助文档（英文）
- `:help shapeim-rules` — 输入规则参考
- `:help shapeim-config` — 配置选项
- [plan.md](./doc/plan.md) — 设计文档（中文）
- [doc/](./doc/) — 架构、API、模块文档

## 测试

```bash
# 运行单元测试
nvim --headless -u NONE --cmd "set rtp+=." -l tests/compiler_spec.lua
nvim --headless -u NONE --cmd "set rtp+=." -l tests/engine_spec.lua
```

手动测试清单见 [doc/testing.md](./doc/testing.md)。

## 许可证

[MIT](./LICENSE)
