local test_dir = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ':h')
local support = dofile(test_dir .. '/spec_support.lua')

local resultmap = require('mybatis-xml.jump.resultmap')
local rm_test = resultmap._test

local placeholder = require('mybatis-xml.jump.placeholder')
local ph_test = placeholder._test

-- Create temporary directory structure for tests
local temp_dir = vim.fn.tempname()
vim.fn.mkdir(temp_dir .. '/src/main/java/com/example/demo/model', 'p')
temp_dir = vim.uv.fs_realpath(temp_dir) or vim.fs.normalize(temp_dir)

local user_class_path = temp_dir .. '/src/main/java/com/example/demo/model/User.java'
local user_mapper_class_path = temp_dir .. '/src/main/java/com/example/demo/model/UserMapper.java'

-- Mock project root
local project = require('mybatis-xml.project')
local original_root = project.root
project.root = function() return temp_dir end

-- 1. Test enclosing resultMap type lookup
support.reset({
  '<resultMap id="UserResultMap" type="com.example.demo.model.User">',
  '  <id column="id" property="id"/>',
  '  <result column="username" property="username"/>',
  '</resultMap>'
}, 'xml')

vim.api.nvim_win_set_cursor(0, { 3, 30 })
local rm_type = rm_test.find_enclosing_resultmap_type(0)
support.expect_equal('find_enclosing_resultmap_type inside resultMap', rm_type, 'com.example.demo.model.User')

-- Populate User.java with fields so the jump can locate 'username'
vim.fn.writefile({
  'package com.example.demo.model;',
  'public class User {',
  '  private Long id;',
  '  private String username;',
  '}'
}, user_class_path)

-- Test try_jump_resultmap_property
vim.api.nvim_win_set_cursor(0, { 3, 1 })
vim.bo.modified = false
local jumped = rm_test.try_jump_resultmap_property(0)
support.expect_equal('try_jump_resultmap_property from anywhere on the line', jumped, true)

local current_buf = vim.api.nvim_get_current_buf()
local current_file = vim.api.nvim_buf_get_name(current_buf)
local current_cursor = vim.api.nvim_win_get_cursor(0)
support.expect_true('jumped to correct Model class file', current_file:find('User%.java$') ~= nil)
support.expect_equal('jumped to correct field line in Model class', current_cursor[1], 4)

-- Test field declaration matching
local java_lines = {
  'public class User {',
  '  private Long id;',
  '  private String username;',
  '  private List<String> roles = new ArrayList<>();',
  '}'
}
local field_ln1 = rm_test.find_field_declaration_line(java_lines, 'id')
support.expect_equal('find_field_declaration_line for id', field_ln1, 2)
local field_ln2 = rm_test.find_field_declaration_line(java_lines, 'username')
support.expect_equal('find_field_declaration_line for username', field_ln2, 3)
local field_ln3 = rm_test.find_field_declaration_line(java_lines, 'roles')
support.expect_equal('find_field_declaration_line for roles with generics', field_ln3, 4)

-- 2. Test get_placeholder_at_cursor
local placeholder_line = 'select * from user where name = #{user.name } and status = ${status}'
local p1 = ph_test.get_placeholder_at_cursor(placeholder_line, 36)
support.expect_equal('get_placeholder_at_cursor user.name', p1, 'user.name')
local p2 = ph_test.get_placeholder_at_cursor(placeholder_line, 60)
support.expect_equal('get_placeholder_at_cursor status', p2, 'status')
local p3 = ph_test.get_placeholder_at_cursor(placeholder_line, 10)
support.expect_equal('get_placeholder_at_cursor out of bounds', p3, nil)

-- 3. Test FQN resolution in Java files
vim.fn.writefile({
  'package com.example.demo.model;',
  'import com.example.demo.model.User;',
  'import com.example.demo.dto.UserQuery;',
  'public interface UserMapper {}'
}, user_mapper_class_path)

local param_user = { type = 'User', full_type = 'User' }
local fqn_user = ph_test.resolve_param_type_fqn(param_user, user_mapper_class_path)
support.expect_equal('resolve_param_type_fqn from import', fqn_user, 'com.example.demo.model.User')

local param_query = { type = 'UserQuery', full_type = 'UserQuery' }
local fqn_query = ph_test.resolve_param_type_fqn(param_query, user_mapper_class_path)
support.expect_equal('resolve_param_type_fqn from import 2', fqn_query, 'com.example.demo.dto.UserQuery')

-- Restore project root mock and cleanup temp files
project.root = original_root
vim.fn.delete(temp_dir, 'rf')

support.flush()
