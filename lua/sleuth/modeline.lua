-- lua/sleuth/modeline.lua
local M = {}

-- 简单版：扫描首尾若干行，匹配 Vim modeline（vim:set …）
function M.parse(bufnr)
  local res = {}
  if not vim.bo[bufnr].modeline then return res end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 5, false)
  vim.list_extend(lines, vim.api.nvim_buf_get_lines(bufnr, -5, -1, false))
  for _, line in ipairs(lines) do
    for opt, val in line:gmatch('%f[%w](%w+)=(%d+)%f[%W]') do
      if opt == 'ts' or opt == 'tabstop' then res.tabstop = tonumber(val) end
      if opt == 'sw' or opt == 'shiftwidth' then res.shiftwidth = tonumber(val) end
      if opt == 'tw' or opt == 'textwidth' then res.textwidth = tonumber(val) end
    end
    if line:match('%f[%w](no?expandtab)%f[%W]') then
      res.expandtab = not line:match('noexpandtab')
    end
  end
  return res
end

return M
