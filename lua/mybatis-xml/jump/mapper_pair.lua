--- mybatis-xml.nvim Mapper 对跳转模块
--- 在 Mapper.java 与 Mapper.xml 之间互相跳转
--- 支持自动生成 XML 语句块
local M = {}

local util = require('mybatis-xml.util')
local log = require('mybatis-xml.log')
local project = require('mybatis-xml.project')
local parameter = require('mybatis-xml.completion.parameter')

-- ============================================================================
-- 辅助函数（local）
-- ============================================================================

--- 获取文件名（不含路径）
---@param path string
---@return string
local function basename(path)
  return vim.fn.fnamemodify(path, ':t')
end

--- 在目录下按文件名搜索文件
---@param root string 搜索根目录
---@param filename string 文件名
---@param limit number|nil 最大结果数
---@return string[] 匹配的文件路径列表
local function find_files_by_name(root, filename, limit)
  return vim.fs.find(function(name)
    return name == filename
  end, {
    path = root,
    type = 'file',
    limit = limit or 50,
  })
end

--- 获取 Java buffer 的完全限定名（package.ClassName）
---@param bufnr number
---@return string|nil
local function java_fqn(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  local class_name = vim.fn.fnamemodify(name, ':t:r')
  if class_name == '' then
    return nil
  end

  local max_lines = math.min(vim.api.nvim_buf_line_count(bufnr), 200)
  for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, max_lines, false)) do
    local package_name = line:match('^%s*package%s+([%w_%.]+)%s*;')
    if package_name then
      return package_name .. '.' .. class_name
    end
  end

  return class_name
end

--- 从文件路径获取 Java 完全限定名
---@param path string
---@return string|nil
local function java_fqn_from_file(path)
  local class_name = vim.fn.fnamemodify(path, ':t:r')
  if class_name == '' then
    return nil
  end

  for _, line in ipairs(util.read_file_lines(path)) do
    local package_name = line:match('^%s*package%s+([%w_%.]+)%s*;')
    if package_name then
      return package_name .. '.' .. class_name
    end
  end

  return class_name
end

--- 从 XML 文件中获取 mapper namespace
---@param path string
---@return string|nil
local function mapper_namespace_from_file(path)
  for _, line in ipairs(util.read_file_lines(path)) do
    local namespace = line:match('<mapper.-namespace%s*=%s*"([^"]+)"')
    if namespace then
      return namespace
    end
  end
end

--- 获取当前光标所在 XML 语句的 id
--- 支持 select/insert/update/delete/sql 标签
---@param bufnr number
---@return string|nil
local function xml_statement_id(bufnr)
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local statement_tags = {
    select = true,
    insert = true,
    update = true,
    delete = true,
    sql = true,
  }

  for start_line = cursor_line, 1, -1 do
    local tag_name = lines[start_line]:match('<%s*([%w:_-]+)')
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

--- 获取当前行的 Java 方法名
---@param bufnr number
---@return string|nil
local function java_method_name(bufnr)
  local line = vim.api.nvim_get_current_line()
  local class_name = basename(vim.api.nvim_buf_get_name(bufnr)):gsub('%.java$', '')

  for name in line:gmatch('([%w_]+)%s*%(') do
    if name ~= class_name then
      return name
    end
  end

  local cword = vim.fn.expand('<cword>')
  if cword ~= '' and line:match(vim.pesc(cword) .. '%s*%(') then
    return cword
  end
end

--- 在 Java 文件中查找方法声明行号
---@param path string
---@param method_name string|nil
---@return number line_nr
local function find_java_line(path, method_name)
  if not method_name or method_name == '' then
    return 1
  end

  local pattern = '%f[%w_]' .. vim.pesc(method_name) .. '%s*%('
  for index, line in ipairs(util.read_file_lines(path)) do
    if line:match(pattern) then
      return index
    end
  end

  return 1
end

