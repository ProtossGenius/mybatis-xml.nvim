--- mybatis-xml.nvim resultMap 跳转模块
--- 支持 resultMap 引用跳转和 resultMap property 属性跳转到 Model 字段
local M = {}

local util = require('mybatis-xml.util')
local log = require('mybatis-xml.log')

-- ============================================================================
-- 辅助函数
-- ============================================================================

--- 查找光标所在位置的 resultMap 标签，返回其 type 属性值
--- 向上搜索直到找到 <resultMap> 标签
---@param bufnr number
---@return string|nil model_type FQN 类型
local function find_enclosing_resultmap_type(bufnr)
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i = cursor_line, 1, -1 do
    local line = lines[i]
    if line:match('</resultMap>') then
      return nil
    end
    if line:match('<resultMap') then
      local model_type = line:match('type%s*=%s*"([^"]+)"') or line:match("type%s*=%s*'([^']+)'")
      if model_type then
        return model_type
      end
    end
  end
  return nil
end

--- 在 Java 文件的行数组中查找字段声明行
---@param lines string[] 文件行数组
---@param field_name string 字段名
---@return number line_nr 行号（1-indexed）
local function find_field_declaration_line(lines, field_name)
  -- 优先精确匹配字段声明模式: Type fieldName;
  local pattern = '%s+([%w_%.<>,%[%]]+)%s+' .. vim.pesc(field_name) .. '%s*[;=]'
  for i, line in ipairs(lines) do
    if not line:match('^%s*//') and not line:match('^%s*@') then
      if line:match(pattern) then
        return i
      end
    end
  end
  -- fallback: 模糊匹配字段名出现的位置
  for i, line in ipairs(lines) do
    if not line:match('^%s*//') and not line:match('^%s*@') then
      if line:find('%f[%w_]' .. vim.pesc(field_name) .. '%f[^%w_]') then
        return i
      end
    end
  end
  return 1
end

--- 跳转到 Model 类的字段声明处
---@param model_fqn string 完全限定类名
---@param field_name string 字段名
---@param bufnr number
---@return boolean 是否成功跳转
local function jump_to_model_field(model_fqn, field_name, bufnr)
  local java_path = util.find_java_file_by_fqn(model_fqn, bufnr)
  if not java_path then
    return false
  end

  local lines = util.read_file_lines(java_path)
  if #lines == 0 then
    return false
  end

  local line_nr = find_field_declaration_line(lines, field_name)
  util.open_at(java_path, line_nr, 'edit')
  return true
end

-- ============================================================================
-- 公开函数
-- ============================================================================

--- 尝试跳转到 resultMap 定义
--- 检查光标是否在 resultMap 属性上，跳转到对应的 <resultMap> 定义
---@param bufnr number
---@return boolean
function M.try_jump_result_map(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1]
  if not line then
    return false
  end

  local attr_name, attr_value = util.get_attribute_at_cursor(line, cursor[2])
  if not attr_name or attr_name:lower() ~= 'resultmap' or not attr_value or attr_value == '' then
    return false
  end

  -- 在当前 buffer 中查找 <resultMap ... id="VALUE"
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local escaped = vim.pesc(attr_value)
  for i, l in ipairs(lines) do
    if l:match('<resultMap') and l:match('id%s*=%s*"' .. escaped .. '"') then
      vim.api.nvim_win_set_cursor(0, { i, 0 })
      vim.cmd('normal! zz')
      return true
    end
  end

  log.warn('找不到 resultMap 定义: ' .. attr_value)
  return true
end

--- 尝试跳转到 resultMap 中 property 属性对应的 Model 字段
--- 例如 <result property="userName" .../> 会跳转到 Model 类的 userName 字段声明
---@param bufnr number
---@return boolean
function M.try_jump_resultmap_property(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1]
  if not line then
    return false
  end

  local property_val = line:match('property%s*=%s*"([^"]+)"') or line:match("property%s*=%s*'([^']+)'")
  if not property_val or property_val == '' then
    return false
  end

  local model_type = find_enclosing_resultmap_type(bufnr)
  if not model_type then
    return false
  end

  if jump_to_model_field(model_type, property_val, bufnr) then
    return true
  end

  return false
end

-- ============================================================================
-- 测试接口
-- ============================================================================

M._test = {
  try_jump_result_map = M.try_jump_result_map,
  try_jump_resultmap_property = M.try_jump_resultmap_property,
  find_enclosing_resultmap_type = find_enclosing_resultmap_type,
  find_field_declaration_line = find_field_declaration_line,
  jump_to_model_field = jump_to_model_field,
}

return M
