--- mybatis-xml.nvim XML 标签配对重命名
--- 编辑开始标签时自动同步关闭标签
--- 修复：使用行号+位置追踪而非名称匹配，解决重命名后无法定位的 bug

local M = {}

local state = {}

local function tokenize(bufnr)
  local tokens = {}
  local stack = {}
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, '\n')

  local line_starts = { 1 }
  for i = 1, #content do
    if content:sub(i, i) == '\n' then
      line_starts[#line_starts + 1] = i + 1
    end
  end

  local function get_pos(byte_idx)
    local line = 1
    for i = 2, #line_starts do
      if byte_idx < line_starts[i] then
        break
      end
      line = i
    end
    local col = byte_idx - line_starts[line] + 1
    return line, col
  end

  local search_from = 1
  while true do
    local start_idx, end_idx, closing, name, attrs = content:find('<(/?)([%w_:%.%-]+)([^>]*)>', search_from)
    if not start_idx then
      break
    end

    local first_char = name:sub(1, 1)
    if first_char:match('[%a_:]') then
      local line, col = get_pos(start_idx)
      local name_start_idx = start_idx + (closing == '/' and 2 or 1)
      local _, name_start_col = get_pos(name_start_idx)

      local token = {
        line = line,
        name = name,
        name_start = name_start_col,
        name_end = name_start_col + #name - 1,
        kind = closing == '/' and 'end' or 'start',
      }

      local attr_tail = attrs or ''
      if token.kind == 'start' and attr_tail:match('/%s*$') then
        token.kind = 'self'
      end

      tokens[#tokens + 1] = token
      local token_index = #tokens

      if token.kind == 'start' then
        stack[#stack + 1] = token_index
      elseif token.kind == 'end' then
        local top_index = stack[#stack]
        if top_index and tokens[top_index].name == token.name then
          tokens[top_index].pair = token_index
          token.pair = top_index
          table.remove(stack)
        end
      end
    end

    search_from = end_idx + 1
  end

  return tokens
end


local function find_token_at(tokens, line_nr, col)
  for index, token in ipairs(tokens) do
    if token.line == line_nr then
      local start_col = token.name_start - 1
      local end_col = token.name_end - 1
      if col >= start_col and col <= end_col then
        return token, index
      end
    end
  end
end

--- 按行号和大致位置查找 token（不依赖名称匹配）
local function find_token_near(tokens, line_nr, kind, name_start)
  local best_token
  local best_distance

  for _, token in ipairs(tokens) do
    if token.line == line_nr and token.kind == kind then
      local distance = math.abs(token.name_start - name_start)
      if not best_distance or distance < best_distance then
        best_token = token
        best_distance = distance
      end
    end
  end

  return best_token
end

local function session_for(bufnr)
  if not state[bufnr] then
    state[bufnr] = {}
  end
  return state[bufnr]
end

local function capture_session(bufnr, preserve_existing)
  local session = session_for(bufnr)
  if session.updating then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local tokens = tokenize(bufnr)
  local token, _ = find_token_at(tokens, cursor[1], cursor[2])
  if not token or not token.pair then
    if not preserve_existing then
      session.edit = nil
    end
    return
  end

  local pair = tokens[token.pair]
  if not pair or pair.name ~= token.name then
    session.edit = nil
    return
  end

  session.edit = {
    line = token.line,
    kind = token.kind,
    name_start = token.name_start,
    original_name = token.name,
    pair_line = pair.line,
    pair_name_start = pair.name_start,
    pair_name_end = pair.name_end,
    pair_kind = pair.kind,
    pair_original_name = pair.name,
  }
end

local function apply_pair_rename(bufnr)
  local session = session_for(bufnr)
  local edit = session.edit
  if not edit or session.updating then
    return
  end

  -- 重新 tokenize 以获取编辑后的状态
  local tokens = tokenize(bufnr)

  -- 用行号+位置查找编辑后的 token（不再依赖名称匹配！）
  local token = find_token_near(tokens, edit.line, edit.kind, edit.name_start)
  if not token or token.kind == 'self' then
    session.edit = nil
    return
  end

  -- 用行号+位置查找配对 token
  local pair = find_token_near(tokens, edit.pair_line, edit.pair_kind, edit.pair_name_start)
  if not pair then
    session.edit = nil
    return
  end

  -- 检查配对 token 的名字是否仍然是原始名字（没被用户手动改过）
  if pair.name ~= edit.pair_original_name then
    session.edit = nil
    return
  end

  -- 如果编辑后的名字和原始名字相同，或者和配对的名字已经相同，则不需要操作
  if token.name == edit.original_name or token.name == pair.name then
    session.edit = nil
    return
  end

  -- 执行重命名
  session.updating = true
  vim.api.nvim_buf_set_text(
    bufnr,
    pair.line - 1,
    pair.name_start - 1,
    pair.line - 1,
    pair.name_end,
    { token.name }
  )
  session.updating = false
  session.edit = nil
end

function M.setup()
  local group = vim.api.nvim_create_augroup('MybatisXmlTagSync', { clear = true })

  vim.api.nvim_create_autocmd('InsertEnter', {
    group = group,
    pattern = '*',
    callback = function(args)
      if vim.bo[args.buf].filetype == 'xml' then
        capture_session(args.buf, true)
      end
    end,
  })

  vim.api.nvim_create_autocmd('CursorMoved', {
    group = group,
    pattern = '*',
    callback = function(args)
      if vim.bo[args.buf].filetype == 'xml' then
        capture_session(args.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd('InsertLeave', {
    group = group,
    pattern = '*',
    callback = function(args)
      if vim.bo[args.buf].filetype == 'xml' then
        apply_pair_rename(args.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd('BufWipeout', {
    group = group,
    pattern = '*',
    callback = function(args)
      state[args.buf] = nil
    end,
  })
end

M._test = {
  tokenize = tokenize,
  find_token_at = find_token_at,
  find_token_near = find_token_near,
}

return M
