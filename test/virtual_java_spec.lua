local test_dir = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ':h')
local support = dofile(test_dir .. '/spec_support.lua')

local generator = require('mybatis-xml.virtual.generator')
local sync = require('mybatis-xml.virtual.sync')
local project = require('mybatis-xml.project')

-- Create temporary directory structure for testing virtual java file generation
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
  'import com.example.model.User;',
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
  '    <select id="selectUsers" resultType="com.example.User">',
  '        select * from user',
  '    </select>',
  '    <delete id="deleteUser">',
  '        delete from user where id = #{id}',
  '    </delete>',
  '</mapper>',
}, xml_path)

-- Mock project root
local original_root = project.root
project.root = function() return temp_dir end

-- Open XML buffer so get_namespace works
vim.cmd('edit ' .. vim.fn.fnameescape(xml_path))
local xml_buf = vim.api.nvim_get_current_buf()

-- 1. Test get_virtual_path
local virtual_path = generator.get_virtual_path(xml_path, xml_buf)
support.expect_true('get_virtual_path returns path', virtual_path ~= nil)

local expected_virtual_path = src_dir .. '/_mybatis_virtual/UserMapperVirtual.java'
local function realpath(p)
  return vim.uv.fs_realpath(p) or vim.fs.normalize(p)
end
support.expect_equal('get_virtual_path matches expected', realpath(virtual_path), realpath(expected_virtual_path))

-- 2. Test generate_virtual_content
local content = generator.generate_virtual_content(xml_path, xml_buf)
support.expect_true('generate_virtual_content returns table', type(content) == 'table' and #content > 0)

local text = table.concat(content, '\n')
support.expect_true('virtual package is correct', text:match('package com.example._mybatis_virtual;') ~= nil)
support.expect_true('virtual inherits mapper interface', text:match('public abstract class UserMapperVirtual implements UserMapper') ~= nil)
support.expect_true('virtual has selectUserById override', text:match('public User selectUserById%b()') ~= nil)
support.expect_true('virtual has selectUsers override', text:match('public List<User> selectUsers%b()') ~= nil)
support.expect_true('virtual binds parameter', text:match('Object _val_id = id;') ~= nil)
support.expect_true('virtual returns null for object', text:match('return null;') ~= nil)

-- 3. Test write_virtual_file
local written = generator.write_virtual_file(xml_path, xml_buf)
support.expect_true('write_virtual_file returns true', written)
support.expect_true('virtual file exists on disk', vim.fn.filereadable(virtual_path) == 1)

-- 4. Test ensure_gitignore
local gitignore_path = temp_dir .. '/.gitignore'
support.expect_true('gitignore file was created', vim.fn.filereadable(gitignore_path) == 1)
local gitignore_lines = vim.fn.readfile(gitignore_path)
local gitignore_text = table.concat(gitignore_lines, '\n')
support.expect_true('gitignore has _mybatis_virtual pattern', gitignore_text:match('%*%*/_mybatis_virtual/') ~= nil)

-- Restore project root mock and cleanup
project.root = original_root
vim.fn.delete(temp_dir, 'rf')

support.flush()
