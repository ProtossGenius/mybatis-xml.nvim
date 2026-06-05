--- mybatis-xml.nvim 数据库同步模块 — resultMap/Model 解析
local M = {}
local util = require('mybatis-xml.util')

--- 解析 mapper XML 中的 resultMap 块
---@param mapper_xml_path string
---@return table[] entries, table[] metas
function M.parse_resultmap(mapper_xml_path)
  local content = table.concat(util.read_file_lines(mapper_xml_path), '\n')
  local entries = {}
  local metas = {}

  for rm_tag, rm_body in content:gmatch('<resultMap([^>]-)>(.-)</resultMap>') do
    local rm_id = rm_tag:match('id%s*=%s*"([^"]+)"')
    local rm_type = rm_tag:match('type%s*=%s*"([^"]+)"')
    table.insert(metas, { id = rm_id, type = rm_type })

    for tag_name, tag_content in rm_body:gmatch('<(%w+)%s([^>]-)/?>') do
      if tag_name == 'result' or tag_name == 'id' then
        local col = tag_content:match('column%s*=%s*"([^"]+)"')
        local prop = tag_content:match('property%s*=%s*"([^"]+)"')
        local jdbc = tag_content:match('jdbcType%s*=%s*"([^"]+)"')
        if col and prop then
          table.insert(entries, { column = col, property = prop, jdbc_type = jdbc or '' })
        end
      end
    end
  end

  return entries, metas
end

--- 解析 Java Model 文件中的字段声明
---@param model_java_path string
---@return table[] fields, boolean has_data
function M.parse_model_fields(model_java_path)
  local lines = util.read_file_lines(model_java_path)
  local fields = {}
  local has_data = false

  for _, line in ipairs(lines) do
    if line:match('@Data') then
      has_data = true
    end
    local field_type, field_name = line:match('^%s*private%s+([%w_<>%[%],%s%.]+)%s+([%w_]+)%s*[=;]')
    if field_type and field_name then
      field_type = field_type:gsub('%s+$', ''):gsub('%s+', ' ')
      table.insert(fields, { name = field_name, type = field_type })
    end
  end

  return fields, has_data
end

--- 从 Java 文件中解析注解获取表名
---@param java_file_path string
---@param annotation_config table
---@return string|nil
function M.find_table_name(java_file_path, annotation_config)
  if not java_file_path or not util.is_file(java_file_path) then
    return nil
  end
  local content = table.concat(util.read_file_lines(java_file_path), '\n')
  local class_name = annotation_config.class
  local field_name = annotation_config.field

  local pattern1 = '@' .. vim.pesc(class_name) .. '%s*%(' .. '.-' .. vim.pesc(field_name) .. '%s*=%s*"([^"]+)"'
  local value = content:match(pattern1)
  if value then return value end

  local pattern2 = '@' .. vim.pesc(class_name) .. '%s*%(%s*"([^"]+)"%s*%)'
  return content:match(pattern2)
end

M._test = {
  parse_resultmap = M.parse_resultmap,
  parse_model_fields = M.parse_model_fields,
  find_table_name = M.find_table_name,
}

return M
