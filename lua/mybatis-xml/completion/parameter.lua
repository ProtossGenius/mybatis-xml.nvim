--- mybatis-xml.nvim 参数补全模块
--- 处理 #{} / ${} 占位符内的参数补全逻辑

local M = {}
local util = require('mybatis-xml.util')
local log = require('mybatis-xml.log')

-- ============================================================================
-- 语句块定位
-- ============================================================================

--- 向上搜索当前光标所在的 SQL 语句块，获取 statement id
---@param bufnr number
---@return string|nil statement_id
function M.find_current_statement_id(bufnr)
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local statement_tags = {
    select = true, insert = true, update = true, delete = true,
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

-- ============================================================================
-- Java 方法参数解析
-- ============================================================================

--- 从 mapper.java 中找到对应方法的参数列表
---@param java_path string
---@param method_name string
---@return table[]|nil
function M.parse_method_params(java_path, method_name)
  local lines = util.read_file_lines(java_path)
  if #lines == 0 then
    return nil
  end

  local escaped_name = vim.pesc(method_name)
  local full_text = table.concat(lines, '\n')

  local pattern = '%f[%w_]' .. escaped_name .. '%s*%(([%s%S]-)%)%s*;'
  local params_str = full_text:match(pattern)
  if not params_str then
    return nil
  end

  local params = {}
  local simplified = params_str:gsub('<[^>]*>', '')
  for part in simplified:gmatch('[^,]+') do
    part = vim.trim(part)
    if part ~= '' then
      local param_annotation = part:match('@Param%s*%(%s*"([^"]+)"%s*%)')
      local no_annotations = part:gsub('@%w+%s*%([^)]*%)', ''):gsub('@%w+', '')
      no_annotations = vim.trim(no_annotations)
      local type_name, param_name = no_annotations:match('^(.-)%s+([%w_]+)$')
      if type_name and param_name then
        type_name = type_name:gsub('^final%s+', '')
        type_name = type_name:gsub('%.%.%.', '')
        type_name = vim.trim(type_name)
        local simple_type = type_name:match('[^%.]+$') or type_name
        table.insert(params, {
          name = param_name,
          type = simple_type,
          full_type = type_name,
          param_annotation = param_annotation,
        })
      end
    end
  end

  return params
end

-- ============================================================================
-- Model 字段提取
-- ============================================================================

--- 从 Model 类文件中提取字段名列表
---@param model_path string
---@return string[]
function M.extract_model_fields(model_path)
  local lines = util.read_file_lines(model_path)
  local fields = {}
  local in_class = false

  for _, line in ipairs(lines) do
    if line:match('class%s+') then
      in_class = true
    end

    if in_class then
      local trimmed = vim.trim(line)
      if not trimmed:match('^@') and not trimmed:match('^//') and not trimmed:match('^/%*') and not trimmed:match('^%*') then
        local field = trimmed:match('^%s*[%w%s<>,%.%[%]]*%s+([%w_]+)%s*[;=]')
        if field then
          if not trimmed:match('%(') and not trimmed:match('^class%s')
            and not trimmed:match('^interface%s') and not trimmed:match('^enum%s')
            and not trimmed:match('^return%s') and not trimmed:match('^import%s')
            and not trimmed:match('^package%s')
            and field ~= 'serialVersionUID' then
            table.insert(fields, field)
          end
        end
      end
    end
  end

  local seen = {}
  local unique = {}
  for _, f in ipairs(fields) do
    if not seen[f] then
      seen[f] = true
      table.insert(unique, f)
    end
  end

  return unique
end

--- 通过 LSP documentSymbol 获取字段名
---@param file_path string
---@return table[]|nil
function M.get_lsp_symbols(file_path)
  local lsp = require('mybatis-xml.lsp')
  local client = lsp.get_jdtls_client()
  if not client then
    return nil
  end
  local uri = vim.uri_from_fname(file_path)
  local response, _ = client.request_sync('textDocument/documentSymbol', {
    textDocument = { uri = uri },
  }, 1000)
  if not response or response.err or not response.result then
    return nil
  end
  return response.result
end

--- 从 documentSymbol 结果中提取字段名
---@param symbols table[]
---@return string[]
function M.extract_fields_from_symbols(symbols)
  local fields = {}
  local function traverse(syms)
    for _, sym in ipairs(syms) do
      if sym.kind == 8 or sym.kind == 7 then -- Field or Property
        table.insert(fields, sym.name)
      end
      if sym.children and #sym.children > 0 then
        traverse(sym.children)
      end
    end
  end
  traverse(symbols)
  return fields
end

--- 从 Model 类文件中提取字段名列表（优先使用 LSP）
---@param model_path string
---@return string[]
function M.extract_model_fields_with_lsp(model_path)
  local symbols = M.get_lsp_symbols(model_path)
  if symbols and #symbols > 0 then
    local fields = M.extract_fields_from_symbols(symbols)
    if #fields > 0 then
      local filtered = {}
      for _, f in ipairs(fields) do
        if f ~= 'serialVersionUID' then
          table.insert(filtered, f)
        end
      end
      return filtered
    end
  end
  return M.extract_model_fields(model_path)
end

--- 在行内向前搜索 #{ 或 ${ 的位置
---@param line string
---@param cursor_col number
---@return number|nil
function M.find_completion_start_col(line, cursor_col)
  for c = cursor_col, 1, -1 do
    local char = line:sub(c, c)
    local prev_char = c > 1 and line:sub(c - 1, c - 1) or ''
    if char == '{' and (prev_char == '#' or prev_char == '$') then
      return c
    end
  end
  return nil
end

-- ============================================================================
-- 构建补全项
-- ============================================================================

--- 构建参数补全列表
---@param bufnr number
---@return string[]|nil items
function M.build_param_items(bufnr)
  local statement_id = M.find_current_statement_id(bufnr)
  if not statement_id then
    log.warn('未找到当前 SQL 语句块')
    return nil
  end

  local namespace = util.get_namespace(bufnr)
  if not namespace then
    log.warn('未找到 mapper namespace')
    return nil
  end

  local java_path = util.find_java_file_by_fqn(namespace, bufnr)
  if not java_path then
    log.warn('找不到 Mapper.java: %s', namespace)
    return nil
  end

  local params = M.parse_method_params(java_path, statement_id)
  if not params or #params == 0 then
    log.info('方法 %s 未找到参数', statement_id)
    return nil
  end

  local items = {}
  local single_param = (#params == 1)

  for _, param in ipairs(params) do
    local display_name = param.param_annotation or param.name

    if util.is_model_type(param.type) then
      local model_path = util.find_java_file_by_fqn(param.full_type, bufnr)
      if not model_path and param.type ~= param.full_type then
        model_path = util.find_java_file_by_fqn(param.type, bufnr)
      end

      if not model_path then
        local java_lines = util.read_file_lines(java_path)
        local simple_type = param.type:match('[^%.]+$') or param.type
        for _, jl in ipairs(java_lines) do
          local import_fqn = jl:match('^%s*import%s+([%w_%.]+)%s*;')
          if import_fqn then
            local import_simple = import_fqn:match('[^%.]+$')
            if import_simple == simple_type then
              model_path = util.find_java_file_by_fqn(import_fqn, bufnr)
              break
            end
          end
        end
      end

      if model_path then
        local fields = M.extract_model_fields_with_lsp(model_path)
        if #fields > 0 then
          for _, field in ipairs(fields) do
            if single_param then
              table.insert(items, field)
              table.insert(items, display_name .. '.' .. field)
            else
              table.insert(items, display_name .. '.' .. field)
            end
          end
        else
          table.insert(items, display_name)
        end
      else
        table.insert(items, display_name)
      end
    else
      table.insert(items, display_name)
    end
  end

  return items
end

M._test = {
  find_current_statement_id = M.find_current_statement_id,
  parse_method_params = M.parse_method_params,
  extract_model_fields = M.extract_model_fields,
  get_lsp_symbols = M.get_lsp_symbols,
  extract_fields_from_symbols = M.extract_fields_from_symbols,
  extract_model_fields_with_lsp = M.extract_model_fields_with_lsp,
  find_completion_start_col = M.find_completion_start_col,
  build_param_items = M.build_param_items,
}

return M
