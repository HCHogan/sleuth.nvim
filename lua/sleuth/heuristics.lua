-- lua/sleuth/heuristics.lua
local M = {}

-- 基本缩进猜测：扫描行，统计 tab/space/增量出现频率
function M.guess(bufname, lines, declared, opts)
  local stats = { tabs=0, spaces=0, indents={}, total=0 }
  local prev = nil
  local tabwidth = declared.tabstop or vim.o.tabstop

  for _, line in ipairs(lines) do
    if #line>0 then
      local indent = select(2, line:gsub('\t',''))*tabwidth
                   + #line:match('^ *')
      if line:match('^\t') then stats.tabs = stats.tabs+1 end
      if line:match('^ '..string.rep(' ',1)) then stats.spaces = stats.spaces+1 end
      if prev then
        local inc = indent - prev
        if inc>0 and inc<12 then
          stats.indents[inc] = (stats.indents[inc] or 0) + 1
        end
      end
      prev = indent
      stats.total = stats.total + 1
    end
  end

  -- 选最频繁的 indent
  local best, freq = declared.shiftwidth or 0, 0
  for inc,count in pairs(stats.indents) do
    if count>freq or (count==freq and inc<best) then
      best, freq = inc, count
    end
  end

  return {
    expandtab   = declared.expandtab~=nil and declared.expandtab or (stats.spaces>=stats.tabs),
    shiftwidth  = declared.shiftwidth  or best>0 and best or vim.o.shiftwidth,
    tabstop     = declared.tabstop     or vim.o.tabstop,
  }
end

return M

