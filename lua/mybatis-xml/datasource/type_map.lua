--- mybatis-xml.nvim 类型映射模块
--- MySQL → Java / JDBC 类型映射

local M = {}

local mysql_to_java_map = {
  bigint      = 'Long',
  int         = 'Integer',
  integer     = 'Integer',
  tinyint     = 'Integer',
  smallint    = 'Integer',
  mediumint   = 'Integer',
  varchar     = 'String',
  char        = 'String',
  text        = 'String',
  longtext    = 'String',
  mediumtext  = 'String',
  datetime    = 'Date',
  timestamp   = 'Date',
  date        = 'Date',
  decimal     = 'BigDecimal',
  numeric     = 'BigDecimal',
  double      = 'Double',
  float       = 'Float',
  bit         = 'Boolean',
  boolean     = 'Boolean',
  blob        = 'byte[]',
  longblob    = 'byte[]',
  mediumblob  = 'byte[]',
}

local mysql_to_jdbc_map = {
  bigint    = 'BIGINT',
  int       = 'INTEGER',
  integer   = 'INTEGER',
  varchar   = 'VARCHAR',
  char      = 'VARCHAR',
  text      = 'LONGVARCHAR',
  longtext  = 'LONGVARCHAR',
  mediumtext = 'LONGVARCHAR',
  datetime  = 'TIMESTAMP',
  timestamp = 'TIMESTAMP',
  date      = 'DATE',
  decimal   = 'DECIMAL',
  numeric   = 'DECIMAL',
  double    = 'DOUBLE',
  float     = 'FLOAT',
  bit       = 'BIT',
  boolean   = 'BIT',
  tinyint   = 'TINYINT',
  smallint  = 'SMALLINT',
  mediumint = 'INTEGER',
  blob      = 'BLOB',
  longblob  = 'BLOB',
  mediumblob = 'BLOB',
}

--- 下划线命名转驼峰: user_name → userName
function M.snake_to_camel(name)
  if not name or name == '' then return name or '' end
  return name:lower():gsub('_(%w)', function(c) return c:upper() end)
end

--- MySQL 类型转 Java 类型
function M.mysql_type_to_java(mysql_type)
  if not mysql_type then return 'Object' end
  local base = mysql_type:lower():match('^(%w+)')
  return mysql_to_java_map[base] or 'Object'
end

--- MySQL 类型转 JDBC 类型
function M.mysql_type_to_jdbc(mysql_type)
  if not mysql_type then return 'VARCHAR' end
  local base = mysql_type:lower():match('^(%w+)')
  return mysql_to_jdbc_map[base] or 'VARCHAR'
end

return M
