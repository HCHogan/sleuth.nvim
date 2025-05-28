-- lua/sleuth/editorconfig.lua
local util = require('sleuth.util')
local M = {}

-- 搜索并读取最近的 .editorconfig
function M.detect(bufname, opts)
  local cwd = vim.fn.fnamemodify(bufname, ':p:h')
  local limit = opts.neighbor_limit
  local config = {}
  while limit > 0 and cwd ~= vim.fn.fnamemodify(cwd, ':h') do
    local path = cwd .. '/.editorconfig'
    if vim.fn.filereadable(path) == 1 then
      local pairs = util.readfile(path)
      for _, line in ipairs(pairs) do
        local k, v = line:match('^%s*(%w+)%s*=%s*(%w+)%s*$')
        if k == 'indent_style' then
          config.expandtab = (v == 'space')
        elseif k == 'indent_size' then
          config.shiftwidth = tonumber(v)
        elseif k == 'tab_width' then
          config.tabstop = tonumber(v)
        end
      end
      break
    end
    cwd = vim.fn.fnamemodify(cwd, ':h')
    limit = limit - 1
  end
  return config
end

return M
