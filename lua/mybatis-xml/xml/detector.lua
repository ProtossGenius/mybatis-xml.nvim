-- [[ mybatis-xml.xml.detector ]]
-- MyBatis XML 文件检测

local M = {}

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
    -- DOCTYPE mapper 或 <mapper namespace="..."
    if line:match('<!DOCTYPE%s+mapper') or line:match('<mapper.-namespace') then
      return true
    end
  end
  return false
end

return M
