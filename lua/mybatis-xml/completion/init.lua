--- mybatis-xml.nvim 补全引擎入口
--- 编排所有子模块，提供 omnifunc 接口和自动触发

local M = {}
local util = require('mybatis-xml.util')
local log = require('mybatis-xml.log')

--- 模块级变量：存储当前补全上下文类型
M._omnifunc_context = nil

-- ============================================================================
-- 补全上下文检测
-- ============================================================================

--- 分析当前行和光标位置，判断补全上下文类型和起始列
---@param line string
---@param col number 0-indexed
---@return string|nil ctx, number|nil start_col
function M.get_completion_context(line, col)
  local left_str = line:sub(1, col)

  -- 1. 在 #{} 或 ${} 内部
  local param_start = left_str:match('.*[#$]{()([^}]*)$')
  if param_start then
    return 'parameter', param_start - 1
  end

  -- 2. 在属性值内部
  local attr_name, start_col = util.find_attribute_start(line, col)
  if attr_name then
    if util.CLASS_REF_ATTRS[attr_name] then
      return 'class', start_col
    elseif attr_name == 'resultmap' then
      return 'resultmap', start_col
    elseif attr_name == 'refid' then
      return 'refid', start_col
    end
  end

  -- 3. 在 XML 标签内（补全属性名）
  local tag_attribute = require('mybatis-xml.completion.tag_attribute')
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local xml_tag = tag_attribute.find_current_xml_tag(bufnr, cursor_row, col)
  if xml_tag then
    local word_start = left_str:match('.*[%s"\']()([%w_:-]*)$')
    if word_start then
      return 'tag_attribute_' .. xml_tag, word_start - 1
    end
  end

  return nil, nil
end

-- ============================================================================
-- Omnifunc 补全接口
-- ============================================================================

--- Vim omnifunc 补全函数
---@param findstart number
---@param base string
---@return number|table
function M.omnifunc(findstart, base)
  local bufnr = vim.api.nvim_get_current_buf()
  if findstart == 1 then
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1] - 1
    local col = cursor[2]
    local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
    local ctx, start_col = M.get_completion_context(line, col)
    if start_col then
      M._omnifunc_context = ctx
      return start_col
    else
      return -1
    end
  else
    local ctx = M._omnifunc_context
    if not ctx then
      return {}
    end

    local matches = {}
    local base_lower = base:lower()

    if ctx == 'parameter' then
      local parameter = require('mybatis-xml.completion.parameter')
      local items = parameter.build_param_items(bufnr) or {}
      local cursor = vim.api.nvim_win_get_cursor(0)
      local row = cursor[1] - 1
      local col = cursor[2]
      local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
      local next_char = line:sub(col + 1, col + 1)
      local closing = (next_char == '}') and '' or '}'

      for _, item in ipairs(items) do
        if item:lower():find(base_lower, 1, true) == 1 then
          table.insert(matches, { word = item .. closing, abbr = item, menu = '[Param]' })
        end
      end

    elseif ctx == 'class' then
      local class = require('mybatis-xml.completion.class')
      matches = class.get_class_matches(bufnr, base)

    elseif ctx == 'resultmap' then
      local resultmap = require('mybatis-xml.completion.resultmap')
      matches = resultmap.get_resultmap_matches(bufnr, base)

    elseif ctx == 'refid' then
      local refid = require('mybatis-xml.completion.refid')
      matches = refid.get_refid_matches(bufnr, base)

    elseif ctx:match('^tag_attribute_') then
      local tag_name = ctx:gsub('^tag_attribute_', '')
      local ta = require('mybatis-xml.completion.tag_attribute')
      matches = ta.get_tag_attribute_matches(bufnr, tag_name, base)
    end

    return matches
  end
end

-- ============================================================================
-- 触发补全
-- ============================================================================

--- 内部触发补全
function M.trigger_autocomplete_inline(bufnr, ctx, start_col)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''

  local base = line:sub(start_col + 1, col)
  M._omnifunc_context = ctx
  local matches = M.omnifunc(0, base)
  if matches and #matches > 0 then
    vim.fn.complete(start_col + 1, matches)
  end
end

--- 触发参数补全（自动检测上下文）
function M.trigger_param_completion(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
  local ctx, start_col = M.get_completion_context(line, col)
  if ctx and start_col then
    M.trigger_autocomplete_inline(bufnr, ctx, start_col)
  end
end

--- 手动触发补全
function M.manual_trigger(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''

  local left_str = line:sub(1, col)
  local has_brace_left = left_str:match('#{[^}]*$') or left_str:match('%${[^}]*$')
  local ctx, _ = M.get_completion_context(line, col)

  if has_brace_left or ctx then
    M.trigger_param_completion(bufnr)
  else
    log.warn('光标不在补全上下文内部')
  end
end

--- 在 insert 模式下处理 `{` 输入
function M.handle_open_brace(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''

  local char_before = col > 0 and line:sub(col, col) or ''

  if char_before == '#' or char_before == '$' then
    vim.api.nvim_feedkeys('{', 'n', false)
    vim.schedule(function()
      M.trigger_param_completion(bufnr)
    end)
  else
    vim.api.nvim_feedkeys('{', 'n', false)
  end
end

--- 为指定 buffer 设置自动补全
function M.setup_autocomplete(bufnr)
  vim.bo[bufnr].omnifunc = 'v:lua.require("mybatis-xml.completion").omnifunc'

  local group = vim.api.nvim_create_augroup('MyBatisXmlAutocomplete_' .. bufnr, { clear = true })
  vim.api.nvim_create_autocmd({ 'TextChangedI', 'InsertCharPre' }, {
    group = group,
    buffer = bufnr,
    callback = function()
      if vim.fn.pumvisible() ~= 0 then return end
      if vim.api.nvim_get_mode().mode ~= 'i' then return end

      vim.schedule(function()
        if vim.api.nvim_get_mode().mode == 'i' and vim.fn.pumvisible() == 0 then
          local current_cursor = vim.api.nvim_win_get_cursor(0)
          local current_line = vim.api.nvim_buf_get_lines(bufnr, current_cursor[1] - 1, current_cursor[1], false)[1] or ''
          local current_ctx, current_start = M.get_completion_context(current_line, current_cursor[2])
          if current_ctx and current_start then
            M.trigger_autocomplete_inline(bufnr, current_ctx, current_start)
          end
        end
      end)
    end,
  })
end

M._test = {
  get_completion_context = M.get_completion_context,
}

return M
