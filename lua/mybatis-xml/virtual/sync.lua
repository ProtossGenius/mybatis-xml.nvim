--- mybatis-xml.nvim 虚拟 Java 文件同步模块
--- 提供启动时批量生成和保存时的增量更新

local M = {}
local generator = require('mybatis-xml.virtual.generator')
local project = require('mybatis-xml.project')
local util = require('mybatis-xml.util')
local log = require('mybatis-xml.log')

--- 启动时批量生成项目中所有的虚拟 Java 文件
function M.generate_all()
  local root = project.root()
  if not root then return end

  -- 扫描所有 Mapper.xml 文件
  local xml_files = vim.fs.find(function(name)
    return name:match('Mapper%.xml$') ~= nil or name:match('mapper%.xml$') ~= nil
  end, { path = root, type = 'file', limit = 200 })

  local count = 0
  for _, xml_path in ipairs(xml_files) do
    local lines = util.read_file_lines(xml_path)
    local namespace = nil
    for _, l in ipairs(lines) do
      namespace = l:match('<mapper.-namespace%s*=%s*"([^"]+)"')
      if namespace then break end
    end

    if namespace then
      local java_path = util.find_java_file_by_fqn(namespace, 0)
      if java_path then
        local ok = generator.write_virtual_file(xml_path, 0)
        if ok then count = count + 1 end
      end
    end
  end

  if count > 0 then
    log.info('Generated ' .. count .. ' virtual Java files on startup')
  end
end

--- 注册自动命令
function M.setup()
  local group = vim.api.nvim_create_augroup('MybatisXmlVirtualSync', { clear = true })

  -- 启动或切换目录时批量生成
  vim.api.nvim_create_autocmd({ 'VimEnter', 'DirChanged' }, {
    group = group,
    callback = function()
      vim.defer_fn(function()
        M.generate_all()
      end, 200)
    end,
  })

  -- 保存 Mapper.java 时重新生成虚拟文件
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = group,
    pattern = '*Mapper.java',
    callback = function(args)
      local bufnr = args.buf
      local file_name = vim.api.nvim_buf_get_name(bufnr)
      local java_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local pkg = nil
      for _, l in ipairs(java_lines) do
        pkg = l:match('^%s*package%s+([%w_%.]+)%s*;')
        if pkg then break end
      end
      if pkg then
        local class_name = vim.fn.fnamemodify(file_name, ':t:r')
        local fqn = pkg .. '.' .. class_name
        -- 尝试查找关联的 XML 并写入
        local mapper_pair = require('mybatis-xml.jump.mapper_pair')
        local xml_path = mapper_pair._test.resolve_mapper_xml(bufnr)
        if xml_path then
          generator.write_virtual_file(xml_path, bufnr)
        end
      end
    end,
  })

  -- 保存 Mapper.xml 时，确保虚拟 Java 文件存在
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = group,
    pattern = '*Mapper.xml',
    callback = function(args)
      generator.write_virtual_file(vim.api.nvim_buf_get_name(args.buf), args.buf)
    end,
  })
end

return M
