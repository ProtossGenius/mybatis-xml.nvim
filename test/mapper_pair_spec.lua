local test_dir = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ':h')
local support = dofile(test_dir .. '/spec_support.lua')

local mapper_pair = require('mybatis-xml.jump.mapper_pair')
local j_test = mapper_pair._test

-- 1. Test get_tag_type
support.expect_equal('get_tag_type select', j_test.get_tag_type('selectUser'), 'select')
support.expect_equal('get_tag_type find', j_test.get_tag_type('findUser'), 'select')
support.expect_equal('get_tag_type get', j_test.get_tag_type('getUser'), 'select')
support.expect_equal('get_tag_type query', j_test.get_tag_type('queryUser'), 'select')
support.expect_equal('get_tag_type insert', j_test.get_tag_type('insertUser'), 'insert')
support.expect_equal('get_tag_type add', j_test.get_tag_type('addUser'), 'insert')
support.expect_equal('get_tag_type save', j_test.get_tag_type('saveUser'), 'insert')
support.expect_equal('get_tag_type update', j_test.get_tag_type('updateUser'), 'update')
support.expect_equal('get_tag_type modify', j_test.get_tag_type('modifyUser'), 'update')
support.expect_equal('get_tag_type delete', j_test.get_tag_type('deleteUser'), 'delete')
support.expect_equal('get_tag_type remove', j_test.get_tag_type('removeUser'), 'delete')
support.expect_equal('get_tag_type unknown defaults to select', j_test.get_tag_type('otherFunc'), 'select')

-- Create temporary directory structure for path resolution and return type tests
local temp_dir = vim.fn.tempname()
temp_dir = vim.uv.fs_realpath(temp_dir) or vim.fs.normalize(temp_dir)

local src_dir = temp_dir .. '/src/main/java/com/example'
local resources_dir = temp_dir .. '/src/main/resources/mapper'
vim.fn.mkdir(src_dir, 'p')
vim.fn.mkdir(resources_dir, 'p')
vim.fn.writefile({}, temp_dir .. '/.root') -- root marker

local java_path = src_dir .. '/UserMapper.java'
local xml_path = resources_dir .. '/UserMapper.xml'

vim.fn.writefile({
  'package com.example;',
  'import org.apache.ibatis.annotations.Param;',
  'import java.util.List;',
  'public interface UserMapper {',
  '    User selectUserById(@Param("id") Long id);',
  '    List<User> selectUsers();',
  '    void deleteUser(Long id);',
  '}',
}, java_path)

vim.fn.writefile({
  '<?xml version="1.0" encoding="UTF-8"?>',
  '<!DOCTYPE mapper PUBLIC "-//mybatis.org//DTD Mapper 3.0//EN" "http://mybatis.org/dtd/mybatis-3-0.dtd">',
  '<mapper namespace="com.example.UserMapper">',
  '    <select id="selectUserById" resultType="com.example.User">',
  '        select * from user where id = #{id}',
  '    </select>',
  '</mapper>',
}, xml_path)

-- Open java buffer
vim.cmd('edit ' .. vim.fn.fnameescape(java_path))
local java_buf = vim.api.nvim_get_current_buf()

-- Mock project root
local project = require('mybatis-xml.project')
local original_root = project.root
project.root = function() return temp_dir end

-- 2. Test is_mapper_java_buffer and is_mapper_xml_buffer
support.expect_equal('is_mapper_java_buffer true', j_test.is_mapper_java_buffer(java_buf), true)
support.expect_equal('is_mapper_xml_buffer false for Java', j_test.is_mapper_xml_buffer(java_buf), false)

-- Open XML buffer
vim.cmd('edit ' .. vim.fn.fnameescape(xml_path))
local xml_buf = vim.api.nvim_get_current_buf()
support.expect_equal('is_mapper_xml_buffer true', j_test.is_mapper_xml_buffer(xml_buf), true)
support.expect_equal('is_mapper_java_buffer false for XML', j_test.is_mapper_java_buffer(xml_buf), false)

-- 3. Test resolve_mapper_xml and resolve_mapper_java
local function realpath(p)
  return vim.uv.fs_realpath(p) or vim.fs.normalize(p)
end
support.expect_equal('resolve_mapper_xml resolves correct file', realpath(j_test.resolve_mapper_xml(java_buf)), realpath(xml_path))
support.expect_equal('resolve_mapper_java resolves correct file', realpath(j_test.resolve_mapper_java(xml_buf)), realpath(java_path))

-- 4. Test java_fqn and java_fqn_from_file
support.expect_equal('java_fqn_from_file mapper', j_test.java_fqn_from_file(java_path), 'com.example.UserMapper')

-- 5. Test xml_statement_id, java_method_name, get_method_return_type
vim.cmd('edit ' .. vim.fn.fnameescape(java_path))
support.expect_equal('get_method_return_type selectUserById', j_test.get_method_return_type(java_path, 'selectUserById'), 'User')
support.expect_equal('get_method_return_type selectUsers', j_test.get_method_return_type(java_path, 'selectUsers'), 'List<User>')

-- Set cursor to selectUserById line
support.set_cursor_on_substring(5, 'selectUserById', 1)
support.expect_equal('java_method_name selectUserById', j_test.java_method_name(java_buf), 'selectUserById')

-- Restore original root
project.root = original_root
-- Clean up
vim.fn.delete(temp_dir, 'rf')

support.flush()
