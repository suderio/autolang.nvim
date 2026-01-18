# Diretório onde as dependências de teste ficarão
TEST_DEPS_DIR = .tests

# URLs dos repositórios
PLENARY_URL = https://github.com/nvim-lua/plenary.nvim
TREESITTER_URL = https://github.com/nvim-treesitter/nvim-treesitter

test: prepare
	@echo "===> Running Tests..."
	nvim --headless --noplugin -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"

prepare:
	@mkdir -p $(TEST_DEPS_DIR)
	@if [ ! -d "$(TEST_DEPS_DIR)/plenary.nvim" ]; then \
		echo "===> Cloning plenary.nvim..."; \
		git clone --depth 1 $(PLENARY_URL) $(TEST_DEPS_DIR)/plenary.nvim; \
	fi
	@if [ ! -d "$(TEST_DEPS_DIR)/nvim-treesitter" ]; then \
		echo "===> Cloning nvim-treesitter..."; \
		git clone --depth 1 $(TREESITTER_URL) $(TEST_DEPS_DIR)/nvim-treesitter; \
	fi

clean:
	rm -rf $(TEST_DEPS_DIR)
