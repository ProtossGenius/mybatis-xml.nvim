--- mybatis-xml.nvim 数据库同步模块 — 表结构获取
local M = {}
local util = require('mybatis-xml.util')

--- 获取插件根目录下的脚本路径
local function get_script_path()
  local info = debug.getinfo(1, 'S')
  local source = info.source:sub(2) -- 去掉 @
  local plugin_root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source))))
  return vim.fs.joinpath(plugin_root, 'scripts', 'fetch_table_schema.py')
end

--- 异步调用 Python 脚本获取表结构
---@param config table
---@param table_name string
---@param callback fun(columns: table[]|nil, err: string|nil)
function M.fetch_table_columns(config, table_name, callback)
  local script = get_script_path()
  if not util.is_file(script) then
    callback(nil, 'Python 脚本不存在: ' .. script)
    return
  end

  local cmd = {
    'python3', script,
    '--host', config.host or 'localhost',
    '--port', tostring(config.port or 3306),
    '--user', config.user or 'root',
    '--password', config.password or '',
    '--database', config.database or '',
    '--table', table_name,
  }
  if config.skip_ssl then
    table.insert(cmd, '--skip-ssl')
  end

  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        local output = (result.stdout or '') .. (result.stderr or '')
        local ok, data = pcall(vim.json.decode, output)
        if ok and data and data.error then
          callback(nil, data.error)
        else
          callback(nil, '脚本执行失败 (code=' .. tostring(result.code) .. '): ' .. output)
        end
        return
      end

      local ok, data = pcall(vim.json.decode, result.stdout or '')
      if not ok or type(data) ~= 'table' then
        callback(nil, 'JSON 解析失败: ' .. (result.stdout or ''))
        return
      end

      if data.error then
        callback(nil, data.error)
        return
      end

      callback(data.columns or {}, nil)
    end)
  end)
end

return M
