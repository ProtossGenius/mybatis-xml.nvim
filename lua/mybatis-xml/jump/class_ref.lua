--- mybatis-xml.nvim 类引用跳转
--- 从 XML 中的类引用属性（type, resultType, parameterType 等）跳转到对应 Java 文件
local M = {}

local util = require('mybatis-xml.util')
local log = require('mybatis-xml.log')

--- 尝试从光标位置跳转到类引用
--- 检查当前光标是否在类引用属性（type, resultType, parameterType 等）上，
--- 如果是则跳转到对应的 Java 类文件
---@param bufnr number
---@return boolean jumped 是否成功跳转
function M.try_jump_class_ref(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1]
  if not line then
    return false
  end

  local attr_name, attr_value = util.get_attribute_at_cursor(line, cursor[2])
  if not attr_name or not attr_value then
    return false
  end

  -- 检查属性名是否是类引用类型（不区分大小写）
  if not util.CLASS_REF_ATTRS[attr_name:lower()] then
    return false
  end

  if attr_value == '' then
    return false
  end

  local java_path = util.find_java_file_by_fqn(attr_value, bufnr)
  if java_path then
    util.open_at(java_path, 1, 'edit')
    return true
  end

  log.warn('找不到类文件: ' .. attr_value)
  return true  -- 已识别为类引用，但未找到文件
end

-- ============================================================================
-- 测试接口
-- ============================================================================

M._test = {
  try_jump_class_ref = M.try_jump_class_ref,
}

return M
