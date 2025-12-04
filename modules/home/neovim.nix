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
        plenary-nvim

        a-vim
        dracula-nvim
        gitlinker-nvim # after plenary-nvim
        telescope-nvim
      ];
      extraLuaConfig = ''
        -- Early mapleader for default bindings
        vim.g.mapleader = ","

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
                  "--exclude=.git",
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
                "--glob=!.git",
            },
          },
        })

        -- gitlinker
        require('gitlinker').setup({
          callbacks = {
            ["ssh.gitea.hillion.co.uk"] = function(url_data)
              url_data.host = "gitea.hillion.co.uk"
              return
                  require('gitlinker.hosts').get_gitea_type_url(url_data)
            end
          },
        })

        -- LSP Configuration
        -- Check if a command is available in PATH
        local function is_executable(cmd)
          return vim.fn.executable(cmd) == 1
        end

        -- Set up keybindings when any LSP attaches (shared across all LSP servers)
        vim.api.nvim_create_autocmd('LspAttach', {
          callback = function(args)
            local bufnr = args.buf
            -- Enable completion triggered by <c-x><c-o>
            vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')

            -- Keybindings for LSP functions
            local bufopts = { noremap=true, silent=true, buffer=bufnr }
            vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, bufopts)
            vim.keymap.set('n', 'gd', vim.lsp.buf.definition, bufopts)
            vim.keymap.set('n', 'K', vim.lsp.buf.hover, bufopts)
            vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, bufopts)
            vim.keymap.set('n', '<C-k>', vim.lsp.buf.signature_help, bufopts)
            vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, bufopts)
            vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, bufopts)
            vim.keymap.set('n', 'gr', vim.lsp.buf.references, bufopts)
          end
        })

        -- Configure basedpyright if available
        if is_executable('basedpyright-langserver') then
          vim.lsp.config.basedpyright = {
            cmd = { 'basedpyright-langserver', '--stdio' },
            filetypes = { 'python' },
            root_markers = { 'pyproject.toml', 'setup.py', 'setup.cfg', 'requirements.txt', 'Pipfile', 'pyrightconfig.json' },
            settings = {
              basedpyright = {
                analysis = {
                  autoSearchPaths = true,
                  useLibraryCodeForTypes = true,
                  diagnosticMode = "openFilesOnly",
                }
              }
            }
          }

          -- Enable basedpyright for Python files
          vim.api.nvim_create_autocmd('FileType', {
            pattern = 'python',
            callback = function()
              vim.lsp.enable('basedpyright')
            end
          })
        end

        -- osc52 keyboard
        vim.g.clipboard = {
          name = 'OSC 52',
          copy = {
            ['+'] = require('vim.ui.clipboard.osc52').copy('+'),
            ['*'] = require('vim.ui.clipboard.osc52').copy('*'),
          },
          paste = {
            ['+'] = require('vim.ui.clipboard.osc52').paste('+'),
            ['*'] = require('vim.ui.clipboard.osc52').paste('*'),
          },
        }

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
