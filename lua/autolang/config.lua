local M = {}

M.defaults = {
    auto_detect = true,

    lines_to_check = 50,

    interactive = false,

    -- Exemple: { "en", "pt" }
    limit_languages = nil,

    -- Achtung:
    -- Keys must be the name of the trigram file
    -- inside 'lua/autolang/trigrams/' (without .lua extension).
    -- Values are the Vim's 'set spelllang=...'.
    lang_mapping = {
        -- Latin trigram files
        en = "en", -- Loads: lua/autolang/trigrams/en.lua
        pt_BR = "pt_br", -- Loads: lua/autolang/trigrams/pt_BR.lua
        es = "es", -- Loads: lua/autolang/trigrams/es.lua
        fr = "fr", -- Loads: lua/autolang/trigrams/fr.lua
        de = "de", -- Loads: lua/autolang/trigrams/de.lua
        af = "af",
        ar = "ar",
        az = "az",
        bg = "bg",
        ca = "ca",
        ceb = "ceb",
        cs = "cs",
        cy = "cy",
        da = "da",
        et = "et",
        eu = "eu",
        fa = "fa",
        fi = "fi",
        ha = "ha",
        haw = "haw",
        hi = "hi",
        hr = "hr",
        hu = "hu",
        id = "id",
        is = "is",
        it = "it",
        kk = "kk",
        ky = "ky",
        la = "la",
        lt = "lt",
        lv = "lv",
        mk = "mk",
        mn = "mn",
        nb = "nb",
        ne = "ne",
        nl = "nl",
        nr = "nr",
        nso = "nso",
        pl = "pl",
        ps = "ps",
        pt = "pt",
        pt_PT = "pt_pt",
        ro = "ro",
        sk = "sk",
        sl = "sl",
        so = "so",
        sq = "sq",
        sr = "sr",
        ss = "ss",
        st = "st",
        sv = "sv",
        sw = "sw",
        tlh = "tlh",
        tl = "tl",
        tn = "tn",
        tr = "tr",
        ts = "ts",
        uk = "uk",
        ur = "ur",
        uz = "uz",
        ve = "ve",
        xh = "xh",
        zu = "zu",
        -- Script detection (Unicode)
        -- These are used when script detection (CJK/Cirílico) is enough.
        -- They do not need to be inside the trigrams directory.
        zh = "cjk", -- Chinese
        ru = "ru", -- Russian
    },
}

return M
