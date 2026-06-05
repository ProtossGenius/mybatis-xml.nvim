# mybatis-xml.nvim

A powerful, modern Neovim plugin written in Lua for MyBatis Mapper.xml development. It enhances editing, navigation, completion, database schema synchronization, and integrates with `nvim-jdtls` using virtual Java files to provide robust type checking and auto-completion.

## Features

- **Bidirectional Navigation**: Fast jumps between `Mapper.java` interface methods and corresponding XML statements (`<select>`, `<insert>`, etc.) using standard `gf` or `<C-]>`.
- **Abstract Method Generation**: Instantly generate the matching XML statement block (with inferred `parameterType` and `resultType`) when jumping from a new Java method to a non-existent XML statement.
- **Smart Completion (`omnifunc`)**:
  - Context-aware completions for `#{}` and `${}` parameters.
  - MyBatis tags attribute completions.
  - Cache-backed class FQN autocompletion.
  - ResultMap IDs and SQL statement refids autocompletion.
- **Virtual Java Class Support**: Automatically generates virtual Java classes representing XML mappers in the background. This allows `jdtls` to parse parameters, type check statements, and provide autocomplete.
- **Database Schema Sync**: Pulls table schemas from your datasource to verify and append missing fields in `resultMap` and Java Model classes (supporting lombok `@Data` and getter/setter generation).
- **XML Tag Renaming**: Pair-renaming for XML tags that handles multi-line declarations and SQL comparison operators safely.
- **MyBatis Snippets**: Fully-loaded snippets for select/insert/update/delete/foreach/resultMap tags, out of the box.

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'ProtossGenius/mybatis-xml.nvim',
  ft = { 'xml', 'java' },
  dependencies = {
    'mfussenegger/nvim-jdtls',
    'L3MON4D3/LuaSnip', -- optional, for snippets
  },
  config = function()
    require('mybatis-xml').setup({
      -- Enable / Disable features
      auto_complete = true,
      snippets = true,
      tag_sync = true,
      datasource = {
        enabled = true,
      },
      virtual_java = {
        enabled = true,
        dir = '.mybatis-xml-nvim',
      },
      log_level = 'INFO', -- 'DEBUG' to troubleshoot
    })
  end,
}
```

## Keymaps

The plugin automatically registers buffer-local keymaps for Mapper Java and XML files:

### In `Mapper.java` / `Mapper.xml`
- `gf` or `<C-]>`: Jump mapper pair (Java method $\leftrightarrow$ XML tag).
- `gF`: Jump mapper pair and open in vertical split.
- `<leader>li`: Jump pair.
- `<leader>lD`: Jump pair in vertical split.

### In `Mapper.xml`
- `{` (after `#` or `$`): Triggers parameter autocompletion.
- `<C-x><C-o>` or `<leader>lp`: Manually trigger parameter/XML autocomplete.

## Database Synchronization

Configure datasource details in a `.nvim-datasource.json` file in your project root.

You can generate the template by running:
```vim
:DatasourceConfig
```

To sync changes:
```vim
:DatasourceSync
```

## Testing

Run tests locally within the plugin directory:
```bash
./test/run_tests.sh
```

## License

MIT
