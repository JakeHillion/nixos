{ pkgs, lib, config, ... }:

let
  cfg = config.custom.home.neovim;
in
{
  options.custom.home.neovim = {
    enable = lib.mkEnableOption "neovim";
  };

  config = lib.mkIf config.custom.home.neovim.enable {
    home-manager.users."${config.custom.user}".programs.neovim = {
      enable = true;

      viAlias = true;
      vimAlias = true;

      plugins = with pkgs.vimPlugins; [
        a-vim
        dracula-nvim
        git-blame-nvim
        telescope-nvim
      ];
      extraLuaConfig = ''
        -- Logical options
        vim.opt.splitright = true
        vim.opt.splitbelow = true
        vim.opt.ignorecase = true
        vim.opt.smartcase = true

        vim.opt.expandtab = true
        vim.opt.tabstop = 2
        vim.opt.shiftwidth = 2

        -- Appearance
        vim.cmd[[colorscheme dracula-soft]]

        vim.opt.number = true
        vim.opt.relativenumber = true

        -- Telescope
        require('telescope').setup({
          pickers = {
            find_files = {
              find_command = {
                  "${pkgs.fd}/bin/fd",
                  "--type=f",
                  "--strip-cwd-prefix",
                  "--no-require-git",
                  "--hidden",
                  "--exclude=.sl",
              },
            },
          },
          defaults = {
            vimgrep_arguments = {
                "${pkgs.ripgrep}/bin/rg",
                "--color=never",
                "--no-heading",
                "--with-filename",
                "--line-number",
                "--column",
                "--smart-case",
                "--no-require-git",
                "--hidden",
                "--glob=!.sl",
            },
          },
        })

        --  Key bindings
        vim.g.mapleader = ","

        --- Key bindings: Telescope
        local telescope_builtin = require('telescope.builtin')
        vim.keymap.set('n', '<leader>ff', telescope_builtin.find_files, {})
        vim.keymap.set('n', '<leader>fg', telescope_builtin.live_grep, {})
        vim.keymap.set('n', '<leader>fb', telescope_builtin.buffers, {})
        vim.keymap.set('n', '<leader>fh', telescope_builtin.help_tags, {})
      '';
    };
  };
}
