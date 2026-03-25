local M = {}

function M.check()
	local health = vim.health
	health.start("Autolang.nvim Diagnostics")

	-- Check 1: Tree-sitter
	local query = vim.treesitter.query.get('lua', 'autolang')
	if query then
		health.ok('Tree-sitter queries found')
	else
		health.error('Tree-sitter queries not found.', 'Add the autolang repository to the runtimepath.')
	end

	-- Check 2: Trigrams existence
	local en_exists = pcall(require, "autolang.trigrams.en")
	if en_exists then
		health.ok("Trigram data files found.")
	else
		health.error("Trigram data files missing.', 'Make sure 'lua/autolang/trigrams/' is populated.")
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
