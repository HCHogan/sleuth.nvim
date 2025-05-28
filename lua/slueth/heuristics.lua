-- lua/sleuth/heuristics.lua
local fn      = vim.fn
local vimr    = vim.regex
local M       = {}

-- 可选配置项全集（包括 EditorConfig 支持的那些）
M.all_options = {
  'expandtab', 'shiftwidth', 'tabstop', 'textwidth', 'fixendofline',
  'endofline', 'fileformat', 'fileencoding', 'bomb'
}

-- 判断是否已经检测到足够的数据
function M.ready(det)
  return det.options.expandtab ~= nil and det.options.shiftwidth ~= nil
end

-- 解析 b:sleuth_* 或 g:sleuth_filetype_* 这类用户手工设置
function M.parse_user_options(bufname)
  local opts = { defaults = {} }
  -- 这里简化：用户可以通过 vim.g.sleuth_<ft>_defaults 设默认值
  return opts
end

-- 模式：解析 Vim modeline
function M.detect_modeline(det)
  -- 简化版：循环前后 5 行，匹配 set ts= sw= et
  local lines = fn.getbufline(0, 1, 5)
  for _, l in ipairs(lines) do
    for key, val in l:gmatch('(%w+)%s*=%s*(%d+)') do
      if key == 'ts' or key == 'tabstop' then det.options.tabstop = tonumber(val) end
      if key == 'sw' or key == 'shiftwidth' then det.options.shiftwidth = tonumber(val) end
    end
    if l:find('et') then det.options.expandtab = true end
    if l:find('noet') then det.options.expandtab = false end
  end
end

-- 把 EditorConfig 的 glob 模式（比如 "*.py", "src/**/test?.js"）转成 Lua 的 pattern
function M.fnmatch_to_pattern(pat)
  -- 先转义 Lua magic 字符
  local p = pat:gsub("([%^%$%(%)%%%.%[%]%+%-%?])", "%%%1")
  -- ** → .*
  p = p:gsub("%*%*", ".*")
  -- *  → [^/]*
  p = p:gsub("%*", "[^/]*")
  -- ?  → .
  p = p:gsub("%?", ".")
  return "^" .. p .. "$"
end

-- 把 parse 出来的 EditorConfig key/value 转换成 nvim-sleuth 的选项
function M.editorconfig_to_options(pairs)
  local opts = {}

  -- indent style
  if pairs.indent_style == "tab" then
    opts.expandtab = false
  elseif pairs.indent_style == "space" then
    opts.expandtab = true
  end

  -- indent size
  if pairs.indent_size then
    local n = tonumber(pairs.indent_size)
    if n then
      opts.shiftwidth = n
      -- 如果没有显式 tab_width，就让 tabstop = indent_size
      if not pairs.tab_width then
        opts.tabstop = n
      end
    end
  end

  -- tab width
  if pairs.tab_width then
    local n = tonumber(pairs.tab_width)
    if n then
      opts.tabstop = n
    end
  end

  -- max line length → textwidth
  if pairs.max_line_length then
    local n = tonumber(pairs.max_line_length)
    if n then
      opts.textwidth = n
    end
  end

  -- insert_final_newline → fixendofline
  if pairs.insert_final_newline == "true" then
    opts.fixendofline = true
  elseif pairs.insert_final_newline == "false" then
    opts.fixendofline = false
  end

  -- end_of_line → fileformat
  if pairs.end_of_line then
    local e = pairs.end_of_line:lower()
    if e == "lf" then
      opts.fileformat = "unix"
    elseif e == "crlf" then
      opts.fileformat = "dos"
    elseif e == "cr" then
      opts.fileformat = "mac"
    end
  end

  -- charset → fileencoding、bom
  if pairs.charset then
    local c = pairs.charset:lower()
    -- bom 信息不在这里单独处理，nvim-sleuth 目前只关心 fileencoding
    opts.fileencoding = c:gsub("%-bom$", "")
  end

  -- vim_filetype → filetype
  if pairs.vim_filetype then
    opts.filetype = pairs.vim_filetype
  end

  return opts
end

