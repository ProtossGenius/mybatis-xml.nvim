-- [[ mybatis-xml.lsp.diagnostics ]]
-- MyBatis 诊断：检测 default 方法与 XML statement 冲突

local M = {}
local util = require('mybatis-xml.util')
local log = require('mybatis-xml.log')

local diagnostic_ns = vim.api.nvim_create_namespace('MyBatisMapperDiagnostics')

--- 从 XML 文件中提取所有 statement id
---@param xml_path string
---@return table<string, boolean>
local function get_xml_ids(xml_path)
  local ids = {}
  local lines = util.read_file_lines(xml_path)
  for _, line in ipairs(lines) do
    local id = line:match('id%s*=%s*"([^"]+)"') or line:match("id%s*=%s*'([^']+)'")
    if id then
      ids[id] = true
    end
  end
  return ids
end

--- 检查 Mapper.java 中的 default 方法是否与 XML statement 冲突
---@param bufnr number
function M.check_default_methods(bufnr)
  if not bufnr or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local file_path = vim.api.nvim_buf_get_name(bufnr)
  if not file_path or file_path == '' or not file_path:match('Mapper%.java$') then
    return
  end

  local mapper_pair = require('mybatis-xml.jump.mapper_pair')
  local xml_path = mapper_pair.resolve_mapper_xml(bufnr)
  if not xml_path or not util.is_file(xml_path) then
    vim.diagnostic.set(diagnostic_ns, bufnr, {})
    return
  end

  local xml_ids = get_xml_ids(xml_path)
  local java_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local diagnostics = {}

  for i, line in ipairs(java_lines) do
    local method_name = line:match('%f[%w]default%f[%W]%s+.-%s+([%w_]+)%s*%(')
    if method_name and xml_ids[method_name] then
      table.insert(diagnostics, {
        lnum = i - 1,
        col = 0,
        end_lnum = i - 1,
        end_col = #line,
        severity = vim.diagnostic.severity.ERROR,
        message = string.format("Default method '%s' should not have a corresponding SQL/statement block in XML.", method_name),
        source = 'mybatis-xml',
      })
    end
  end

  vim.diagnostic.set(diagnostic_ns, bufnr, diagnostics)
end

--- 设置诊断自动命令
function M.setup()
  local group = vim.api.nvim_create_augroup('MybatisXmlDiagnostics', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'TextChanged', 'TextChangedI' }, {
    group = group,
    pattern = { '*Mapper.java' },
    callback = function(args)
      local bufnr = args.buf
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
          M.check_default_methods(bufnr)
        end
      end)
    end,
  })
end

M._test = {
  get_xml_ids = get_xml_ids,
  check_default_methods = M.check_default_methods,
  diagnostic_ns = diagnostic_ns,
}

return M
