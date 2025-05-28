-- lua/sleuth/config.lua
local M = { opts = {} }

local default_opts = {
  modeline       = true,
  editorconfig   = true,
  neighbor_limit = 8,
  max_lines      = 256,
  notify = false,
}

function M.init(user)
  M.opts = vim.tbl_deep_extend('force', default_opts, user or {})
end

return M
