-- tests/minimal_init.lua

vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false

local cwd = vim.loop.cwd()
local test_dir = cwd .. "/.tests"

-- Função auxiliar para carregar plugins
local function load_plugin(name)
    local path = test_dir .. "/" .. name
    -- Adiciona ao RTP (Neovim)
    vim.opt.rtp:prepend(path)
    -- Adiciona ao Package Path (Lua) para garantir require
    package.path = package.path .. ";" .. path .. "/lua/?.lua;" .. path .. "/lua/?/init.lua"
end

print("==> Configurando ambiente de teste...")

-- 1. Carrega Caminhos
load_plugin("plenary.nvim")
load_plugin("nvim-treesitter")
vim.opt.rtp:prepend(cwd) -- Autolang

-- 2. CORREÇÃO DO ERRO E492: Carrega os comandos do Plenary
-- Isso garante que :PlenaryBustedDirectory esteja disponível
vim.cmd("runtime! plugin/plenary.vim")

-- 3. Configura Treesitter
-- Tenta carregar configs (padrão) ou config (caso seu clone esteja estranho)
local ok_ts, configs = pcall(require, "nvim-treesitter.configs")
if not ok_ts then
    ok_ts, configs = pcall(require, "nvim-treesitter.config")
end

if ok_ts then
    print("==> Setup Treesitter...")
    configs.setup({
        ensure_installed = { "lua", "python", "markdown", "query", "org" },
        sync_install = true,
        highlight = { enable = true },
    })
else
    print("AVISO: Não foi possível carregar nvim-treesitter.configs. Os testes de TS podem falhar.")
end

-- 4. Setup Autolang
print("==> Setup Autolang...")
require("autolang").setup({ auto_detect = false, interactive = false })
