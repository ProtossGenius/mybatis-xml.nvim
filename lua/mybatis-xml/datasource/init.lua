--- mybatis-xml.nvim 数据库同步模块 — 主流程
local M = {}
local project = require('mybatis-xml.project')
local util = require('mybatis-xml.util')
local log = require('mybatis-xml.log')
local parser = require('mybatis-xml.datasource.parser')
local schema = require('mybatis-xml.datasource.schema')
local diff_mod = require('mybatis-xml.datasource.diff')
local fix = require('mybatis-xml.datasource.fix')

local CONFIG_FILENAME = '.nvim-datasource.json'

--- 从项目根目录读取配置文件
function M.load_config()
  local root = project.root()
  local config_path = vim.fs.joinpath(root, CONFIG_FILENAME)
  if not util.is_file(config_path) then
    log.warn('找不到配置文件: %s', CONFIG_FILENAME)
    return nil
  end
  local text = table.concat(util.read_file_lines(config_path), '\n')
  local ok, config = pcall(vim.json.decode, text)
  if not ok or type(config) ~= 'table' then
    log.error('配置文件解析失败: %s', CONFIG_FILENAME)
    return nil
  end
  return config
end

--- 主流程：扫描所有 mapper.xml，逐一比对并提供修复
function M.sync_project()
  local config = M.load_config()
  if not config then return end

  local annotation_config = config.table_annotation
  if not annotation_config or not annotation_config.class then
    log.warn('配置缺少 table_annotation')
    return
  end

  local root = project.root()

  local xml_files = vim.fs.find(function(name)
    return name:match('Mapper%.xml$') ~= nil or name:match('mapper%.xml$') ~= nil
  end, { path = root, type = 'file', limit = 200 })

  if #xml_files == 0 then
    log.info('项目中未找到 mapper.xml')
    return
  end

  local tasks = {}
  for _, xml_path in ipairs(xml_files) do
    local entries, metas = parser.parse_resultmap(xml_path)

    for _, meta in ipairs(metas) do
      if meta.type then
        local model_fqn = meta.type
        local model_simple_name = model_fqn:match('([^%.]+)$')
        local model_file = project.find_exact_file(model_simple_name .. '.java', { root = root })

        local xml_content = table.concat(util.read_file_lines(xml_path), '\n')
        local namespace = xml_content:match('<mapper.-namespace%s*=%s*"([^"]+)"')
        local mapper_java_path
        if namespace then
          local mapper_simple_name = namespace:match('([^%.]+)$')
          if mapper_simple_name then
            mapper_java_path = project.find_exact_file(mapper_simple_name .. '.java', { root = root })
          end
        end

        local table_name
        if model_file then
          table_name = parser.find_table_name(model_file, annotation_config)
        end
        if not table_name and mapper_java_path then
          table_name = parser.find_table_name(mapper_java_path, annotation_config)
        end

        if table_name and model_file then
          table.insert(tasks, {
            xml_path = xml_path,
            model_path = model_file,
            mapper_java_path = mapper_java_path,
            table_name = table_name,
            resultmap_entries = entries,
          })
        end
      end
    end
  end

  if #tasks == 0 then
    log.info('未找到可同步的 mapper')
    return
  end

  local function process_task(index)
    if index > #tasks then
      log.info('同步完成')
      return
    end

    local task = tasks[index]
    schema.fetch_table_columns(config, task.table_name, function(columns, err)
      if err then
        log.error('获取表 %s 失败: %s', task.table_name, err)
        process_task(index + 1)
        return
      end

      if not columns or #columns == 0 then
        log.warn('表 %s 没有列信息', task.table_name)
        process_task(index + 1)
        return
      end

      local model_fields, has_data = parser.parse_model_fields(task.model_path)
      local diff = diff_mod.compute_diff(columns, task.resultmap_entries, model_fields)

      if diff_mod.is_diff_empty(diff) then
        process_task(index + 1)
        return
      end

      fix.show_diff_window(diff, {
        table_name = task.table_name,
        mapper_xml = vim.fn.fnamemodify(task.xml_path, ':~:.'),
        model_java = vim.fn.fnamemodify(task.model_path, ':~:.'),
      }, function()
        fix.apply_fix(diff, task.xml_path, task.model_path, has_data)

        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_valid(bufnr) then
            local buf_name = vim.api.nvim_buf_get_name(bufnr)
            if buf_name == task.xml_path or buf_name == task.model_path then
              vim.api.nvim_buf_call(bufnr, function()
                vim.cmd('silent! checktime')
                vim.cmd('silent! edit')
              end)
            end
          end
        end

        vim.defer_fn(function() process_task(index + 1) end, 300)
      end)
    end)
  end

  if #tasks == 1 then
    process_task(1)
  else
    local items = { '全部同步 (' .. #tasks .. ' 个表)' }
    for _, task in ipairs(tasks) do
      table.insert(items, task.table_name .. ' ← ' .. vim.fn.fnamemodify(task.xml_path, ':t'))
    end

    vim.ui.select(items, { prompt = 'Datasource Sync' }, function(_, idx)
      if not idx then return end
      if idx == 1 then
        process_task(1)
      else
        process_task(idx - 1)
      end
    end)
  end
end

local CONFIG_TEMPLATE = vim.json.encode({
  host = 'localhost', port = 3306, user = 'root', password = '',
  database = 'mydb', skip_ssl = true,
  table_annotation = { class = 'Table', field = 'table' },
})

--- 注册命令和自动命令
function M.setup()
  vim.api.nvim_create_user_command('DatasourceSync', function()
    M.sync_project()
  end, { desc = '同步数据库表结构到 MyBatis resultMap 和 Java Model' })

  vim.api.nvim_create_user_command('DatasourceConfig', function()
    local root = project.root()
    local config_path = vim.fs.joinpath(root, CONFIG_FILENAME)
    if not util.is_file(config_path) then
      local formatted = vim.fn.system({ 'python3', '-m', 'json.tool' }, CONFIG_TEMPLATE)
      if vim.v.shell_error ~= 0 then formatted = CONFIG_TEMPLATE end
      vim.fn.writefile(vim.split(formatted, '\n', { plain = true }), config_path)
      log.info('已创建配置文件模板: %s', config_path)
    end
    vim.cmd('edit ' .. vim.fn.fnameescape(config_path))
  end, { desc = '打开数据源配置文件' })

  local group = vim.api.nvim_create_augroup('MybatisXmlDatasourceSync', { clear = true })
  vim.api.nvim_create_autocmd('LspAttach', {
    group = group,
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if not client or client.name ~= 'jdtls' then return end
      vim.defer_fn(function()
        local root = project.root()
        local config_path = vim.fs.joinpath(root, CONFIG_FILENAME)
        if util.is_file(config_path) then
          M.sync_project()
        end
      end, 5000)
    end,
  })
end

return M