--- 在 XML 文件中查找 statement id 所在行号
---@param path string
---@param statement_id string|nil
---@return number line_nr
local function find_xml_line(path, statement_id)
  if not statement_id or statement_id == '' then
    return 1
  end

  local escaped = vim.pesc(statement_id)
  for index, line in ipairs(util.read_file_lines(path)) do
    if line:match('id%s*=%s*"' .. escaped .. '"') then
      return index
    end
  end

  return 1
end

--- 获取方法的返回类型
---@param java_path string
---@param method_name string
---@return string|nil
local function get_method_return_type(java_path, method_name)
  local lines = util.read_file_lines(java_path)
  local escaped_name = vim.pesc(method_name)
  local pattern = '([%w_<>%.]+)%s+' .. escaped_name .. '%s*%('
  for _, line in ipairs(lines) do
    -- 移除注解和修饰符
    local clean = line:gsub('@%w+%s*%([^)]*%)', ''):gsub('@%w+', '')
    clean = clean:gsub('%f[%w]public%f[%W]', ''):gsub('%f[%w]default%f[%W]', '')
    clean = vim.trim(clean)
    local ret = clean:match(pattern)
    if ret then
      return ret
    end
  end
  return nil
end

--- 根据方法名推断 XML 标签类型
---@param method_name string
---@return string tag_type "select"|"insert"|"update"|"delete"
local function get_tag_type(method_name)
  local lower = method_name:lower()
  if lower:match('^select') or lower:match('^get') or lower:match('^find') or lower:match('^query') or lower:match('^count') then
    return 'select'
  elseif lower:match('^insert') or lower:match('^add') or lower:match('^create') or lower:match('^save') then
    return 'insert'
  elseif lower:match('^update') or lower:match('^modify') or lower:match('^set') then
    return 'update'
  elseif lower:match('^delete') or lower:match('^remove') then
    return 'delete'
  else
    return 'select'
  end
end

--- 解析参数类型的完全限定名（从 import 和 package 推断）
---@param param table 参数信息
---@param java_path string
---@return string fqn
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
---@param type_name string
---@param file_path string
---@return string fqn
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

-- ============================================================================
-- 公开函数
-- ============================================================================

--- 从 Mapper.java buffer 解析对应的 Mapper.xml 文件路径
--- 优先按 namespace 匹配，fallback 按文件名匹配
---@param bufnr number
---@return string|nil xml_path
function M.resolve_mapper_xml(bufnr)
  local root = project.root(bufnr)
  local java_name = basename(vim.api.nvim_buf_get_name(bufnr))
  local xml_name = java_name:gsub('%.java$', '.xml')
  local namespace = java_fqn(bufnr)
  local all_candidates = find_files_by_name(root, xml_name, 50)

  -- 过滤掉 target/build 目录下的文件
  local candidates = {}
  for _, candidate in ipairs(all_candidates) do
    local normalized = vim.fs.normalize(candidate)
    if not normalized:match('/target/') and not normalized:match('/build/') then
      table.insert(candidates, candidate)
    end
  end

  -- 优先按 namespace 精确匹配
  if namespace then
    for _, candidate in ipairs(candidates) do
      if mapper_namespace_from_file(candidate) == namespace then
        return candidate
      end
    end
  end

  return candidates[1] or all_candidates[1]
end

