--- mybatis-xml.nvim 通用工具函数
--- 提供文件读取、FQN解析、光标属性获取等基础工具
local M = {}

local uv = vim.uv or vim.loop
local project = require('mybatis-xml.project')

-- ============================================================================
-- 常量定义
-- ============================================================================

--- 已知的基本类型/包装类型，不需要展开字段
M.PRIMITIVE_TYPES = {
  String = true, Integer = true, Long = true, Double = true, Float = true,
  Boolean = true, Short = true, Byte = true, Character = true,
  BigDecimal = true, BigInteger = true, Date = true,
  LocalDate = true, LocalDateTime = true,
  int = true, long = true, double = true, float = true,
  boolean = true, short = true, byte = true, char = true,
  -- 常见集合/Map类型也视为基本类型
  List = true, Set = true, Map = true, Collection = true,
  Object = true, Void = true,
}

--- 属性名白名单：这些属性的值被视为类引用（FQN）
M.CLASS_REF_ATTRS = {
  type = true,
  resulttype = true,
  parametertype = true,
  oftype = true,
  javatype = true,
  typehandler = true,
}

--- MyBatis XML 标签属性定义
M.TAG_ATTRIBUTES = {
  select = { 'id', 'parameterType', 'resultType', 'resultMap', 'flushCache', 'useCache', 'timeout', 'fetchSize', 'statementType', 'resultSetType', 'databaseId', 'resultOrdered', 'resultSets' },
  insert = { 'id', 'parameterType', 'flushCache', 'timeout', 'statementType', 'keyProperty', 'useGeneratedKeys', 'keyColumn', 'databaseId' },
  update = { 'id', 'parameterType', 'flushCache', 'timeout', 'statementType', 'keyProperty', 'useGeneratedKeys', 'keyColumn', 'databaseId' },
  delete = { 'id', 'parameterType', 'flushCache', 'timeout', 'statementType', 'databaseId' },
  resultmap = { 'id', 'type', 'extends', 'autoMapping' },
  result = { 'property', 'column', 'javaType', 'jdbcType', 'typeHandler' },
  id = { 'property', 'column', 'javaType', 'jdbcType', 'typeHandler' },
  association = { 'property', 'column', 'javaType', 'jdbcType', 'typeHandler', 'select', 'resultMap', 'foreignColumn', 'resultSet', 'columnPrefix', 'notNullColumn' },
  collection = { 'property', 'column', 'javaType', 'ofType', 'jdbcType', 'typeHandler', 'select', 'resultMap', 'foreignColumn', 'resultSet', 'columnPrefix', 'notNullColumn' },
  mapper = { 'namespace' },
  foreach = { 'collection', 'item', 'index', 'open', 'close', 'separator' },
  ['if'] = { 'test' },
  when = { 'test' },
  trim = { 'prefix', 'suffix', 'prefixOverrides', 'suffixOverrides' },
  bind = { 'name', 'value' },
  include = { 'refid' },
  sql = { 'id' },
}

-- ============================================================================
-- 文件操作
-- ============================================================================

