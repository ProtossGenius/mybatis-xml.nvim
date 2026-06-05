--- mybatis-xml.nvim 占位符跳转模块
--- 从 #{param.field} / ${param.field} 占位符跳转到对应的 Java 参数或 Model 字段
local M = {}

local util = require('mybatis-xml.util')
local log = require('mybatis-xml.log')
local parameter = require('mybatis-xml.completion.parameter')

-- ============================================================================
-- 辅助函数
-- ============================================================================

--- 获取光标所在位置的占位符内容
--- 匹配 #{content} 或 ${content}
---@param line string
---@param col number 光标列号(0-indexed)
---@return string|nil content 占位符内容（去除空白）
local function get_placeholder_at_cursor(line, col)
  local start_pos = 1
  while true do
    local p_start, p_end, content = line:find('[#$]%s*{%s*([^}]+)%s*}', start_pos)
    if not p_start then
      break
    end
    local val_start = p_start - 1
    local val_end = p_end - 1
    if col >= val_start and col <= val_end then
      return vim.trim(content)
    end
    start_pos = p_end + 1
  end
  return nil
end

--- 解析参数的完全限定类名
--- 优先使用 full_type，否则从 import 或同包下推断
---@param param table 参数信息 { type, full_type, ... }
---@param java_path string Mapper.java 文件路径
---@return string fqn 完全限定类名
local function resolve_param_type_fqn(param, java_path)
  if param.full_type:find('%.', 1, true) then
    return param.full_type
  end
  local lines = util.read_file_lines(java_path)
  local package = ''
  for _, l in ipairs(lines) do
    local pkg = l:match('^%s*package%s+([%w_%.]+)%s*;')
    if pkg then
      package = pkg
    end
    local imp = l:match('^%s*import%s+([%w_%.]+)%s*;')
    if imp then
      if imp:match('[^%.]+$') == param.type then
        return imp
      end
    end
  end
  if package ~= '' then
    return package .. '.' .. param.type
  end
  return param.type
end

--- 解析文件中类型名的完全限定名
--- 从文件的 import 声明和 package 声明推断
---@param type_name string 类型名（可能含泛型）
---@param file_path string Java 文件路径
---@return string fqn 完全限定类名
local function resolve_type_fqn_in_file(type_name, file_path)
  local simple_type = type_name:gsub('<[^>]*>', '')
  simple_type = simple_type:match('[^%.]+$') or simple_type

  local lines = util.read_file_lines(file_path)
  local package = ''
  for _, l in ipairs(lines) do
    local pkg = l:match('^%s*package%s+([%w_%.]+)%s*;')
    if pkg then
      package = pkg
    end
    local imp = l:match('^%s*import%s+([%w_%.]+)%s*;')
    if imp then
      if imp:match('[^%.]+$') == simple_type then
        return imp
      end
    end
  end
  if package ~= '' then
    return package .. '.' .. simple_type
  end
  return simple_type
end

--- 在文件行数组中查找方法声明行
---@param lines string[] 文件行数组
---@param method_name string 方法名
---@return number line_nr 行号（1-indexed）
local function find_method_line(lines, method_name)
  local escaped = vim.pesc(method_name)
  for i, l in ipairs(lines) do
    if l:find('%f[%w_]' .. escaped .. '%f[^%w_]%s*%(') then
      return i
    end
  end
  return 1
end

--- 在 Java 文件行数组中查找字段声明行
---@param lines string[] 文件行数组
---@param field_name string 字段名
---@return number line_nr 行号（1-indexed）
local function find_field_declaration_line(lines, field_name)
  local pattern = '%s+([%w_%.<>,%[%]]+)%s+' .. vim.pesc(field_name) .. '%s*[;=]'
  for i, line in ipairs(lines) do
    if not line:match('^%s*//') and not line:match('^%s*@') then
      if line:match(pattern) then
        return i
      end
    end
  end
  for i, line in ipairs(lines) do
    if not line:match('^%s*//') and not line:match('^%s*@') then
      if line:find('%f[%w_]' .. vim.pesc(field_name) .. '%f[^%w_]') then
        return i
      end
    end
  end
  return 1
