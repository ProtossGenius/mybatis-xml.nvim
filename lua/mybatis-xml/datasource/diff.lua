--- mybatis-xml.nvim 数据库同步模块 — 差异计算
local M = {}
local type_map = require('mybatis-xml.datasource.type_map')

--- 比对数据库列、resultMap 字段和 Model 字段的差异
---@param db_columns table[]
---@param resultmap_fields table[]
---@param model_fields table[]
---@return table diff
function M.compute_diff(db_columns, resultmap_fields, model_fields)
  local rm_columns = {}
  for _, entry in ipairs(resultmap_fields) do
    rm_columns[entry.column] = true
  end

  local model_map = {}
  for _, field in ipairs(model_fields) do
    model_map[field.name] = field.type
  end

  local missing_in_resultmap = {}
  local missing_in_model = {}
  local type_mismatch_in_model = {}

  for _, col in ipairs(db_columns) do
    local property_name = type_map.snake_to_camel(col.name)
    local expected_java_type = type_map.mysql_type_to_java(col.type)
    local jdbc_type = type_map.mysql_type_to_jdbc(col.type)

    if not rm_columns[col.name] then
      table.insert(missing_in_resultmap, {
        column = col.name, property = property_name,
        jdbc_type = jdbc_type, java_type = expected_java_type,
        mysql_type = col.type,
      })
    end

    local existing_type = model_map[property_name]
    if not existing_type then
      table.insert(missing_in_model, {
        name = property_name, java_type = expected_java_type,
        column = col.name, mysql_type = col.type,
      })
    elseif existing_type ~= expected_java_type then
      table.insert(type_mismatch_in_model, {
        name = property_name, expected = expected_java_type,
        actual = existing_type, column = col.name,
      })
    end
  end

  return {
    missing_in_resultmap = missing_in_resultmap,
    missing_in_model = missing_in_model,
    type_mismatch_in_model = type_mismatch_in_model,
  }
end

--- 判断 diff 是否为空
function M.is_diff_empty(diff)
  return #diff.missing_in_resultmap == 0
    and #diff.missing_in_model == 0
    and #diff.type_mismatch_in_model == 0
end

M._test = {
  compute_diff = M.compute_diff,
  is_diff_empty = M.is_diff_empty,
}

return M