--- 从当前 buffer 路径向上查找并解析 .editorconfig，把结果合并进 det.declared
-- @param det table  需要包含 det.bufname、det.declared 两个字段
function M.detect_editorconfig(det)
  local path = det.bufname
  if path == "" then
    det.editorconfig = {}
    det.root = ""
    return
  end

  -- 向上查找 .editorconfig
  local filename  = vim.g.sleuth_editorconfig_filename or ".editorconfig"
  local overrides = vim.g.sleuth_editorconfig_overrides or {}
  local dir       = fn.fnamemodify(path, ":p:h")
  local prev      = nil
  local root_dir  = ""
  local sections  = {} -- 存放 { pattern, pairs } 的列表

  while dir and dir ~= prev and dir ~= "" do
    -- 看有没有用户 override 路径
    local cfg = overrides[dir .. "/" .. filename] or overrides[dir] or (dir .. "/" .. filename)
    if fn.filereadable(cfg) == 0 then
      break
    end

    local lines    = fn.readfile(cfg)
    local preamble = {}
    local current  = preamble

    -- 简单解析 EditorConfig 文件
    for _, raw in ipairs(lines) do
      local s = raw:match("^%s*(.-)%s*$")
      -- 空行或注释
      if s == "" or s:match("^[;#]") then
        -- skip
        -- 区块头 [pattern]
      elseif s:match("^%[") then
        local pat = s:match("^%[([^%]]+)%]%s*$")
        if pat then
          local regex = M.fnmatch_to_pattern(pat)
          local tbl   = {}
          table.insert(sections, { regex, tbl })
          current = tbl
        end
        -- key = value
      elseif s:find("=") then
        local k, v = s:match("^(%S+)%s*=%s*(%S+)%s*$")
        if k and v then
          current[k:lower()] = v
        end
      end
    end

    -- 如果在 preamble 里出现 root = true，则认为到这里是顶层
    if preamble["root"] == "true" then
      root_dir = dir
    end
    if root_dir ~= "" then
      break
    end

    prev = dir
    dir  = fn.fnamemodify(dir, ":h")
  end

  -- 合并所有匹配当前文件路径的 section
  det.editorconfig = {}
  det.root = root_dir
  for _, sec in ipairs(sections) do
    local patt, pairs = sec[1], sec[2]
    if path:match(patt) then
      for k, v in pairs(pairs) do
        det.editorconfig[k] = v
      end
    end
  end

  -- 把 editorconfig 转成 nvim-sleuth 选项，合并到 det.declared
  local ec_opts = M.editorconfig_to_options(det.editorconfig)
  det.declared = vim.tbl_deep_extend("force", det.declared or {}, ec_opts)
end

--- 主要启发式检测
-- @param det table
-- @param lines string[]
function M.guess(det, lines)
  local heur = {
    hard    = 0,
    soft    = 0,
    spaces  = 0,
    checked = 0,
    indents = {}
  }
  local prev_indent, prev_line = -1, ''
  local tabstop = 8
  local softtab = (' '):rep(tabstop)

  for _, line in ipairs(lines) do
    if line:match([[^\s*$]]) then goto continue end

    -- 统计硬 tab / 软 tab
    if line:match('^\t') then
      heur.hard = heur.hard + 1
    elseif line:match('^' .. softtab) then
      heur.soft = heur.soft + 1
    end
    if line:match('^  ') then
      heur.spaces = heur.spaces + 1
    end

    -- 计算缩进级差
    local expanded = line:gsub('\t', softtab)
    local indent   = #expanded:match('^ *')
    local inc      = (prev_indent < 0) and 0 or (indent - prev_indent)
    prev_indent    = indent

    if inc > 1 and (inc < 4 or inc % 4 == 0) then
      heur.indents[inc] = (heur.indents[inc] or 0) + 1
      heur.checked = heur.checked + 1
    end

    if heur.checked >= 32 then break end
    ::continue::
  end

  -- 选出出现频率最高的 indent
  local best, freq = 0, 0
  for sw, cnt in pairs(heur.indents) do
    if cnt > freq or (cnt == freq and sw < best) then
      best, freq = sw, cnt
    end
  end

  local opts = {}
  if heur.hard > heur.soft then
    opts.expandtab = false
    opts.tabstop   = tabstop
  else
    opts.expandtab = true
    if freq > 0 then opts.shiftwidth = best end
  end
  det.options = vim.tbl_deep_extend('keep', opts, det.options)
end

--- 将 det.options 转换为 `setlocal …` 命令
-- @param det        table
-- @param permitted  string[]
-- @param silent     boolean
-- @return string    Vim command
function M.apply_options(det, permitted, silent)
  local cmd = { 'setlocal' }
  for _, opt in ipairs(permitted) do
    local v = det.options[opt]
    if v == nil then goto skip end

    if opt == 'expandtab' then
      table.insert(cmd, (v and '' or 'no') .. 'expandtab')
    else
      table.insert(cmd, string.format('%s=%s', opt, v))
    end

    ::skip::
  end

  if #cmd > 1 then
    -- 汇总警告输出
    if not silent then
      vim.notify('[sleuth] ' .. table.concat(cmd, ' '), vim.log.levels.INFO)
    end
    return table.concat(cmd, ' ')
  end
end

return M