end

-- ============================================================================
-- 公开函数
-- ============================================================================

--- 尝试从占位符跳转到对应的 Java 代码
--- 支持以下场景：
---   - #{param} -> 跳转到 Mapper.java 中的方法参数声明
---   - #{user.name} -> 跳转到 User 类的 name 字段声明
---   - #{username} (唯一 Model 参数) -> 跳转到 Model 的 username 字段
---@param bufnr number
---@return boolean
function M.try_jump_placeholder(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1]
  if not line then
    return false
  end

  local placeholder = get_placeholder_at_cursor(line, cursor[2])
  if not placeholder or placeholder == '' then
    return false
  end

  local parts = vim.split(placeholder, '.', { plain = true })
  if #parts == 0 then
    return false
  end

  local statement_id = util.find_current_statement_id(bufnr)
  if not statement_id then
    return false
  end

  local namespace = util.get_namespace(bufnr)
  if not namespace then
    return false
  end

  local java_path = util.find_java_file_by_fqn(namespace, bufnr)
  if not java_path then
    return false
  end

  local params = parameter.parse_method_params(java_path, statement_id)
  if not params or #params == 0 then
    return false
  end

  if #parts > 1 then
    -- 对应 #{user.name} 这种多级属性跳转
    for _, param in ipairs(params) do
      local display_name = param.param_annotation or param.name
      if display_name == parts[1] then
        local current_fqn = resolve_param_type_fqn(param, java_path)
        for idx = 2, #parts do
          local field = parts[idx]
          local m_path = util.find_java_file_by_fqn(current_fqn, bufnr)
          if not m_path then
            break
          end
          local m_lines = util.read_file_lines(m_path)
          local line_idx = find_field_declaration_line(m_lines, field)

          if idx == #parts then
            util.open_at(m_path, line_idx, 'edit')
            return true
          else
            local decl_line = m_lines[line_idx] or ''
            local type_name_match = decl_line:match('%s+([%w_%.<>,%[%]]+)%s+' .. vim.pesc(field) .. '%s*[;=]')
            if type_name_match then
              current_fqn = resolve_type_fqn_in_file(type_name_match, m_path)
            else
              break
            end
          end
        end
      end
    end
  else
    -- 对应 #{username} 这种单字段跳转
    -- 优先匹配 Mapper.java 的参数名
    for _, param in ipairs(params) do
      local display_name = param.param_annotation or param.name
      if display_name == parts[1] then
        local mapper_lines = util.read_file_lines(java_path)
        local method_line = find_method_line(mapper_lines, statement_id)
        util.open_at(java_path, method_line, 'edit')
        return true
      end
    end

    -- 其次如果只有一个 Model 参数，匹配 Model 的字段
    if #params == 1 and util.is_model_type(params[1].type) then
      local param = params[1]
      local current_fqn = resolve_param_type_fqn(param, java_path)
      local m_path = util.find_java_file_by_fqn(current_fqn, bufnr)
      if m_path then
        local m_lines = util.read_file_lines(m_path)
        local field_line = find_field_declaration_line(m_lines, parts[1])
        util.open_at(m_path, field_line, 'edit')
        return true
      end
    end
  end

  return false
end

-- ============================================================================
-- 测试接口
-- ============================================================================

M._test = {
  try_jump_placeholder = M.try_jump_placeholder,
  get_placeholder_at_cursor = get_placeholder_at_cursor,
  resolve_param_type_fqn = resolve_param_type_fqn,
  resolve_type_fqn_in_file = resolve_type_fqn_in_file,
  find_method_line = find_method_line,
  find_field_declaration_line = find_field_declaration_line,
}

return M
