--- mybatis-xml.nvim 项目根目录检测
--- 简化版：不依赖 user.project，独立检测 Java 项目根目录
local M = {}

local uv = vim.uv or vim.loop

--- Java 项目标记文件
local JAVA_MARKERS = {
  'pom.xml',
  'mvnw',
  'build.gradle',
  'build.gradle.kts',
  'settings.gradle',
  'settings.gradle.kts',
  'gradlew',
}

--- 通用项目标记文件（fallback）
local GENERIC_MARKERS = {
  '.git',
  '.hg',
  '.svn',
}

local function is_file(path)
  local stat = path and path ~= '' and uv.fs_stat(path) or nil
  return stat and stat.type == 'file' or false
end

--- 检测路径对应的项目根目录
--- 优先查找 Java 项目标记（pom.xml, build.gradle 等），
--- 如果找不到则 fallback 到 .git 等通用标记
---@param path_or_bufnr string|number|nil
---@return string 项目根目录
function M.root(path_or_bufnr)
  local path
  if type(path_or_bufnr) == 'string' then
    path = path_or_bufnr
  elseif type(path_or_bufnr) == 'number' then
    path = vim.api.nvim_buf_get_name(path_or_bufnr)
  else
    path = vim.api.nvim_buf_get_name(0)
  end

  if not path or path == '' then
    path = vim.fn.getcwd()
  end

  path = vim.fs.normalize(path)

  -- 优先使用 initial_cwd（如果是 Java 项目）
  local initial_cwd = _G.initial_cwd or vim.fn.getcwd()
  initial_cwd = vim.fs.normalize(initial_cwd)

  local initial_cwd_is_java = false
  for _, marker in ipairs(JAVA_MARKERS) do
    if vim.fn.filereadable(vim.fs.joinpath(initial_cwd, marker)) == 1 then
      initial_cwd_is_java = true
      break
    end
  end

  if initial_cwd_is_java then
    local is_inside = path:sub(1, #initial_cwd) == initial_cwd
    local is_temp = path:match('^/tmp/') or path:match('^/private/var/') or path:match('^/var/')
    if is_inside or is_temp then
      return initial_cwd
    end
  end

  -- 查找 Java 项目标记
  local java_root = vim.fs.root(path, JAVA_MARKERS)
  if java_root then
    return java_root
  end

  -- fallback: 查找通用项目标记
  local generic_root = vim.fs.root(path, GENERIC_MARKERS)
  if generic_root then
    return generic_root
  end

  -- 最终 fallback: 当前工作目录
  return vim.fn.getcwd()
end

--- 在项目中按文件名精确查找文件
---@param filename string 文件名（basename）
---@param opts table|nil { root = string }
---@return string|nil path, string|nil error
function M.find_exact_file(filename, opts)
  opts = opts or {}
  local root = opts.root or M.root()
  local matches = vim.fs.find(function(name)
    return name == filename
  end, {
    path = root,
    type = 'file',
    limit = 10,
  })

  if #matches == 0 then
    return nil, 'not found'
  end
  if #matches == 1 then
    return matches[1], nil
  end
  return nil, 'multiple matches found'
end

return M
