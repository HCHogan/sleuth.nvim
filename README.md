# sleuth.nvim

A Lua port of Tim Pope's sleuth.vim for Neovim

## Installation

lazy.nvim:

```lua
return {
  'HCHogan/sleuth.nvim',
  opts = {
    modeline       = true,
    editorconfig   = true,
    neighbor_limit = 8,
    max_lines      = 256,
  }
}
```
