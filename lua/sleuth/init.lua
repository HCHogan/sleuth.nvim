-- lua/sleuth/init.lua
local M            = {}

local cfg          = require('sleuth.config')
local util         = require('sleuth.util')
local modeline     = require('sleuth.modeline')
local editorconfig = require('sleuth.editorconfig')
local heuristics   = require('sleuth.heuristics')

-- 默认 setup
function M.setup(user_opts)
  cfg.init(user_opts)

  -- 创建自动命令组
  local aug = vim.api.nvim_create_augroup('Sleuth', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufNewFile', 'BufReadPost' }, {
    group    = aug,
    callback = function() M.auto_init() end,
  })
  vim.api.nvim_create_autocmd('FileType', {
    group    = aug,
    callback = function()
      if vim.b.sleuth_opts then M.apply(vim.b.sleuth_opts) end
    end,
  })

  -- 提供命令
  vim.api.nvim_create_user_command('Sleuth', function()
    M.auto_init(true)
  end, { desc = 'Run sleuth indentation detection' })
end

-- 自动初始化
function M.auto_init(force)
  local bufnr = vim.api.nvim_get_current_buf()
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if bufname == '' then return end

  -- 1. 用户在 b: 中声明的优先
  local declared = modeline.parse(vim.api.nvim_get_current_buf())
  if cfg.opts.editorconfig then
    local ec = editorconfig.detect(bufname, cfg.opts)
    vim.tbl_extend('keep', declared, ec)
  end

  -- 2. 如果有足够 declared，就直接 apply
  if declared.shiftwidth and declared.expandtab ~= nil then
    vim.b.sleuth_opts = declared
    return M.apply(declared)
  end

  -- 3. 扫 buffer 前 N 行或邻近文件尝试猜测
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, cfg.opts.max_lines, false)
  local guess = heuristics.guess(bufname, lines, declared, cfg.opts)
  vim.b.sleuth_opts = guess
  return M.apply(guess)
end

-- 应用探测结果
function M.apply(opts)
  local o = vim.opt_local
  if opts.expandtab ~= nil then o.expandtab = opts.expandtab end
  if opts.shiftwidth then o.shiftwidth = opts.shiftwidth end
  if opts.tabstop then o.tabstop = opts.tabstop end
  if opts.textwidth then o.textwidth = opts.textwidth end

  if cfg.opts.notify then
    local parts = {}
    if opts.shiftwidth then table.insert(parts, 'sw=' .. opts.shiftwidth) end
    if opts.tabstop then table.insert(parts, 'ts=' .. opts.tabstop) end
    if opts.expandtab ~= nil then
      table.insert(parts, (opts.expandtab and 'expandtab' or 'noexpandtab'))
    end
    if opts.textwidth then table.insert(parts, 'tw=' .. opts.textwidth) end
    vim.notify(('sleuth applied: %s'):format(table.concat(parts, ', ')), vim.log.levels.INFO)
  end
end

return M
