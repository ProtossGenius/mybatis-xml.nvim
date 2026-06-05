--- mybatis-xml.nvim refid 跳转模块
--- 从 <include refid="..."/> 跳转到对应的 <sql id="..."> 定义
local M = {}

local util = require('mybatis-xml.util')
local log = require('mybatis-xml.log')

--- 尝试跳转到 sql id 定义 (通过 refid)
--- 检查光标是否在 refid 属性上，跳转到对应的 <sql> 定义
---@param bufnr number
---@return boolean
function M.try_jump_refid(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1]
  if not line then
    return false
  end

  local attr_name, attr_value = util.get_attribute_at_cursor(line, cursor[2])
  if attr_name ~= 'refid' or not attr_value or attr_value == '' then
    return false
  end

  -- 在当前 buffer 中查找 <sql ... id="VALUE"
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local escaped = vim.pesc(attr_value)
  for i, l in ipairs(lines) do
    if l:match('<sql') and l:match('id%s*=%s*"' .. escaped .. '"') then
      vim.api.nvim_win_set_cursor(0, { i, 0 })
      vim.cmd('normal! zz')
      return true
    end
  end

  log.warn('找不到 sql 定义: ' .. attr_value)
  return true
end

-- ============================================================================
-- 测试接口
-- ============================================================================

M._test = {
  try_jump_refid = M.try_jump_refid,
}

return M
