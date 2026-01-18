local autolang = require("autolang")

describe("Autolang Detection", function()
    -- Helper para criar buffer temporário
    local function setup_buffer(filetype, lines)
        local buf = vim.api.nvim_create_buf(true, false)
        -- vim.api.nvim_buf_set_option(buf, "buftype", "")
        vim.bo.buftype = ""

        -- CORREÇÃO E95: Gera um nome único para cada buffer usando o tempo
        local unique_name = "teste_autolang_" .. filetype .. "_" .. tostring(vim.loop.hrtime())
        vim.api.nvim_buf_set_name(buf, unique_name)

        -- vim.api.nvim_buf_set_option(buf, "filetype", filetype)
        vim.bo.filetype = filetype
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        vim.api.nvim_set_current_buf(buf)

        -- Força o parser do Tree-sitter
        if pcall(require, "nvim-treesitter") then
            local ok, parser = pcall(vim.treesitter.get_parser, buf, filetype)
            if ok and parser then
                parser:parse()
            end
        end

        return buf
    end

    before_each(function()
        vim.opt.spelllang = "en"

        -- CORREÇÃO PRINCIPAL:
        -- Forçamos o auto_detect = true apenas na memória durante o teste
        -- para que a função detect_and_set não aborte imediatamente.
        autolang.opts.auto_detect = true
    end)

    it("should detect English in Markdown prose", function()
        setup_buffer("markdown", {
            "The quick brown fox jumps over the lazy dog.",
            "This is a standard english sentence used for testing.",
            "Algorithm performance is crucial here.",
        })

        autolang.detect_and_set()

        assert.are.same("en", vim.bo.spelllang)
    end)

    it("should detect Portuguese in Python comments (ignoring code)", function()
        setup_buffer("python", {
            "import os",
            "def funcao_complexa(x):",
            "    # A função: processamento de dados e alocação",
            "    # Não devemos esquecer das exceções e condições",
            "    # Isso garante que a acentuação e a cedilha funcionem",
            "    return True",
        })

        autolang.detect_and_set()

        assert.are.same("pt_br", vim.bo.spelllang)
    end)

    it("should detect Chinese via Unicode Script (Fail-Fast)", function()
        setup_buffer("text", {
            "你好，世界。这是一个测试文本。",
            "我们正在测试语言检测插件的功能。",
            "Unicode 范围检测应该非常快速。",
        })

        autolang.detect_and_set()

        -- Confirme se no seu config.lua 'zh' mapeia para 'cjk'
        -- Se falhar, verifique se está mapeado para 'zh'
        assert.are.same("cjk", vim.bo.spelllang)
    end)

    it("should fallback/ignore ambiguous short text", function()
        setup_buffer("text", { "Short" })

        vim.bo.spelllang = "en"
        autolang.detect_and_set()

        -- Como é muito curto, ele deve abortar e manter o 'en'
        assert.are.same("en", vim.bo.spelllang)
    end)
end)
