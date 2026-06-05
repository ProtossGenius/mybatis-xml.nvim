-- [[ mybatis-xml.lsp ]]
-- LSP 交互入口

local M = {}

--- 获取 jdtls 客户端
---@return vim.lsp.Client|nil
function M.get_jdtls_client()
  local config = require('mybatis-xml.config')
  if config.options.jdtls_client_fn then
    return config.options.jdtls_client_fn()
  end

  local clients = vim.lsp.get_clients({ name = 'jdtls' })
  return clients[1] or nil
end

--- 通过 LSP 获取文件的文档符号
---@param file_path string
---@return table[]|nil
function M.get_document_symbols(file_path)
  local client = M.get_jdtls_client()
  if not client then
    return nil
  end

  local uri = vim.uri_from_fname(file_path)
  local response, err = client.request_sync('textDocument/documentSymbol', {
    textDocument = { uri = uri },
  }, 1000)

  if not response or response.err or not response.result then
    return nil
  end

  return response.result
end

return M
