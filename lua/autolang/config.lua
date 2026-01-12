local M = {}

M.defaults = {
    -- Habilita a detecção automática
    auto_detect = true,

    -- Quantas linhas do topo do arquivo analisar (performance)
    lines_to_check = 50,

    -- Modo interativo: se true, pergunta antes de mudar
    interactive = false,

    -- Lista de línguas a considerar (nil = todas disponíveis em data.lua)
    -- Exemplo para limitar: { "en", "pt" }
    limit_languages = nil,

    -- IMPORTANTE:
    -- As chaves (Lado Esquerdo) devem corresponder EXATAMENTE ao nome do arquivo
    -- na pasta 'lua/autolang/trigrams/' (sem o .lua).
    -- Os valores (Lado Direito) são o 'set spelllang=...' do Vim.
    lang_mapping = {
        -- Arquivos de Trigramas (Latinos)
        en    = "en",    -- Carrega: lua/autolang/trigrams/en.lua
        pt_BR = "pt_br",    -- Carrega: lua/autolang/trigrams/pt_BR.lua
        es    = "es",       -- Carrega: lua/autolang/trigrams/es.lua
        fr    = "fr",       -- Carrega: lua/autolang/trigrams/fr.lua
        de    = "de",       -- Carrega: lua/autolang/trigrams/de.lua

        -- Detecção via Script (Unicode)
        -- Estas chaves são usadas quando a detecção de script (CJK/Cirílico) dispara.
        -- Elas NÃO precisam de arquivos na pasta trigrams, pois são ignoradas no loop de distância.
        zh    = "cjk",      -- Chinês (Detectado por Range Unicode)
        ru    = "ru",       -- Russo (Detectado por Range Unicode)
    },
}

return M
