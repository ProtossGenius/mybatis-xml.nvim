--- mybatis-xml.nvim 跳转引擎入口
--- 统一 Ctrl+] 跳转处理，按优先链分发到各子模块

local M = {}

--- 统一跳转处理（Ctrl+]）
--- 优先级: 类引用 > resultMap property > resultMap 引用 > refid > 占位符 > mapper pair
---@param bufnr number
function M.jump_handler(bufnr)
  local class_ref = require('mybatis-xml.jump.class_ref')
  if class_ref.try_jump_class_ref(bufnr) then return end

  local resultmap = require('mybatis-xml.jump.resultmap')
  if resultmap.try_jump_resultmap_property(bufnr) then return end
  if resultmap.try_jump_result_map(bufnr) then return end

  local refid = require('mybatis-xml.jump.refid')
  if refid.try_jump_refid(bufnr) then return end

  local placeholder = require('mybatis-xml.jump.placeholder')
  if placeholder.try_jump_placeholder(bufnr) then return end

  -- fallback: 跳转到对应的 mapper pair
  local mapper_pair = require('mybatis-xml.jump.mapper_pair')
  mapper_pair.jump_mapper_pair('edit')
end

--- 为 MyBatis XML buffer 设置跳转快捷键
---@param bufnr number
function M.setup_xml_keymaps(bufnr)
  local completion = require('mybatis-xml.completion')
  local map_opts = { buffer = bufnr, silent = true }

  vim.keymap.set('n', '<C-]>', function()
    M.jump_handler(bufnr)
  end, vim.tbl_extend('force', map_opts, { desc = 'MyBatis: 跳转引用' }))

  vim.keymap.set('i', '{', function()
    completion.handle_open_brace(bufnr)
  end, vim.tbl_extend('force', map_opts, { desc = 'MyBatis: 参数补全' }))

  vim.api.nvim_buf_create_user_command(bufnr, 'MyBatisParamComplete', function()
    completion.manual_trigger(bufnr)
  end, { desc = 'MyBatis: 手动参数补全' })

  vim.keymap.set('i', '<C-x><C-o>', function()
    completion.manual_trigger(bufnr)
  end, vim.tbl_extend('force', map_opts, { desc = 'MyBatis: 手动补全' }))

  vim.keymap.set('n', '<leader>lp', function()
    completion.manual_trigger(bufnr)
  end, vim.tbl_extend('force', map_opts, { desc = 'MyBatis: 手动补全' }))
end

--- 为 Mapper Java buffer 设置导航快捷键
---@param bufnr number
function M.setup_java_keymaps(bufnr)
  local mapper_pair = require('mybatis-xml.jump.mapper_pair')
  if not mapper_pair.is_mapper_buffer(bufnr) then
    return
  end

  local function jump_edit()
    mapper_pair.jump_mapper_pair('edit')
  end
  local function jump_vsplit()
    mapper_pair.jump_mapper_pair('vsplit')
  end

  local map_opts = { buffer = bufnr, silent = true }
  vim.keymap.set('n', 'gf', jump_edit, vim.tbl_extend('force', map_opts, { desc = 'Jump mapper pair' }))
  vim.keymap.set('n', 'gF', jump_vsplit, vim.tbl_extend('force', map_opts, { desc = 'Jump mapper pair in split' }))
  vim.keymap.set('n', '<C-]>', jump_edit, vim.tbl_extend('force', map_opts, { desc = 'Jump mapper pair' }))
  vim.keymap.set('n', '<leader>li', jump_edit, vim.tbl_extend('force', map_opts, { desc = 'Mapper: Jump pair' }))
  vim.keymap.set('n', '<leader>lD', jump_vsplit, vim.tbl_extend('force', map_opts, { desc = 'Mapper: Jump pair in split' }))
end

return M
