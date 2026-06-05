--- mybatis-xml.nvim 标签属性名补全模块
local M = {}
local util = require('mybatis-xml.util')

--- 从当前 buffer 向上搜索，查找光标所在的 XML 标签名
---@param bufnr number
---@param cursor_row number 0-indexed
---@param cursor_col number 0-indexed
---@return string|nil tag_name 小写标签名
function M.find_current_xml_tag(bufnr, cursor_row, cursor_col)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, cursor_row + 1, false)
  local start_row = math.max(0, cursor_row - 10)
  local combined = {}
  for i = start_row, cursor_row - 1 do
    table.insert(combined, lines[i + 1])
  end
  local cursor_line = lines[cursor_row + 1] or ''
  table.insert(combined, cursor_line:sub(1, cursor_col))

  local full_text = table.concat(combined, '\n')
  local _, tag_name = full_text:match('.*<()([^>%s/]+)[^>]*$')
  if _ and tag_name then
    return tag_name:lower()
  end
  return nil
end

--- 从标签文本中提取已定义的属性名集合
---@param tag_text string
---@return table<string, boolean>
function M.get_defined_attributes(tag_text)
  local attrs = {}
  for attr in tag_text:gmatch('([%w_:-]+)%s*=') do
    attrs[attr:lower()] = true
  end
  return attrs
end

--- 获取标签属性名补全列表
---@param bufnr number
---@param tag_name string
---@param base string
---@return table[]
function M.get_tag_attribute_matches(bufnr, tag_name, base)
  local matches = {}
  local base_lower = base:lower()
  local attrs_candidates = util.TAG_ATTRIBUTES[tag_name] or {}

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, row + 1, false)
  local start_row = math.max(0, row - 10)
  local combined = {}
  for i = start_row, row - 1 do
    table.insert(combined, lines[i + 1])
  end
  local cursor_line = lines[row + 1] or ''
  table.insert(combined, cursor_line:sub(1, col))
  local full_text = table.concat(combined, '\n')

  local tag_start = full_text:match('.*<[>%s/]*' .. vim.pesc(tag_name) .. '()')
  local tag_text = tag_start and full_text:sub(tag_start) or ""
  local defined = M.get_defined_attributes(tag_text)

  for _, attr in ipairs(attrs_candidates) do
    if not defined[attr:lower()] then
      if attr:lower():find(base_lower, 1, true) == 1 then
        table.insert(matches, { word = attr .. '=""', abbr = attr, menu = '[Attr]' })
      end
    end
  end

  return matches
end

M._test = {
  find_current_xml_tag = M.find_current_xml_tag,
  get_defined_attributes = M.get_defined_attributes,
  get_tag_attribute_matches = M.get_tag_attribute_matches,
}

return M
