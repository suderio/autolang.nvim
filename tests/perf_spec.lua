local autolang = require("autolang")

describe("Autolang Performance", function()
    local function benchmark(name, filetype, content_generator)
        local lines = content_generator()
        local buf = vim.api.nvim_create_buf(false, true)
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

    --    it("benchmark: Python File with Code and Comments", function()
    --        benchmark("Python Mixed", "python", function()
    --            local t = {}
    --            for _ = 1, 200 do
    --                table.insert(t, "def complex_function(arg):")
    --                table.insert(t, "    # This is a comment explaining the logic")
    --                table.insert(t, "    return arg * 2")
    --            end
    --            return t
    --        end)
    --    end)
end)

describe("Autolang Performance", function()
    -- Função auxiliar para medir tempo
    local function measure(name, task)
        local start = vim.loop.hrtime()
        task()
        local end_time = vim.loop.hrtime()
        local ms = (end_time - start) / 1e6
        print(string.format("PERF [%s]: %.4f ms", name, ms))
        return ms
    end

    -- Cria um arquivo real no disco para simular o cenário real
    local function create_heavy_org_file()
        local filename = vim.fn.tempname() .. ".org"
        local f = io.open(filename, "w")

        -- Gera 4.000 linhas de conteúdo Org complexo
        -- Estrutura complexa força o Tree-sitter a trabalhar mais
        if f ~= nil then
            f:write("#+TITLE: Heavy Performance Test\n")
            f:write("#+AUTHOR: Autolang Benchmark\n\n")

            for i = 1, 500 do
                f:write("* Heading Level 1 - Section " .. i .. "\n")
                f:write(":PROPERTIES:\n:ID: " .. i .. "\n:CREATED: today\n:END:\n")
                f:write("Here is some standard text to detect language.\n")
                f:write("Português do Brasil misturado com English text.\n")
                f:write("** Subheading Level 2\n")
                f:write("#+BEGIN_SRC python\nprint('code block ignore')\n#+END_SRC\n\n")
            end

            f:close()
        end

        return filename
    end

    it("benchmark: Huge Org File from Disk (Regression Test)", function()
        local filename = create_heavy_org_file()

        -- Abre o arquivo (edit)
        vim.cmd("edit " .. filename)
        local buf = vim.api.nvim_get_current_buf()

        -- Habilita detecção para o teste
        autolang.opts.auto_detect = true

        -- MEDIÇÃO CRÍTICA
        -- Se a otimização de "limit stop_row" funcionou, isso deve ser < 10ms.
        -- Se falhar, isso levará > 100ms.
        local duration = measure("Heavy Org File (500 blocks)", function()
            autolang.detect_and_set()
        end)

        -- Cleanup
        vim.api.nvim_buf_delete(buf, { force = true })
        os.remove(filename)

        -- Asserção de Performance
        -- Com a correção, deve ser muito rápido. Sem a correção, falharia aqui.
        assert.is_true(duration < 20, "Org detection is too slow! Took: " .. duration .. "ms")
    end)
end)
