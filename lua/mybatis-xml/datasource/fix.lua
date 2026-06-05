--- mybatis-xml.nvim 数据库同步模块 — 自动修复
local M = {}
local util = require('mybatis-xml.util')
local log = require('mybatis-xml.log')

local function write_file(path, text)
  local lines = vim.split(text, '\n', { plain = true })
  vim.fn.writefile(lines, path)
end

--- 将 diff 中的缺失项写入 mapper XML 和 model Java 文件
---@param diff table
---@param mapper_xml_path string
---@param model_java_path string
---@param has_data_annotation boolean
function M.apply_fix(diff, mapper_xml_path, model_java_path, has_data_annotation)
  -- ── 补齐 resultMap ──
  if #diff.missing_in_resultmap > 0 and util.is_file(mapper_xml_path) then
    local xml_lines = util.read_file_lines(mapper_xml_path)
    local insert_indices = {}
    for i = #xml_lines, 1, -1 do
      if xml_lines[i]:match('</resultMap>') then
        table.insert(insert_indices, 1, i)
      end
    end

    if #insert_indices > 0 then
      local insert_at = insert_indices[#insert_indices]
      local indent = xml_lines[insert_at]:match('^(%s*)') or ''
      indent = indent .. '    '

      local new_lines = {}
      for _, entry in ipairs(diff.missing_in_resultmap) do
        table.insert(new_lines, indent .. '<result column="' .. entry.column
          .. '" property="' .. entry.property
          .. '" jdbcType="' .. entry.jdbc_type .. '"/>')
      end

      for i = #new_lines, 1, -1 do
        table.insert(xml_lines, insert_at, new_lines[i])
      end

      write_file(mapper_xml_path, table.concat(xml_lines, '\n'))
      log.info('resultMap 已补齐 %d 个字段', #diff.missing_in_resultmap)
    end
  end

  -- ── 补齐 Model 字段 ──
  if #diff.missing_in_model > 0 and util.is_file(model_java_path) then
    local model_lines = util.read_file_lines(model_java_path)
    local model_text = table.concat(model_lines, '\n')

    local fields_to_add = {}
    for _, entry in ipairs(diff.missing_in_model) do
      local field_pattern = '%s' .. vim.pesc(entry.name) .. '%s*[=;]'
      if not model_text:match(field_pattern) then
        table.insert(fields_to_add, entry)
      end
    end

    if #fields_to_add > 0 then
      local last_field_line = nil
      for i, line in ipairs(model_lines) do
        if line:match('^%s*private%s+') or line:match('^%s*protected%s+')
          or line:match('^%s*public%s+[%w_<>%[%]]+%s+[%w_]+%s*[=;]') then
          last_field_line = i
        end
      end

      if not last_field_line then
        for i, line in ipairs(model_lines) do
          if line:match('class%s+%w+') then
            last_field_line = i + 1
            break
          end
        end
      end

      if last_field_line then
        -- import 处理
        local needs_date = false
        local needs_big_decimal = false
        for _, entry in ipairs(fields_to_add) do
          if entry.java_type == 'Date' then needs_date = true
          elseif entry.java_type == 'BigDecimal' then needs_big_decimal = true end
        end

        local imports_to_add = {}
        if needs_date and not model_text:match('import%s+java%.util%.Date') then
          table.insert(imports_to_add, 'import java.util.Date;')
        end
        if needs_big_decimal and not model_text:match('import%s+java%.math%.BigDecimal') then
          table.insert(imports_to_add, 'import java.math.BigDecimal;')
        end

        if #imports_to_add > 0 then
          local last_import_line = 0
          for i, line in ipairs(model_lines) do
            if line:match('^%s*import%s+') then last_import_line = i end
          end
          if last_import_line > 0 then
            for idx, imp in ipairs(imports_to_add) do
              table.insert(model_lines, last_import_line + idx, imp)
              last_field_line = last_field_line + 1
            end
          end
        end

        -- 生成字段声明和可选 getter/setter
        local new_lines = {}
        for _, entry in ipairs(fields_to_add) do
          table.insert(new_lines, '')
          table.insert(new_lines, '    private ' .. entry.java_type .. ' ' .. entry.name .. ';')

          if not has_data_annotation then
            local capitalized = entry.name:sub(1, 1):upper() .. entry.name:sub(2)
            local getter_prefix = entry.java_type == 'Boolean' and 'is' or 'get'
            table.insert(new_lines, '')
            table.insert(new_lines, '    public ' .. entry.java_type .. ' ' .. getter_prefix .. capitalized .. '() {')
            table.insert(new_lines, '        return ' .. entry.name .. ';')
            table.insert(new_lines, '    }')
            table.insert(new_lines, '')
            table.insert(new_lines, '    public void set' .. capitalized .. '(' .. entry.java_type .. ' ' .. entry.name .. ') {')
            table.insert(new_lines, '        this.' .. entry.name .. ' = ' .. entry.name .. ';')
            table.insert(new_lines, '    }')
          end
        end

        for i = #new_lines, 1, -1 do
          table.insert(model_lines, last_field_line + 1, new_lines[i])
        end

        write_file(model_java_path, table.concat(model_lines, '\n'))
        log.info('Model 已补齐 %d 个字段', #fields_to_add)
      end
    end
  end

  -- 类型不匹配仅警告
  if #diff.type_mismatch_in_model > 0 then
    for _, entry in ipairs(diff.type_mismatch_in_model) do
      log.warn('类型不匹配: %s 期望 %s, 实际 %s', entry.name, entry.expected, entry.actual)
    end
  end
end

--- 在浮窗中展示 diff 摘要，用户确认后执行回调
---@param diff table
---@param context table
---@param on_confirm fun()
function M.show_diff_window(diff, context, on_confirm)
  local lines = {}
  table.insert(lines, '表: ' .. (context.table_name or '?'))
  table.insert(lines, 'Mapper XML: ' .. (context.mapper_xml or '?'))
  table.insert(lines, 'Model Java: ' .. (context.model_java or '?'))
  table.insert(lines, string.rep('─', 60))

  if #diff.missing_in_resultmap > 0 then
    table.insert(lines, '')
    table.insert(lines, '▸ resultMap 中缺失的列 (' .. #diff.missing_in_resultmap .. '):')
    for _, entry in ipairs(diff.missing_in_resultmap) do
      table.insert(lines, '    <result column="' .. entry.column .. '" property="' .. entry.property .. '" jdbcType="' .. entry.jdbc_type .. '"/>')
    end
  end

  if #diff.missing_in_model > 0 then
    table.insert(lines, '')
    table.insert(lines, '▸ Model 中缺失的字段 (' .. #diff.missing_in_model .. '):')
    for _, entry in ipairs(diff.missing_in_model) do
      table.insert(lines, '    private ' .. entry.java_type .. ' ' .. entry.name .. ';  ← ' .. entry.column .. ' (' .. entry.mysql_type .. ')')
    end
  end

  if #diff.type_mismatch_in_model > 0 then
    table.insert(lines, '')
    table.insert(lines, '▸ Model 类型不匹配 (' .. #diff.type_mismatch_in_model .. '):')
    for _, entry in ipairs(diff.type_mismatch_in_model) do
      table.insert(lines, '    ' .. entry.name .. ': 期望 ' .. entry.expected .. ', 实际 ' .. entry.actual .. '  (⚠ 不自动修复)')
    end
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].buftype = 'nofile'

  local width = 80
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line) + 4)
  end
  width = math.min(width, vim.o.columns - 4)
  local height = math.min(#lines, vim.o.lines - 6)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width, height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal', border = 'rounded',
    title = ' Datasource Sync ', title_pos = 'center',
    footer = ' q: 关闭  y: 确认应用 ', footer_pos = 'center',
  })
  vim.wo[win].wrap = false

  local closed = false
  local function close_win()
    if closed then return end
    closed = true
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  vim.keymap.set('n', 'q', close_win, { buffer = buf, silent = true })
  vim.keymap.set('n', '<Esc>', close_win, { buffer = buf, silent = true })
  vim.keymap.set('n', 'y', function()
    close_win()
    on_confirm()
  end, { buffer = buf, silent = true })

  vim.api.nvim_create_autocmd('BufLeave', { buffer = buf, once = true, callback = close_win })
end

M._test = {
  apply_fix = M.apply_fix,
}

return M
