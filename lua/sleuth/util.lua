-- lua/sleuth/util.lua
local uv = vim.loop
local M = {}

-- 将 Windows 路径分隔符替换为 '/'
function M.slash(path)
  return path:gsub('\\', '/')
end

-- 读取文件所有行
function M.readfile(path)
  local ok, data = pcall(vim.fn.readfile, path)
  return ok and data or {}
end

return M

