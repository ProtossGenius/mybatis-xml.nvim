--- mybatis-xml.nvim 虚拟 Java 文件生成器
--- 根据 Mapper.java 接口，生成继承该接口的抽象虚拟类 UserMapperVirtual.java
--- 用于支持 jdtls 完成属性补全

local M = {}
local util = require('mybatis-xml.util')
local project = require('mybatis-xml.project')
local log = require('mybatis-xml.log')

--- 获取虚拟 Java 文件的路径
---@param xml_path string
---@param bufnr number|nil
---@return string|nil
function M.get_virtual_path(xml_path, bufnr)
  local namespace = util.get_namespace(bufnr or 0)
  if not namespace then return nil end
  local java_path = util.find_java_file_by_fqn(namespace, bufnr or 0)
  if not java_path then return nil end

  local dir = vim.fn.fnamemodify(java_path, ':h')
  local name = vim.fn.fnamemodify(java_path, ':t:r')
  return vim.fs.joinpath(dir, '_mybatis_virtual', name .. 'Virtual.java')
end

local function get_default_return_value(type_name)
  if not type_name or type_name == 'void' then
    return ''
  elseif type_name == 'boolean' then
    return 'return false;'
  elseif type_name == 'int' or type_name == 'long' or type_name == 'double' or type_name == 'float' or type_name == 'short' or type_name == 'byte' or type_name == 'char' then
    return 'return 0;'
  else
    return 'return null;'
  end
end

--- 生成虚拟 Java 文件的内容（行列表）
---@param xml_path string
---@param bufnr number|nil
---@return string[]|nil
function M.generate_virtual_content(xml_path, bufnr)
  local namespace = util.get_namespace(bufnr or 0)
  if not namespace then return nil end
  local java_path = util.find_java_file_by_fqn(namespace, bufnr or 0)
  if not java_path then return nil end

  local lines = util.read_file_lines(java_path)
  if #lines == 0 then return nil end

  local full_text = table.concat(lines, '\n')

  -- 1. 提取包名并构造虚拟包名
  local pkg_name = namespace:match('^(.-)%.[^%.]+$')
  if not pkg_name then return nil end
  local virtual_pkg = pkg_name .. '._mybatis_virtual'

  -- 2. 提取 imports
  local imports = {}
  for import_line in full_text:gmatch('import%s+[%w_%.%*]+%s*;') do
    table.insert(imports, import_line)
  end
  -- 导入被继承的 interface 接口
  table.insert(imports, 'import ' .. namespace .. ';')
  -- 导入 Param 注解以防万一
  if not full_text:match('org%.apache%.ibatis%.annotations%.Param') then
    table.insert(imports, 'import org.apache.ibatis.annotations.Param;')
  end

  -- 3. 提取接口方法定义
  local methods = {}
  -- 搜索所有 ReturnType methodName(Params); 的模式
  for raw_ret, method_name, params_str in full_text:gmatch('([%w_%.<>%[%] ]+)%s+([%w_]+)%s*(%b())%s*;') do
    params_str = params_str:sub(2, -2)
    local ret = vim.trim(raw_ret)
    -- 移除修饰符
    ret = ret:gsub('^public%s+', ''):gsub('^protected%s+', ''):gsub('^private%s+', ''):gsub('^abstract%s+', '')
    ret = vim.trim(ret)

    -- 过滤关键字行
    if ret ~= 'package' and ret ~= 'import' and ret ~= 'class' and ret ~= 'interface' and ret ~= 'default' then
      local params = {}
      -- 移除泛型以简化参数分割
      local simplified = params_str:gsub('<[^>]*>', '')
      for part in simplified:gmatch('[^,]+') do
        part = vim.trim(part)
        if part ~= '' then
          local param_annotation = part:match('@Param%s*%(%s*"([^"]+)"%s*%)')
          local no_annotations = part:gsub('@%w+%s*%([^)]*%)', ''):gsub('@%w+', '')
          no_annotations = vim.trim(no_annotations)
          local type_name, param_name = no_annotations:match('^(.-)%s+([%w_]+)$')
          if type_name and param_name then
            type_name = type_name:gsub('^final%s+', ''):gsub('%.%.%.', '')
            type_name = vim.trim(type_name)
            table.insert(params, {
              name = param_name,
              type = type_name,
              annotation = param_annotation,
            })
          end
        end
      end

      table.insert(methods, {
        name = method_name,
        return_type = ret,
        params = params,
      })
    end
  end

  -- 4. 组装虚拟类行
  local res = {
    'package ' .. virtual_pkg .. ';',
    '',
  }
  for _, imp in ipairs(imports) do
    table.insert(res, imp)
  end
  table.insert(res, '')

  local interface_name = namespace:match('[^%.]+$')
  table.insert(res, 'public abstract class ' .. interface_name .. 'Virtual implements ' .. interface_name .. ' {')

  for _, m in ipairs(methods) do
    table.insert(res, '    @Override')
    
    local param_list = {}
    for _, p in ipairs(m.params) do
      local ann = p.annotation and ('@Param("' .. p.annotation .. '") ') or ''
      table.insert(param_list, ann .. p.type .. ' ' .. p.name)
    end
    local param_str = table.concat(param_list, ', ')

    table.insert(res, '    public ' .. m.return_type .. ' ' .. m.name .. '(' .. param_str .. ') {')
    
    -- 生成变量绑定来触发补全和类型推导
    for _, p in ipairs(m.params) do
      table.insert(res, '        Object _val_' .. p.name .. ' = ' .. p.name .. ';')
    end

    local ret_val = get_default_return_value(m.return_type)
    if ret_val ~= '' then
      table.insert(res, '        ' .. ret_val)
    end
    table.insert(res, '    }')
    table.insert(res, '')
  end

  table.insert(res, '}')

  return res
end

--- 写入虚拟 Java 文件到磁盘
---@param xml_path string
---@param bufnr number|nil
---@return boolean
function M.write_virtual_file(xml_path, bufnr)
  local path = M.get_virtual_path(xml_path, bufnr)
  if not path then return false end

  local content = M.generate_virtual_content(xml_path, bufnr)
  if not content then return false end

  local dir = vim.fn.fnamemodify(path, ':h')
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, 'p')
  end

  vim.fn.writefile(content, path)
  M.ensure_gitignore(xml_path, bufnr)
  return true
end

--- 自动将虚拟包目录加入到 .gitignore 中
---@param xml_path string
---@param bufnr number|nil
function M.ensure_gitignore(xml_path, bufnr)
  local root = project.root(bufnr or 0)
  if not root then return end

  local gitignore_path = vim.fs.joinpath(root, '.gitignore')
  local line_to_add = '**/_mybatis_virtual/'

  local lines = {}
  if util.is_file(gitignore_path) then
    lines = util.read_file_lines(gitignore_path)
    for _, line in ipairs(lines) do
      if line:match('^_mybatis_virtual/') or line:match('%*_mybatis_virtual') or line:match('**/_mybatis_virtual/') then
        return
      end
    end
  end

  table.insert(lines, '')
  table.insert(lines, '# mybatis-xml.nvim virtual java files')
  table.insert(lines, line_to_add)
  vim.fn.writefile(lines, gitignore_path)
  log.info('Added ' .. line_to_add .. ' to .gitignore')
end

return M
