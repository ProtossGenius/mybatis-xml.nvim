local test_dir = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ':h')
local support = dofile(test_dir .. '/spec_support.lua')

local type_map = require('mybatis-xml.datasource.type_map')
local parser = require('mybatis-xml.datasource.parser')
local diff_mod = require('mybatis-xml.datasource.diff')
local fix = require('mybatis-xml.datasource.fix')

-- 1. Test snake_to_camel
support.expect_equal('snake_to_camel simple', type_map.snake_to_camel('user_name'), 'userName')
support.expect_equal('snake_to_camel uppercase', type_map.snake_to_camel('CREATED_AT'), 'createdAt')
support.expect_equal('snake_to_camel single word', type_map.snake_to_camel('id'), 'id')
support.expect_equal('snake_to_camel empty', type_map.snake_to_camel(''), '')

-- 2. Test mysql_type_to_java
support.expect_equal('mysql_type_to_java varchar', type_map.mysql_type_to_java('varchar(64)'), 'String')
support.expect_equal('mysql_type_to_java bigint', type_map.mysql_type_to_java('bigint(20) unsigned'), 'Long')
support.expect_equal('mysql_type_to_java datetime', type_map.mysql_type_to_java('datetime'), 'Date')
support.expect_equal('mysql_type_to_java decimal', type_map.mysql_type_to_java('decimal(10,2)'), 'BigDecimal')

-- 3. Test mysql_type_to_jdbc
support.expect_equal('mysql_type_to_jdbc varchar', type_map.mysql_type_to_jdbc('varchar(64)'), 'VARCHAR')
support.expect_equal('mysql_type_to_jdbc bigint', type_map.mysql_type_to_jdbc('bigint'), 'BIGINT')
support.expect_equal('mysql_type_to_jdbc datetime', type_map.mysql_type_to_jdbc('datetime'), 'TIMESTAMP')

-- 4. Create temp files to test find_table_name, parse_resultmap, parse_model_fields, and apply_fix
local temp_dir = vim.fn.tempname()
vim.fn.mkdir(temp_dir, 'p')
temp_dir = vim.uv.fs_realpath(temp_dir) or vim.fs.normalize(temp_dir)

local model_path = temp_dir .. '/User.java'
local mapper_xml_path = temp_dir .. '/UserMapper.xml'

vim.fn.writefile({
  'package com.example.model;',
  'import javax.persistence.Table;',
  'import lombok.Data;',
  '',
  '@Table(name = "t_user")',
  '@Data',
  'public class User {',
  '    private Long id;',
  '    private String userName;',
  '}',
}, model_path)

vim.fn.writefile({
  '<?xml version="1.0" encoding="UTF-8"?>',
  '<mapper namespace="com.example.mapper.UserMapper">',
  '    <resultMap id="BaseResultMap" type="com.example.model.User">',
  '        <id column="id" property="id" jdbcType="BIGINT"/>',
  '        <result column="user_name" property="userName" jdbcType="VARCHAR"/>',
  '    </resultMap>',
  '</mapper>',
}, mapper_xml_path)

-- Test find_table_name
local table_name_model = parser.find_table_name(model_path, { class = 'Table', field = 'name' })
support.expect_equal('find_table_name from model annotation', table_name_model, 't_user')

-- Test parse_resultmap
local entries, metas = parser.parse_resultmap(mapper_xml_path)
support.expect_equal('parse_resultmap metas count', #metas, 1)
support.expect_equal('parse_resultmap metas type', metas[1].type, 'com.example.model.User')
support.expect_equal('parse_resultmap entries count', #entries, 2)
support.expect_equal('parse_resultmap entries[1] column', entries[1].column, 'id')
support.expect_equal('parse_resultmap entries[2] property', entries[2].property, 'userName')

-- Test parse_model_fields
local fields, has_data = parser.parse_model_fields(model_path)
support.expect_equal('parse_model_fields has_data annotation', has_data, true)
support.expect_equal('parse_model_fields fields count', #fields, 2)
support.expect_equal('parse_model_fields fields[1] name', fields[1].name, 'id')
support.expect_equal('parse_model_fields fields[2] type', fields[2].type, 'String')

-- 5. Test compute_diff
local db_columns = {
  { name = 'id', type = 'bigint' },
  { name = 'user_name', type = 'varchar(64)' },
  { name = 'email', type = 'varchar(128)' }, -- missing in both model and resultMap
}

local diff = diff_mod.compute_diff(db_columns, entries, fields)
support.expect_equal('compute_diff missing in resultMap count', #diff.missing_in_resultmap, 1)
support.expect_equal('compute_diff missing in resultMap column', diff.missing_in_resultmap[1].column, 'email')
support.expect_equal('compute_diff missing in model count', #diff.missing_in_model, 1)
support.expect_equal('compute_diff missing in model name', diff.missing_in_model[1].name, 'email')

-- 6. Test apply_fix with @Data annotation (no getter/setters)
diff.missing_in_resultmap[1].jdbc_type = 'VARCHAR'
diff.missing_in_model[1].java_type = 'String'
fix.apply_fix(diff, mapper_xml_path, model_path, true)

local xml_lines = vim.fn.readfile(mapper_xml_path)
local xml_text = table.concat(xml_lines, '\n')
support.expect_true('apply_fix resultMap has email', xml_text:match('<result column="email" property="email" jdbcType="VARCHAR"/>') ~= nil)

local java_lines = vim.fn.readfile(model_path)
local java_text = table.concat(java_lines, '\n')
support.expect_true('apply_fix model has email field', java_text:match('private String email;') ~= nil)
support.expect_true('apply_fix model with @Data has no getter', java_text:match('public String getEmail') == nil)

-- 7. Test apply_fix without @Data annotation (generates getter/setters)
-- Reset model file without @Data
vim.fn.writefile({
  'package com.example.model;',
  'public class User {',
  '    private Long id;',
  '    private String userName;',
  '}',
}, model_path)

local fields_no_data, has_data_no_data = parser.parse_model_fields(model_path)
local diff_no_data = diff_mod.compute_diff(db_columns, entries, fields_no_data)
diff_no_data.missing_in_model[1].java_type = 'String'

fix.apply_fix(diff_no_data, mapper_xml_path, model_path, false)

local java_lines_no_data = vim.fn.readfile(model_path)
local java_text_no_data = table.concat(java_lines_no_data, '\n')
support.expect_true('apply_fix model without @Data has getter', java_text_no_data:match('public String getEmail%b()') ~= nil)
support.expect_true('apply_fix model without @Data has setter', java_text_no_data:match('public void setEmail%b()') ~= nil)

-- Cleanup
vim.fn.delete(temp_dir, 'rf')

support.flush()
