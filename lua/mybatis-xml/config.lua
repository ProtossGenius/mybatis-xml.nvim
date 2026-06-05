--- mybatis-xml.nvim 配置管理模块
--- 提供默认配置和用户配置合并

local M = {}

M.defaults = {
  -- 自动补全
  auto_complete = true,
  -- LuaSnip 代码片段
  snippets = true,
  -- XML 标签配对重命名
  tag_sync = true,
  -- 数据库同步
  datasource = {
    enabled = true,
  },
  -- 虚拟 Java 文件
  virtual_java = {
    enabled = true,
    dir = '.mybatis-xml-nvim',
  },
  -- 日志级别: 'DEBUG', 'INFO', 'WARN', 'ERROR'
  log_level = 'INFO',
  -- 用户自定义 jdtls client 获取函数（可选）
  -- 如果为 nil，则自动通过 vim.lsp.get_clients({name='jdtls'}) 获取
  jdtls_client_fn = nil,
}

--- 当前生效的配置（setup 后填充）
M.options = vim.deepcopy(M.defaults)

--- 合并用户配置
---@param opts table|nil
function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  require('mybatis-xml.log').set_level(M.options.log_level)
end

return M
