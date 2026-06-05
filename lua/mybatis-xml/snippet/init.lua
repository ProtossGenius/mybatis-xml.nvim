-- [[ mybatis-xml.snippet ]]
-- LuaSnip 代码片段注册

local M = {}
local log = require('mybatis-xml.log')

--- 注册 MyBatis XML 代码片段
function M.register_snippets()
  local ok, ls = pcall(require, 'luasnip')
  if not ok then
    log.debug('LuaSnip not found, skipping snippet registration')
    return
  end

  local s = ls.snippet
  local t = ls.text_node
  local i = ls.insert_node

  ls.add_snippets('xml', {
    s('select', {
      t('<select id="'), i(1, 'id'), t('" parameterType="'), i(2, 'parameterType'), t('" resultType="'), i(3, 'resultType'), t('">'),
      t({ '', '    ' }), i(0),
      t({ '', '</select>' }),
    }),
    s('selectMap', {
      t('<select id="'), i(1, 'id'), t('" parameterType="'), i(2, 'parameterType'), t('" resultMap="'), i(3, 'resultMap'), t('">'),
      t({ '', '    ' }), i(0),
      t({ '', '</select>' }),
    }),
    s('insert', {
      t('<insert id="'), i(1, 'id'), t('" parameterType="'), i(2, 'parameterType'), t('">'),
      t({ '', '    ' }), i(0),
      t({ '', '</insert>' }),
    }),
    s('update', {
      t('<update id="'), i(1, 'id'), t('" parameterType="'), i(2, 'parameterType'), t('">'),
      t({ '', '    ' }), i(0),
      t({ '', '</update>' }),
    }),
    s('delete', {
      t('<delete id="'), i(1, 'id'), t('" parameterType="'), i(2, 'parameterType'), t('">'),
      t({ '', '    ' }), i(0),
      t({ '', '</delete>' }),
    }),
    s('resultMap', {
      t('<resultMap id="'), i(1, 'id'), t('" type="'), i(2, 'type'), t('">'),
      t({ '', '    <id column="id" property="id"/>' }),
      t({ '', '    ' }), i(0),
      t({ '', '</resultMap>' }),
    }),
    s('result', {
      t('<result column="'), i(1, 'column'), t('" property="'), i(2, 'property'), t('"/>'),
    }),
    -- MyBatis 动态 SQL 标签
    s('if', {
      t('<if test="'), i(1, 'condition'), t('">'),
      t({ '', '    ' }), i(0),
      t({ '', '</if>' }),
    }),
    s('where', {
      t('<where>'),
      t({ '', '    ' }), i(0),
      t({ '', '</where>' }),
    }),
    s('set', {
      t('<set>'),
      t({ '', '    ' }), i(0),
      t({ '', '</set>' }),
    }),
    s('foreach', {
      t('<foreach collection="'), i(1, 'list'), t('" item="'), i(2, 'item'),
      t('" open="'), i(3, '('), t('" close="'), i(4, ')'), t('" separator="'), i(5, ','), t('">'),
      t({ '', '    ' }), i(0),
      t({ '', '</foreach>' }),
    }),
    s('choose', {
      t('<choose>'),
      t({ '', '    <when test="' }), i(1, 'condition'), t('">'),
      t({ '', '        ' }), i(2),
      t({ '', '    </when>' }),
      t({ '', '    <otherwise>' }),
      t({ '', '        ' }), i(0),
      t({ '', '    </otherwise>' }),
      t({ '', '</choose>' }),
    }),
    s('trim', {
      t('<trim prefix="'), i(1, ''), t('" suffix="'), i(2, ''), t('" prefixOverrides="'), i(3, ''), t('" suffixOverrides="'), i(4, ''), t('">'),
      t({ '', '    ' }), i(0),
      t({ '', '</trim>' }),
    }),
    s('bind', {
      t('<bind name="'), i(1, 'name'), t('" value="'), i(2, 'value'), t('"/>'),
    }),
    s('include', {
      t('<include refid="'), i(1, 'refid'), t('"/>'),
    }),
    s('sql', {
      t('<sql id="'), i(1, 'id'), t('">'),
      t({ '', '    ' }), i(0),
      t({ '', '</sql>' }),
    }),
    -- 完整 mapper 骨架
    s('mapper', {
      t('<?xml version="1.0" encoding="UTF-8"?>'),
      t({ '', '<!DOCTYPE mapper PUBLIC "-//mybatis.org//DTD Mapper 3.0//EN" "http://mybatis.org/dtd/mybatis-3-mapper.dtd">' }),
      t({ '', '<mapper namespace="' }), i(1, 'com.example.mapper.XxxMapper'), t('">'),
      t({ '', '' }),
      t({ '', '    ' }), i(0),
      t({ '', '' }),
      t({ '', '</mapper>' }),
    }),
  })

  log.debug('LuaSnip MyBatis snippets registered')
end

return M
