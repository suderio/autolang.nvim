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

describe("Autolang Comprehensive Suite", function()
    -- 1. Setup Helper (Igual ao que já validamos e sabemos que funciona)
    local function setup_buffer(filetype, lines)
        local buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_option(buf, "buftype", "")

        local unique_name = "test_" .. filetype .. "_" .. tostring(vim.loop.hrtime())
        vim.api.nvim_buf_set_name(buf, unique_name)

        vim.api.nvim_buf_set_option(buf, "filetype", filetype)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        vim.api.nvim_set_current_buf(buf)

        -- Força carregamento do Tree-sitter se disponível
        if pcall(require, "nvim-treesitter") then
            -- Tenta obter o parser, se falhar (ex: cobol não instalado), ignora silenciosamente
            local ok, parser = pcall(vim.treesitter.get_parser, buf, filetype)
            if ok and parser then
                parser:parse()
            end
        end

        return buf
    end

    before_each(function()
        vim.opt.spelllang = "en" -- Reset para inglês antes de cada teste
        autolang.opts.auto_detect = true -- Força detecção ativa
    end)

    -- 2. Tabela de Casos de Teste (Data Driven)
    -- Mapeia: Filetype -> Conteúdo -> Resultado Esperado
    local test_cases = {
        -- === PORTUGUÊS (Usa Heurística ç/ã/õ para diferenciar de ES) ===
        {
            ft = "python",
            lang = "pt_br",
            text = { "# Função de anotação e processamento", "# Garante a execução correta da ação" },
        },
        {
            ft = "lua",
            lang = "pt_br",
            text = { "-- Configuração padrão da aplicação", "-- Não permite edição manual da seção" },
        },
        {
            ft = "sql",
            lang = "pt_br",
            text = { "-- Seleção de usuários ativos", "-- Otimização da junção de tabelas" },
        },
        { ft = "html", lang = "pt_br", text = { "", "<p>Parágrafo com descrição</p>" } },
        {
            ft = "txt",
            lang = "pt_br",
            text = { "Este é um arquivo de texto simples.", "Contém anotações sobre a reunião de amanhã." },
        },

        -- === ESPANHOL (Usa Heurística ñ/¿/¡ para diferenciar de PT) ===
        {
            ft = "javascript",
            lang = "es",
            text = { "// Función para calcular el tamaño", "// ¿El valor es numérico? Verificación aquí." },
        },
        {
            ft = "typescript",
            lang = "es",
            text = { "// La configuración del año próximo", "// Diseño de la interfaz de usuario" },
        },
        {
            ft = "cs",
            lang = "es",
            text = { "// Clase principal para el diseño", "// Comprobación de la contraseña del usuario" },
        },
        {
            ft = "php",
            lang = "es",
            text = { "// Conexión a la base de datos", "// La contraseña del administrador" },
        },

        -- === INGLÊS (Padrão Trigramas) ===
        {
            ft = "rust",
            lang = "en",
            text = { "// Main entry point of the application", "// Handles memory allocation safely" },
        },
        {
            ft = "go",
            lang = "en",
            text = { "// Returns the resulting error structure", "// Checks if the server is available" },
        },
        {
            ft = "c",
            lang = "en",
            text = { "/* Standard input output library inclusion */", "/* Define constants for buffer size */" },
        },
        {
            ft = "cpp",
            lang = "en",
            text = { "// Template class for data processing", "// Standard vector implementation" },
        },
        {
            ft = "java",
            lang = "en",
            text = { "// Public static void main method", "// Abstract factory implementation pattern" },
        },
        {
            ft = "kotlin",
            lang = "en",
            text = { "// Data class representing the user", "// Extension function for string manipulation" },
        },
        {
            ft = "swift",
            lang = "en",
            text = { "// View controller lifecycle events", "// Delegate pattern implementation details" },
        },
        {
            ft = "scala",
            lang = "en",
            text = { "// Implicit conversion for types", "// Pattern matching on case classes" },
        },
        {
            ft = "zig",
            lang = "en",
            text = { "/// Documentation for the main struct", "/// Allocator interface implementation" },
        },

        -- === LINGUAGENS FUNCIONAIS / SCRIPTING (Inglês Técnico) ===
        {
            ft = "ruby",
            lang = "en",
            text = { "# Returns the active record instance", "# Validates presence of the attribute" },
        },
        {
            ft = "elixir",
            lang = "en",
            text = { "# Module documentation and specs", "# Asynchronous task supervision tree" },
        },
        {
            ft = "haskell",
            lang = "en",
            text = { "-- Pure function without side effects", "-- Monadic composition pipeline" },
        },
        {
            ft = "clojure",
            lang = "en",
            text = { ";; Defines the main namespace", ";; Immutable data structure manipulation" },
        },
        { ft = "lisp", lang = "en", text = { ";; Recursive function definition", ";; List processing utility" } },
        {
            ft = "ocaml",
            lang = "en",
            text = { "(* Pattern matching on list head *)", "(* Recursive tail call optimization *)" },
        },
        {
            ft = "fsharp",
            lang = "en",
            text = { "// Discriminated union definition", "// Pipe forward operator usage" },
        },
        {
            ft = "erlang",
            lang = "en",
            text = { "% Server gen_server implementation", "% Message passing concurrency model" },
        },

        -- === DATA & MATH (Inglês Técnico) ===
        {
            ft = "r",
            lang = "en",
            text = { "# Statistical analysis of the dataset", "# Linear regression model fitting" },
        },
        {
            ft = "julia",
            lang = "en",
            text = { "# Multiple dispatch function definition", "# Numerical computing optimization" },
        },
        {
            ft = "matlab",
            lang = "en",
            text = { "% Matrix multiplication algorithm", "% Signal processing filter design" },
        },
        {
            ft = "perl",
            lang = "en",
            text = { "# Regular expression pattern matching", "# File handle input output processing" },
        },
        {
            ft = "ps1",
            lang = "en",
            text = { "# Windows PowerShell automation script", "# Get process list and filter by name" },
        },

        -- === LEGADO (Inglês Técnico) ===
        {
            ft = "fortran",
            lang = "en",
            text = { "! Subroutine for numerical integration", "! Variable declaration block" },
        },
        { ft = "cobol", lang = "en", text = { "* IDENTIFICATION DIVISION HEADER", "* DATA DIVISION FILE SECTION" } },

        -- === CJK (Chinês/Japonês/Coreano - Detecção por Script Unicode) ===
        {
            ft = "markdown",
            lang = "cjk",
            text = { "你好，世界。这是一个测试。", "这里有一些汉字来测试检测功能。" },
        },
        {
            ft = "org",
            lang = "cjk",
            text = { "* 这是一个标题", "这里有一些内容用于测试 Emacs Org 模式。" },
        },

        -- === CONFIG FILES ===
        { ft = "yaml", lang = "en", text = { "# Configuration for the deployment", "# Docker container settings" } },
        {
            ft = "toml",
            lang = "en",
            text = {
                "# Project metadata definition",
                "# Dependencies version constraints",
                "# Do not write below this line",
            },
        },
        {
            ft = "json",
            lang = "en",
            text = { '"_comment": "Standard JSON does not support comments but some parsers do"' },
        },
    }

    -- 3. Loop Gerador de Testes
    for _, case in ipairs(test_cases) do
        it(string.format("should detect [%s] in [%s] files", case.lang, case.ft), function()
            -- Configura o buffer com o texto do caso de teste
            setup_buffer(case.ft, case.text)

            -- Executa a detecção
            autolang.detect_and_set()

            -- Verifica o resultado
            -- Nota: Verificamos se começa com a língua esperada para lidar com variações (ex: en_us, en_gb)
            local current = vim.bo.spelllang:lower()
            local expected = case.lang:lower()

            -- Lógica especial para 'cjk' que pode ser mapeado para 'zh' dependendo da config do usuário
            -- Mas aqui assumimos o padrão do plugin
            if expected == "cjk" then
                assert.is_true(
                    current == "cjk" or current == "zh",
                    string.format("Expected CJK/ZH but got '%s' in %s", current, case.ft)
                )
            elseif expected == "pt_br" then
                assert.are.same("pt_br", current)
            else
                -- Para inglês, aceitamos 'en', 'en_us', 'en_gb'
                assert.is_true(
                    string.sub(current, 1, 2) == string.sub(expected, 1, 2),
                    string.format("Expected '%s' (prefix) but got '%s' in %s", expected, current, case.ft)
                )
            end
        end)
    end

    -- 4. Teste de Fallback (Arquivo muito pequeno)
    it("should ignore very short text and keep default", function()
        setup_buffer("txt", { "Hi" })
        vim.bo.spelllang = "en"
        autolang.detect_and_set()
        assert.are.same("en", vim.bo.spelllang)
    end)
end)