--- 从 Mapper.xml buffer 解析对应的 Mapper.java 文件路径
--- 优先按 namespace 精确查找，fallback 按文件名匹配
---@param bufnr number
---@return string|nil java_path
function M.resolve_mapper_java(bufnr)
  local root = project.root(bufnr)
  local namespace = mapper_namespace_from_file(vim.api.nvim_buf_get_name(bufnr))

  -- 优先按 namespace 精确查找
  if namespace then
    for _, java_root in ipairs({ 'src/main/java', 'src/test/java' }) do
      local exact = vim.fs.joinpath(root, java_root, namespace:gsub('%.', '/') .. '.java')
      if util.is_file(exact) then
        return exact
      end
    end
  end

  -- fallback: 按文件名搜索
  local java_name = basename(vim.api.nvim_buf_get_name(bufnr)):gsub('%.xml$', '.java')
  local all_candidates = find_files_by_name(root, java_name, 50)

  local candidates = {}
  for _, candidate in ipairs(all_candidates) do
    local normalized = vim.fs.normalize(candidate)
    if not normalized:match('/target/') and not normalized:match('/build/') then
      table.insert(candidates, candidate)
    end
  end

  -- 按 namespace 匹配
  if namespace then
    for _, candidate in ipairs(candidates) do
      if java_fqn_from_file(candidate) == namespace then
        return candidate
      end
    end
  end

  return candidates[1] or all_candidates[1]
end

--- 检查 buffer 是否是 Mapper Java 文件
---@param bufnr number
---@return boolean
function M.is_mapper_java_buffer(bufnr)
  return vim.bo[bufnr].filetype == 'java' and basename(vim.api.nvim_buf_get_name(bufnr)):match('Mapper%.java$') ~= nil
end

--- 检查 buffer 是否是 Mapper XML 文件
---@param bufnr number
---@return boolean
function M.is_mapper_xml_buffer(bufnr)
  local name = basename(vim.api.nvim_buf_get_name(bufnr))
  return vim.bo[bufnr].filetype == 'xml'
    and (name:match('Mapper%.xml$') ~= nil or mapper_namespace_from_file(vim.api.nvim_buf_get_name(bufnr)) ~= nil)
end

--- 检查 buffer 是否是 Mapper 文件（Java 或 XML）
---@param bufnr number|nil
---@return boolean
function M.is_mapper_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return M.is_mapper_java_buffer(bufnr) or M.is_mapper_xml_buffer(bufnr)
end