--- 读取文件内容为行数组
---@param path string
---@return string[]
function M.read_file_lines(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return {}
  end
  return lines
end

--- 检查路径是否是文件
---@param path string|nil
---@return boolean
function M.is_file(path)
  local stat = path and path ~= '' and uv.fs_stat(path) or nil
  return stat and stat.type == 'file' or false
end

-- ============================================================================
-- FQN（完全限定名）操作
-- ============================================================================

--- 将 FQN 转为相对文件路径: com.example.User -> com/example/User.java
---@param fqn string
---@return string
function M.fqn_to_path(fqn)
  return fqn:gsub('%.', '/') .. '.java'
end

--- 在 project root 下搜索 Java 文件 (FQN -> file path)
---@param fqn string 完全限定类名
---@param bufnr number|nil
---@return string|nil path
function M.find_java_file_by_fqn(fqn, bufnr)
  local root = project.root(bufnr)
  local rel_path = M.fqn_to_path(fqn)

  -- 优先在 src/main/java 和 src/test/java 下精确查找
  for _, java_root in ipairs({ 'src/main/java', 'src/test/java' }) do
    local exact = vim.fs.joinpath(root, java_root, rel_path)
    if M.is_file(exact) then
      return exact
    end
  end

  -- fallback: 用 project.find_exact_file 按 basename 查找
  local basename = fqn:match('[^%.]+$') .. '.java'
  local found, err = project.find_exact_file(basename, { root = root })
  if found then
    return found
  end

  -- find_exact_file 返回多个匹配时也会返回 nil，此时手动搜索
  if err and err:match('multiple') then
    local matches = vim.fs.find(function(name)
      return name == basename
    end, { path = root, type = 'file', limit = 20 })
    -- 尝试匹配包含 FQN 路径片段的结果
    local fqn_path_fragment = fqn:gsub('%.', '/')
    for _, match in ipairs(matches) do
      if match:find(fqn_path_fragment, 1, true) then
        return match
      end
    end
    -- 返回第一个
    return matches[1]
  end
end

-- ============================================================================
-- 光标与属性操作
-- ============================================================================

--- 获取光标所在行的属性值（type="...", resultType="...", parameterType="..." 等）
--- 返回属性名和属性值
---@param line string
---@param col number 光标列号(0-indexed)
---@return string|nil attr_name, string|nil attr_value
function M.get_attribute_at_cursor(line, col)
  local start_pos = 1
  while true do
    local attr_start, attr_end, attr_name, _, attr_value = line:find('([%w_]+)%s*=%s*(["\'])(.-)%2', start_pos)
    if not attr_start then
      break
    end
    local val_start = attr_start - 1
    local val_end = attr_end - 1
    if col >= val_start and col <= val_end then
      return attr_name, attr_value
    end
    start_pos = attr_end + 1
  end
end

--- 在属性值内查找属性名和引号起始位置
---@param line string
---@param col number 0-indexed
---@return string|nil attr_name_lower, number|nil quote_start_col
function M.find_attribute_start(line, col)
  local start_pos = 1
  while true do
    local attr_start, attr_end, attr_name, quote_char = line:find('([%w_]+)%s*=%s*(["\'])', start_pos)
    if not attr_start then
      break
    end
    -- 找到属性值的起始引号位置（0-indexed）
    local quote_pos = line:find(quote_char, attr_start + #attr_name)
    if quote_pos then
      -- 找到闭合引号
      local close_quote = line:find(quote_char, quote_pos + 1)
      if close_quote then
        -- col 在引号范围内 [quote_pos, close_quote] (0-indexed)
        if col >= quote_pos and col <= close_quote - 1 then
          return attr_name:lower(), quote_pos  -- 返回引号后第一个字符的列号(1-indexed)
        end
        start_pos = close_quote + 1
      else
        -- 没有闭合引号，假设到行尾
        if col >= quote_pos then
          return attr_name:lower(), quote_pos
        end
        break
      end
    else
      break
    end
  end
  return nil, nil
end

--- 打开文件并跳转到指定行
---@param path string
---@param line_nr number|nil
---@param cmd string|nil
function M.open_at(path, line_nr, cmd)
  vim.cmd((cmd or 'edit') .. ' ' .. vim.fn.fnameescape(path))
  vim.api.nvim_win_set_cursor(0, { math.max(line_nr or 1, 1), 0 })
  vim.cmd('normal! zz')
end

-- ============================================================================
-- Mapper XML 解析
-- ============================================================================

--- 从当前 buffer 获取 mapper namespace
---@param bufnr number
---@return string|nil
function M.get_namespace(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for _, line in ipairs(lines) do
    local ns = line:match('<mapper.-namespace%s*=%s*"([^"]+)"')
    if ns then
      return ns
    end
  end
end

--- 检查当前 buffer 是否是 mybatis mapper xml
---@param bufnr number
---@return boolean
function M.is_mybatis_mapper(bufnr)
  if vim.bo[bufnr].filetype ~= 'xml' then
    return false
  end
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local check_lines = math.min(line_count, 30)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, check_lines, false)
  for _, line in ipairs(lines) do
    if line:match('<!DOCTYPE%s+mapper') or line:match('<mapper.-namespace') then
      return true
    end
  end
  return false
end

--- 向上搜索当前光标所在的 SQL 语句块，获取 statement id
---@param bufnr number
---@return string|nil statement_id
function M.find_current_statement_id(bufnr)
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local statement_tags = {
    select = true,
    insert = true,
    update = true,
    delete = true,
  }

  for start_line = cursor_line, 1, -1 do
    local tag_name = lines[start_line]:match('<(%w+)')
    if tag_name and statement_tags[tag_name] then
      local tag_text = lines[start_line]
      local end_line = start_line
      while end_line < #lines and not tag_text:find('>', 1, true) do
        end_line = end_line + 1
        tag_text = tag_text .. '\n' .. lines[end_line]
      end
      local statement_id = tag_text:match('id%s*=%s*"([^"]+)"')
      if statement_id then
        return statement_id
      end
    end
  end
end

--- 判断类型是否是 Model（非基本类型，首字母大写）
---@param type_name string
---@return boolean
function M.is_model_type(type_name)
  if not type_name or type_name == '' then
    return false
  end
  local simple = type_name:match('[^%.]+$') or type_name
  if M.PRIMITIVE_TYPES[simple] then
    return false
  end
  return simple:match('^%u') ~= nil
end

-- ============================================================================
-- 测试接口
-- ============================================================================

M._test = {
  get_attribute_at_cursor = M.get_attribute_at_cursor,
  find_attribute_start = M.find_attribute_start,
  fqn_to_path = M.fqn_to_path,
  find_java_file_by_fqn = M.find_java_file_by_fqn,
  get_namespace = M.get_namespace,
  is_mybatis_mapper = M.is_mybatis_mapper,
  find_current_statement_id = M.find_current_statement_id,
  is_model_type = M.is_model_type,
  read_file_lines = M.read_file_lines,
  is_file = M.is_file,
}

return M
