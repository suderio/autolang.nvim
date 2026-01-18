local autolang = require("autolang")

describe("Autolang Performance", function()
    local function benchmark(name, filetype, content_generator)
        local lines = content_generator()
        local buf = vim.api.nvim_create_buf(false, true)
        -- vim.api.nvim_buf_set_option(buf, "filetype", filetype)
        vim.bo.filetype = filetype
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        vim.api.nvim_set_current_buf(buf)

        -- Garante que o parser do Treesitter está carregado antes de medir
        -- para não medir o tempo de I/O do parser
        if pcall(require, "nvim-treesitter") then
            vim.treesitter.get_parser(buf, filetype):parse()
        end
        autolang.opts.auto_detect = true
        local start = vim.uv.hrtime()
        autolang.detect_and_set()
        local end_time = vim.uv.hrtime()

        local duration_ms = (end_time - start) / 1e6
        print(string.format("PERF [%s]: %.4f ms", name, duration_ms))

        -- Asserção de Performance (Opcional: Falhar se for muito lento)
        -- Ex: Deve rodar em menos de 5ms
        assert.is_true(duration_ms < 15, "Detection took too long: " .. duration_ms .. "ms")

        vim.api.nvim_buf_delete(buf, { force = true })
    end

    it("benchmark: Large Markdown File (Text Heavy)", function()
        benchmark("Markdown 500 lines", "markdown", function()
            local t = {}
            for _ = 1, 500 do
                table.insert(
                    t,
                    "This is a repeated sentence to simulate a large block of english text used for performance testing."
                )
            end
            return t
        end)
    end)

    it("benchmark: Python File with Code and Comments", function()
        benchmark("Python Mixed", "python", function()
            local t = {}
            for _ = 1, 200 do
                table.insert(t, "def complex_function(arg):")
                table.insert(t, "    # This is a comment explaining the logic")
                table.insert(t, "    return arg * 2")
            end
            return t
        end)
    end)
end)