--- 在 Mapper.java 和 Mapper.xml 之间跳转
--- 如果从 Java 跳转到 XML 时方法在 XML 中不存在，会自动生成 XML 语句块
---@param open_cmd string|nil 打开命令，默认 'edit'，可选 'vsplit' 等
function M.jump_mapper_pair(open_cmd)
  local bufnr = vim.api.nvim_get_current_buf()

  if M.is_mapper_java_buffer(bufnr) then
    local xml_path = M.resolve_mapper_xml(bufnr)
    if not xml_path then
      log.warn('No matching Mapper.xml found.')
      return
    end

    local java_path = vim.api.nvim_buf_get_name(bufnr)
    local method_name = java_method_name(bufnr)
    if method_name then
      -- 检查 statement ID 是否已存在于 Mapper.xml 中
      local exists = false
      if util.is_file(xml_path) then
        local xml_lines = util.read_file_lines(xml_path)
        for _, line in ipairs(xml_lines) do
          if line:match('id%s*=%s*"' .. vim.pesc(method_name) .. '"') or line:match("id%s*=%s*'" .. vim.pesc(method_name) .. "'") then
            exists = true
            break
          end
        end
      end

      if not exists then
        -- 方法在 XML 中不存在，自动生成 XML 语句块
        local params = parameter.parse_method_params(java_path, method_name) or {}

        -- 1. 确定 parameterType
        local param_fqn = nil
        if #params == 1 then
          param_fqn = resolve_param_type_fqn(params[1], java_path)
        end

        -- 2. 确定 resultType
        local result_fqn = nil
        local return_type = get_method_return_type(java_path, method_name)
        if return_type and return_type ~= 'void' and return_type ~= 'int' and return_type ~= 'long' then
          local generic = return_type:match('<%s*([%w_%.]+)%s*>')
          local class_name = generic or return_type
          result_fqn = resolve_type_fqn_in_file(class_name, java_path)
        end

        -- 3. 构建 XML 块
        local tag = get_tag_type(method_name)
        local attrs = { string.format('id="%s"', method_name) }
        if param_fqn then
          table.insert(attrs, string.format('parameterType="%s"', param_fqn))
        end
        if tag == 'select' and result_fqn then
          table.insert(attrs, string.format('resultType="%s"', result_fqn))
        end

        local attr_str = table.concat(attrs, ' ')
        local indent = "  "
        local xml_block = {
          string.format('%s<%s %s>', indent, tag, attr_str),
          string.format('%s  ', indent),
          string.format('%s</%s>', indent, tag),
        }

        -- 4. 在 </mapper> 前插入 XML 块
        local xml_lines = util.read_file_lines(xml_path)
        local insert_index = nil
        for i = #xml_lines, 1, -1 do
          if xml_lines[i]:match('</mapper>') then
            insert_index = i
            break
          end
        end

        if insert_index then
          table.insert(xml_lines, insert_index, "")
          for j, line in ipairs(xml_block) do
            table.insert(xml_lines, insert_index + j, line)
          end
          vim.fn.writefile(xml_lines, xml_path)

          -- 5. 打开 XML 文件并定位到新生成的块
          local target_line = insert_index + 1
          util.open_at(xml_path, target_line, open_cmd)
          vim.api.nvim_win_set_cursor(0, { target_line, #indent + 2 })
          log.info(string.format("Generated and jumped to XML block for '%s' in Mapper.xml", method_name))
          return
        end
      end
    end

    util.open_at(xml_path, find_xml_line(xml_path, method_name), open_cmd)
    return
  end

  if M.is_mapper_xml_buffer(bufnr) then
    local java_path = M.resolve_mapper_java(bufnr)
    if not java_path then
      log.warn('No matching Mapper.java found.')
      return
    end

    util.open_at(java_path, find_java_line(java_path, xml_statement_id(bufnr)), open_cmd)
    return
  end

  log.info('Current buffer is not a Mapper.java or Mapper.xml file.')
end

--- 为 Mapper buffer 设置快捷键
---@param bufnr number
function M.attach_mapper_keymaps(bufnr)
  if not M.is_mapper_buffer(bufnr) then
    return
  end

  local function jump_edit()
    M.jump_mapper_pair('edit')
  end

  local function jump_vsplit()
    M.jump_mapper_pair('vsplit')
  end

  local map_opts = { buffer = bufnr, silent = true }
  vim.keymap.set('n', 'gf', jump_edit, vim.tbl_extend('force', map_opts, { desc = 'Jump mapper pair' }))
  vim.keymap.set('n', 'gF', jump_vsplit, vim.tbl_extend('force', map_opts, { desc = 'Jump mapper pair in split' }))
  vim.keymap.set('n', '<C-]>', jump_edit, vim.tbl_extend('force', map_opts, { desc = 'Jump mapper pair' }))
  vim.keymap.set('n', '<leader>li', jump_edit, vim.tbl_extend('force', map_opts, { desc = 'Mapper: Jump pair' }))
  vim.keymap.set('n', '<leader>lD', jump_vsplit, vim.tbl_extend('force', map_opts, { desc = 'Mapper: Jump pair in split' }))
end

-- ============================================================================
-- 测试接口
-- ============================================================================

M._test = {
  get_tag_type = get_tag_type,
  get_method_return_type = get_method_return_type,
  resolve_mapper_xml = M.resolve_mapper_xml,
  resolve_mapper_java = M.resolve_mapper_java,
  java_fqn = java_fqn,
  java_fqn_from_file = java_fqn_from_file,
  xml_statement_id = xml_statement_id,
  is_mapper_java_buffer = M.is_mapper_java_buffer,
  is_mapper_xml_buffer = M.is_mapper_xml_buffer,
  resolve_param_type_fqn = resolve_param_type_fqn,
  resolve_type_fqn_in_file = resolve_type_fqn_in_file,
  basename = basename,
  find_files_by_name = find_files_by_name,
  java_method_name = java_method_name,
  find_java_line = find_java_line,
  find_xml_line = find_xml_line,
  mapper_namespace_from_file = mapper_namespace_from_file,
}

return M
