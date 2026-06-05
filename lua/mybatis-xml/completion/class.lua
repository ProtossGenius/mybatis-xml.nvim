--- mybatis-xml.nvim 类名 FQN 补全模块
local M = {}
local uv = vim.uv or vim.loop
local project = require('mybatis-xml.project')

local class_cache = {}
local cache_time = 0

--- 获取项目下所有 Java 类的 FQN 列表（带缓存，10 秒过期）
---@param bufnr number|nil
---@return string[]
function M.get_all_project_classes(bufnr)
  local now = uv.now()
  if #class_cache > 0 and (now - cache_time) < 10000 then
    return class_cache
  end

  local root = project.root(bufnr)
  if not root or root == '' then
    return {}
  end

  local java_files = vim.fn.globpath(root, '/**/*.java', false, true)
  local classes = {}
  for _, file_path in ipairs(java_files) do
    local rel = file_path:match('src/[^/]+/java/(.+)%.java$')
    if not rel then
      rel = file_path:match('src/(.+)%.java$')
    end
    if rel then
      local fqn = rel:gsub('/', '.')
      table.insert(classes, fqn)
    end
  end

  class_cache = classes
  cache_time = now
  return classes
end

--- 根据输入前缀过滤类名
---@param bufnr number
---@param base string
---@return table[]
function M.get_class_matches(bufnr, base)
  local matches = {}
  local base_lower = base:lower()
  local classes = M.get_all_project_classes(bufnr)
  for _, class in ipairs(classes) do
    if class:lower():find(base_lower, 1, true) then
      table.insert(matches, {
        word = class,
        abbr = class:match('[^%.]+$') or class,
        menu = '[Class]',
        info = class,
      })
    end
  end
  return matches
end

M._test = {
  get_all_project_classes = M.get_all_project_classes,
}

return M
