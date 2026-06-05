local test_dir = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ':h')
local support = dofile(test_dir .. '/spec_support.lua')

local util = require('mybatis-xml.util')
local u_test = util._test

local parameter = require('mybatis-xml.completion.parameter')
local p_test = parameter._test

-- 1. Test is_model_type
support.expect_equal('is_model_type String is false', u_test.is_model_type('String'), false)
support.expect_equal('is_model_type int is false', u_test.is_model_type('int'), false)
support.expect_equal('is_model_type List is false', u_test.is_model_type('List'), false)
support.expect_equal('is_model_type User is true', u_test.is_model_type('User'), true)
support.expect_equal('is_model_type com.example.User is true', u_test.is_model_type('com.example.User'), true)

-- 2. Test fqn_to_path
support.expect_equal('fqn_to_path simple FQN', u_test.fqn_to_path('com.example.User'), 'com/example/User.java')

-- 3. Test get_attribute_at_cursor
local line = '<resultMap id="BaseResultMap" type="com.example.model.User">'
support.expect_equal('get_attribute_at_cursor type FQN', { u_test.get_attribute_at_cursor(line, 40) }, { 'type', 'com.example.model.User' })
support.expect_equal('get_attribute_at_cursor id attr', { u_test.get_attribute_at_cursor(line, 18) }, { 'id', 'BaseResultMap' })
support.expect_equal('get_attribute_at_cursor out of bounds', { u_test.get_attribute_at_cursor(line, 5) }, { nil, nil })

-- 4. Test parse_method_params and extract_model_fields with temp files
local temp_dir = vim.fn.tempname()
vim.fn.mkdir(temp_dir .. '/src/main/java/com/example', 'p')
temp_dir = vim.uv.fs_realpath(temp_dir) or vim.fs.normalize(temp_dir)

local mapper_path = temp_dir .. '/src/main/java/com/example/UserMapper.java'
local model_path = temp_dir .. '/src/main/java/com/example/User.java'

vim.fn.writefile({
  'package com.example;',
  'import org.apache.ibatis.annotations.Param;',
  'import java.util.List;',
  'public interface UserMapper {',
  '    User selectUserById(@Param("id") Long id);',
  '    int insertUser(User user);',
  '    List<User> selectUsers(@Param("status") Integer status, @Param("role") String role);',
  '}',
}, mapper_path)

vim.fn.writefile({
  'package com.example;',
  'import lombok.Data;',
  '@Data',
  'public class User {',
  '    private Long id;',
  '    private String username;',
  '    private String email;',
  '    public static final long serialVersionUID = 1L;',
  '}',
}, model_path)

-- Test parse_method_params
local select_params = p_test.parse_method_params(mapper_path, 'selectUserById')
support.expect_equal('parse_method_params selectUserById count', #select_params, 1)
support.expect_equal('parse_method_params selectUserById name', select_params[1].name, 'id')
support.expect_equal('parse_method_params selectUserById type', select_params[1].type, 'Long')
support.expect_equal('parse_method_params selectUserById annotation', select_params[1].param_annotation, 'id')

local insert_params = p_test.parse_method_params(mapper_path, 'insertUser')
support.expect_equal('parse_method_params insertUser count', #insert_params, 1)
support.expect_equal('parse_method_params insertUser type', insert_params[1].type, 'User')
support.expect_equal('parse_method_params insertUser name', insert_params[1].name, 'user')

local multiple_params = p_test.parse_method_params(mapper_path, 'selectUsers')
support.expect_equal('parse_method_params selectUsers count', #multiple_params, 2)
support.expect_equal('parse_method_params selectUsers [1] name', multiple_params[1].name, 'status')
support.expect_equal('parse_method_params selectUsers [2] name', multiple_params[2].name, 'role')

-- Test extract_model_fields
local fields = p_test.extract_model_fields(model_path)
support.expect_equal('extract_model_fields fields count', #fields, 3)
support.expect_true('extract_model_fields contains id', vim.tbl_contains(fields, 'id'))
support.expect_true('extract_model_fields contains username', vim.tbl_contains(fields, 'username'))
support.expect_true('extract_model_fields contains email', vim.tbl_contains(fields, 'email'))
support.expect_true('extract_model_fields serialVersionUID is ignored', not vim.tbl_contains(fields, 'serialVersionUID'))

-- Test is_mybatis_mapper and get_namespace
support.reset({
  '<?xml version="1.0" encoding="UTF-8"?>',
  '<!DOCTYPE mapper PUBLIC "-//mybatis.org//DTD Mapper 3.0//EN" "http://mybatis.org/dtd/mybatis-3-0.dtd">',
  '<mapper namespace="com.example.UserMapper">',
  '    <select id="getUserById" resultType="com.example.User">',
  '        select * from user where id = #{id}',
  '    </select>',
  '    <insert id="insertUser">',
  '        insert into user (username) values (#{username})',
  '    </insert>',
  '</mapper>',
}, 'xml', 'xml')

local current_buf = vim.api.nvim_get_current_buf()
support.expect_true('is_mybatis_mapper on mybatis mapper XML', u_test.is_mybatis_mapper(current_buf))
support.expect_equal('get_namespace returns correct namespace', u_test.get_namespace(current_buf), 'com.example.UserMapper')

-- Test find_current_statement_id
support.set_cursor_on_substring(5, 'where id = #{id}', 1)
support.expect_equal('find_current_statement_id inside getUserById', u_test.find_current_statement_id(current_buf), 'getUserById')

support.set_cursor_on_substring(8, 'values', 1)
support.expect_equal('find_current_statement_id inside insertUser', u_test.find_current_statement_id(current_buf), 'insertUser')

-- Cleanup
vim.fn.delete(temp_dir, 'rf')

support.flush()
