-- lua/sleuth/init.lua
local api = vim.api
local fn  = vim.fn
local M   = {}

-- 默认参数
local default_opts = {
  detect_filetype = true,   -- 是否根据 modeline/EditorConfig 也设置 filetype
  permitted       = {       -- 最终允许修改的选项
    'expandtab', 'shiftwidth', 'tabstop', 'textwidth', 'fixendofline'
  },
}

--- 打印 warning
-- @param msg string
-- @param silent boolean
function M.warn(msg, silent)
  if not silent then
    vim.notify('[sleuth] ' .. msg, vim.log.levels.WARN)
  end
end

--- 将 Windows 路径分隔符 `\` 转成 `/`
function M.slash(path)
  return path:gsub([[\\]], '/')
end

local H = require('sleuth.heuristics')

--- 初始化一次检测
-- @param redetect boolean
-- @param unsafe    boolean
-- @param do_ft     boolean
-- @param silent    boolean
function M.init(redetect, unsafe, do_ft, silent)
  local bufnr = api.nvim_get_current_buf()
  local ft     = api.nvim_buf_get_option(bufnr, 'filetype')
  local bufname= api.nvim_buf_get_name(bufnr)
  if not redetect and vim.b.sleuth then
    -- 已缓存过
    return
  end
  vim.b.sleuth = nil

  -- 不处理特殊 buffer
  local bt = api.nvim_buf_get_option(bufnr, 'buftype')
  if bt:match('^nowrite') or ft == 'netrw' or api.nvim_buf_get_option(bufnr, 'binary') then
    return M.warn('disabled for buftype=' .. bt, silent)
  end

  -- modeline / EditorConfig
  local declared = H.parse_user_options(bufname)
  if do_ft and declared.filetype then
    api.nvim_command('setlocal filetype=' .. declared.filetype)
  end

  -- Heuristics
  local detected = {
    bufname   = M.slash(bufname),
    declared  = declared,
    options   = {},
    heuristics= {},
    defaults  = declared.defaults or {},
  }

  H.detect_editorconfig(detected)
  H.detect_modeline(detected)

  if not H.ready(detected) then
    local lines = api.nvim_buf_get_lines(bufnr, 0, math.min(1024, api.nvim_buf_line_count(bufnr)), false)
    H.guess(detected, lines)
  end

  -- 如果依然没检测到 shiftwidth，就退回到 defaults
  if not H.ready(detected) then
    detected.options = vim.tbl_deep_extend('force', {}, detected.declared)
  end

  -- 应用到 buffer
  local cmd = H.apply_options(detected, unsafe and H.all_options or default_opts.permitted, silent)
  if cmd and #cmd > 0 then
    api.nvim_command(cmd)
  end

  vim.b.sleuth = detected
end

--- 自动触发入口
function M.auto_init()
  M.init(true, true, true, false)
end

--- 用户可调用的 setup
-- @param opts table
function M.setup(opts)
  opts = vim.tbl_extend('force', default_opts, opts or {})
  -- Autocmd group
  local grp = api.nvim_create_augroup('nvim_sleuth', { clear = true })

  api.nvim_create_autocmd({'BufReadPost','BufNewFile','BufFilePost'}, {
    group    = grp,
    callback = function() M.auto_init() end,
  })
  api.nvim_create_autocmd('FileType', {
    group    = grp,
    callback = function() M.init(false, false, false, true) end,
  })
end

return M

