local M = {}

function M.check()
    local health = vim.health
    health.start("Autolang.nvim Diagnostics")

    -- Check 1: Tree-sitter
    if pcall(require, "nvim-treesitter") then
        health.ok("nvim-treesitter is installed.")
    else
        health.warn("nvim-treesitter not found. Falling back to raw text analysis (less accurate).")
    end

    -- Check 2: Trigrams existence
    local en_exists = pcall(require, "autolang.trigrams.en")
    if en_exists then
        health.ok("Trigram data files found.")
    else
        health.error("Trigram data files missing. Make sure 'lua/autolang/trigrams/' is populated.")
    end

    -- Check 3: Basic configuration
    local config_ok, config = pcall(require, "autolang.config")
    if config_ok and config.defaults.lang_mapping then
         health.ok("Configuration loaded successfully.")
    else
         health.error("Failed to load default configuration.")
    end
end

return M
