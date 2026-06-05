--- mybatis-xml.nvim — MyBatis XML IDE 增强插件
--- 提供补全、跳转、诊断、数据库同步、XML 标签编辑等功能

local M = {}

--- 初始化插件
---@param opts table|nil 用户配置选项
function M.setup(opts)
  local config = require('mybatis-xml.config')
  config.setup(opts)
  local log = require('mybatis-xml.log')

  -- 注册 XML buffer 检测和功能激活
  local group = vim.api.nvim_create_augroup('MybatisXmlSetup', { clear = true })

  -- 当打开 XML 文件时，检查是否是 MyBatis mapper
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'xml',
    callback = function(args)
      local bufnr = args.buf
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(bufnr) then return end
        local util = require('mybatis-xml.util')
        if not util.is_mybatis_mapper(bufnr) then return end

        log.debug('MyBatis mapper detected: %s', vim.api.nvim_buf_get_name(bufnr))

        -- 设置补全
        if config.options.auto_complete then
          local completion = require('mybatis-xml.completion')
          completion.setup_autocomplete(bufnr)
        end

        -- 设置跳转快捷键
        local jump = require('mybatis-xml.jump')
        jump.setup_xml_keymaps(bufnr)
      end)
    end,
  })

  -- 当打开 Java 文件时，检查是否是 Mapper 并设置快捷键
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'java',
    callback = function(args)
      local bufnr = args.buf
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(bufnr) then return end
        local file_name = vim.api.nvim_buf_get_name(bufnr)
        if file_name:match('Mapper%.java$') then
          local jump = require('mybatis-xml.jump')
          jump.setup_java_keymaps(bufnr)
        end
      end)
    end,
  })

  -- LuaSnip 代码片段
  if config.options.snippets then
    vim.schedule(function()
      local ok, snippet = pcall(require, 'mybatis-xml.snippet')
      if ok then
        snippet.register_snippets()
      end
    end)
  end

  -- XML 标签配对重命名
  if config.options.tag_sync then
    require('mybatis-xml.xml.tag_sync').setup()
  end

  -- 数据库同步
  if config.options.datasource.enabled then
    require('mybatis-xml.datasource').setup()
  end

  -- 虚拟 Java 文件
  if config.options.virtual_java.enabled then
    require('mybatis-xml.virtual.sync').setup()
  end

  -- 诊断
  require('mybatis-xml.lsp.diagnostics').setup()

  log.debug('mybatis-xml.nvim 初始化完成')
end

return M
