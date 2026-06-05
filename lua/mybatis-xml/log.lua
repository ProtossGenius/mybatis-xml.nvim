--- mybatis-xml.nvim 日志模块
--- 统一的日志输出接口，使用 vim.notify 带前缀

local M = {}

local PREFIX = '[mybatis-xml] '
local LEVELS = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }
M._level = LEVELS.INFO

--- 设置日志级别
---@param level string 'DEBUG'|'INFO'|'WARN'|'ERROR'
function M.set_level(level)
  M._level = LEVELS[level:upper()] or LEVELS.INFO
end

--- 输出 DEBUG 级别日志
---@param fmt string
---@param ... any
function M.debug(fmt, ...)
  if LEVELS.DEBUG >= M._level then
    local msg = string.format(fmt, ...)
    vim.notify(PREFIX .. msg, vim.log.levels.DEBUG)
  end
end

--- 输出 INFO 级别日志
---@param fmt string
---@param ... any
function M.info(fmt, ...)
  if LEVELS.INFO >= M._level then
    local msg = string.format(fmt, ...)
    vim.notify(PREFIX .. msg, vim.log.levels.INFO)
  end
end

--- 输出 WARN 级别日志
---@param fmt string
---@param ... any
function M.warn(fmt, ...)
  if LEVELS.WARN >= M._level then
    local msg = string.format(fmt, ...)
    vim.notify(PREFIX .. msg, vim.log.levels.WARN)
  end
end

--- 输出 ERROR 级别日志
---@param fmt string
---@param ... any
function M.error(fmt, ...)
  if LEVELS.ERROR >= M._level then
    local msg = string.format(fmt, ...)
    vim.notify(PREFIX .. msg, vim.log.levels.ERROR)
  end
end

return M
