local test_dir = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ':h')
local support = dofile(test_dir .. '/spec_support.lua')

local completion = require('mybatis-xml.completion')
local c_test = completion._test

local util = require('mybatis-xml.util')
local u_test = util._test

local class = require('mybatis-xml.completion.class')
local class_test = class._test or class

-- 1. Test get_completion_context
-- Test parameter completion
local line_param = "select * from user where email = #{em"
local col_param = #line_param
local ctx_p, start_p = c_test.get_completion_context(line_param, col_param)
support.expect_equal('get_completion_context parameter', { ctx_p, start_p }, { 'parameter', 35 })

-- Test class attribute completion
local line_class = 'type="com.ex"'
local ctx_c, start_c = c_test.get_completion_context(line_class, 8)
support.expect_equal('get_completion_context class', { ctx_c, start_c }, { 'class', 6 })

-- Test resultMap attribute completion
local line_rm = 'resultMap="Base"'
local ctx_rm, start_rm = c_test.get_completion_context(line_rm, 13)
support.expect_equal('get_completion_context resultMap', { ctx_rm, start_rm }, { 'resultmap', 11 })

-- Test refid attribute completion
local line_ref = 'refid="Base"'
local ctx_ref, start_ref = c_test.get_completion_context(line_ref, 9)
support.expect_equal('get_completion_context refid', { ctx_ref, start_ref }, { 'refid', 7 })

-- 2. Mock project root and Java class scanning/completing
local temp_dir = vim.fn.tempname()
vim.fn.mkdir(temp_dir .. '/src/main/java/com/example/demo/model', 'p')
temp_dir = vim.uv.fs_realpath(temp_dir) or vim.fs.normalize(temp_dir)

local user_class_path = temp_dir .. '/src/main/java/com/example/demo/model/User.java'
local order_class_path = temp_dir .. '/src/main/java/com/example/demo/model/Order.java'

vim.fn.writefile({ 'public class User {}' }, user_class_path)
vim.fn.writefile({ 'public class Order {}' }, order_class_path)

-- Mock project root in project module
local project = require('mybatis-xml.project')
local original_root = project.root
project.root = function() return temp_dir end

-- Test class scanning FQN extraction
local classes = class_test.get_all_project_classes(0)
table.sort(classes)
support.expect_equal('class scanning FQN count', #classes, 2)
support.expect_equal('class scanning FQN [1]', classes[1], 'com.example.demo.model.Order')
support.expect_equal('class scanning FQN [2]', classes[2], 'com.example.demo.model.User')

-- 3. Test omnifunc interface programmatically
support.reset({
  '<mapper namespace="com.example.UserMapper">',
  '  <resultMap id="UserResultMap" type="com.example.User">',
  '  </resultMap>',
  '  <sql id="Base_Column_List">',
  '    id, name',
  '  </sql>',
  '</mapper>'
}, 'xml')

-- Check resultMap completion in omnifunc
completion._omnifunc_context = 'resultmap'
local rm_matches = completion.omnifunc(0, 'User')
support.expect_equal('omnifunc resultmap match count', #rm_matches, 1)
support.expect_equal('omnifunc resultmap match details', rm_matches[1], { word = 'UserResultMap', abbr = 'UserResultMap', menu = '[ResultMap]' })

-- Check sql refid completion in omnifunc
completion._omnifunc_context = 'refid'
local ref_matches = completion.omnifunc(0, 'Base')
support.expect_equal('omnifunc refid match count', #ref_matches, 1)
support.expect_equal('omnifunc refid match details', ref_matches[1], { word = 'Base_Column_List', abbr = 'Base_Column_List', menu = '[SQL]' })

-- Check class completion in omnifunc
completion._omnifunc_context = 'class'
local class_matches = completion.omnifunc(0, 'User')
support.expect_equal('omnifunc class match count', #class_matches, 1)
support.expect_equal('omnifunc class match details', class_matches[1], { word = 'com.example.demo.model.User', abbr = 'User', menu = '[Class]', info = 'com.example.demo.model.User' })

-- 4. Test XML tag attribute completion context
local line_tag_attr = '<select id="findAll" '
vim.api.nvim_buf_set_lines(0, 0, 1, false, { line_tag_attr })
vim.api.nvim_win_set_cursor(0, { 1, #line_tag_attr })
local ctx_ta, start_ta = c_test.get_completion_context(line_tag_attr, #line_tag_attr)
support.expect_equal('get_completion_context tag attribute select', { ctx_ta, start_ta }, { 'tag_attribute_select', #line_tag_attr })

-- Restore project root mock
project.root = original_root
vim.fn.delete(temp_dir, 'rf')

support.flush()
