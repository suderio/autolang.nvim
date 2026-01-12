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

    -- Mapeamento do código detectado para o 'spelllang' do vim
    -- É aqui que diferenciamos pt_BR de pt_PT
    lang_mapping = {
        en = "en_us",
        pt = "pt_br", -- Altere para pt_pt se preferir
        es = "es",
        fr = "fr",
        de = "de",
        zh = "cjk",   -- Ou nil, já que spellcheck em chinês é raro
    },
}

return M
