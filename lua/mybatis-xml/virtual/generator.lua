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

local function parse_method_with_lsp_range(java_lines, start_line_0_indexed)
  local current_decl = {}
  local has_body = false
  local ended = false
  for i = start_line_0_indexed + 1, #java_lines do
    local line = java_lines[i]
    local clean = line:gsub('//.*$', ''):gsub('/%*.-%*/', '')
    local brace_idx = clean:find('{')
    local semi_idx = clean:find(';')
    
    if brace_idx and (not semi_idx or brace_idx < semi_idx) then
      has_body = true
      table.insert(current_decl, clean:sub(1, brace_idx - 1))
      ended = true
      break
    elseif semi_idx then
      table.insert(current_decl, clean:sub(1, semi_idx - 1))
      ended = true
      break
    else
      table.insert(current_decl, clean)
    end
  end
  
  if not ended then return nil, false end
  return table.concat(current_decl, ' '), has_body
end

local function get_methods_with_lsp(java_path, java_lines)
  local completion_param = require('mybatis-xml.completion.parameter')
  local symbols = completion_param.get_lsp_symbols(java_path)
  if not symbols or #symbols == 0 then
    return nil
  end

  local methods = {}
  local function traverse(syms)
    for _, sym in ipairs(syms) do
      if sym.kind == 6 then -- Method
        local decl, has_body = parse_method_with_lsp_range(java_lines, sym.range.start.line)
        if decl and not has_body then
          local params_block = decl:match('%b()')
          if params_block then
            local before_params = vim.trim(decl:sub(1, decl:find('%b()') - 1))
            local before_params_no_ann = before_params:gsub('@[%w_%.]+%s*%b()', ''):gsub('@[%w_%.]+', '')
            before_params_no_ann = vim.trim(before_params_no_ann)
            local method_name = before_params_no_ann:match('([%w_]+)$')
            if method_name then
              local return_type = vim.trim(before_params_no_ann:sub(1, before_params_no_ann:find(method_name, 1, true) - 1))
              return_type = return_type:gsub('^public%s+', '')
                                     :gsub('^protected%s+', '')
                                     :gsub('^private%s+', '')
                                     :gsub('^abstract%s+', '')
                                     :gsub('^static%s+', '')
                                     :gsub('^final%s+', '')
              return_type = vim.trim(return_type)
              
              if return_type ~= '' and return_type ~= 'package' and return_type ~= 'import' and return_type ~= 'class' and return_type ~= 'interface' and return_type ~= 'default' then
                local params_str = params_block:sub(2, -2)
                local params = {}
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
                  return_type = return_type,
                  params = params,
                })
              end
            end
          end
        end
      end
      if sym.children and #sym.children > 0 then
        traverse(sym.children)
      end
    end
  end
  traverse(symbols)
  return methods
end

local function parse_methods_fallback(lines)
  local methods = {}
  local current_decl = {}
  for _, line in ipairs(lines) do
    local clean = line:gsub('//.*$', ''):gsub('/%*.-%*/', '')
    local trimmed = vim.trim(clean)
    if trimmed ~= '' then
      table.insert(current_decl, clean)
      local full_decl = table.concat(current_decl, ' ')
      
      local brace_idx = full_decl:find('{')
      local semi_idx = full_decl:find(';')
      
      if brace_idx and (not semi_idx or brace_idx < semi_idx) then
        current_decl = {}
      elseif semi_idx then
        local decl = full_decl:sub(1, semi_idx - 1)
        current_decl = {}
        
        local params_block = decl:match('%b()')
        if params_block then
          local before_params = vim.trim(decl:sub(1, decl:find('%b()') - 1))
          local before_params_no_ann = before_params:gsub('@[%w_%.]+%s*%b()', ''):gsub('@[%w_%.]+', '')
          before_params_no_ann = vim.trim(before_params_no_ann)
          local method_name = before_params_no_ann:match('([%w_]+)$')
          if method_name then
            local return_type = vim.trim(before_params_no_ann:sub(1, before_params_no_ann:find(method_name, 1, true) - 1))
            return_type = return_type:gsub('^public%s+', '')
                                   :gsub('^protected%s+', '')
                                   :gsub('^private%s+', '')
                                   :gsub('^abstract%s+', '')
                                   :gsub('^static%s+', '')
                                   :gsub('^final%s+', '')
            return_type = vim.trim(return_type)
            
            if return_type ~= '' and return_type ~= 'package' and return_type ~= 'import' and return_type ~= 'class' and return_type ~= 'interface' and return_type ~= 'default' then
              local params_str = params_block:sub(2, -2)
              local params = {}
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
                return_type = return_type,
                params = params,
              })
            end
          end
        end
      end
    end
  end
  return methods
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
 
  -- 3. 提取接口方法定义 (优先使用 LSP，若不可用则回退到文本解析器)
  local methods = get_methods_with_lsp(java_path, lines)
  if not methods or #methods == 0 then
    log.debug("LSP symbols not available or empty for virtual generation; fallback to text parser")
    methods = parse_methods_fallback(lines)
  end
 
  -- 提取 XML 中明确声明的 statement IDs
  local xml_ids = nil
  if util.is_file(xml_path) then
    local lsp_diag = require('mybatis-xml.lsp.diagnostics')
    xml_ids = lsp_diag._test.get_xml_ids(xml_path)
  end
 
  -- 过滤：仅保留在 XML 中有声明的非 default 方法
  local filtered_methods = {}
  for _, m in ipairs(methods) do
    if not xml_ids or xml_ids[m.name] then
      table.insert(filtered_methods, m)
    end
  end
  methods = filtered_methods
 
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
