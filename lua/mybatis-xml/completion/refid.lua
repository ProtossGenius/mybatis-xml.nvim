--- mybatis-xml.nvim SQL refid 补全模块
local M = {}

--- 从当前 buffer 中获取所有 <sql> 的 id，按前缀过滤
---@param bufnr number
---@param base string
---@return table[]
function M.get_refid_matches(bufnr, base)
  local matches = {}
  local base_lower = base:lower()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for _, l in ipairs(lines) do
    local id = l:match('<sql.-id%s*=%s*"([^"]+)"') or l:match("<sql.-id%s*=%s*'([^']+)'")
    if id and id:lower():find(base_lower, 1, true) == 1 then
      table.insert(matches, { word = id, abbr = id, menu = '[SQL]' })
    end
  end
  return matches
end

M._test = { get_refid_matches = M.get_refid_matches }
return M
