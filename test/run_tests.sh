#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

run_spec() {
  local spec="$1"
  echo "==> $spec"
  nvim --headless -u "${HOME}/.config/nvim/init.lua" +"set rtp+=$ROOT" +"lua local ok,err = pcall(dofile, '$ROOT/$spec'); if not ok then print(err); vim.cmd('cquit') else vim.cmd('qa!') end"
}

run_spec "test/mybatis_spec.lua"
run_spec "test/completion_spec.lua"
run_spec "test/jump_spec.lua"
run_spec "test/datasource_spec.lua"
run_spec "test/xml_editing_spec.lua"
run_spec "test/mapper_pair_spec.lua"
run_spec "test/virtual_java_spec.lua"

echo "==> All plugin tests passed!"
