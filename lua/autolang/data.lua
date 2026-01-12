local M = {}

-- Stop words para detecção de frequência.
-- Usamos espaços em volta para evitar falsos positivos em línguas latinas (ex: " a " vs "casa").
M.languages = {
    en = { " the ", " be ", " to ", " of ", " and ", " a ", " in ", " that ", " have ", " i " },
    pt = { " de ", " a ", " o ", " que ", " e ", " do ", " da ", " em ", " um ", " para ", " não " },
    es = { " de ", " la ", " que ", " el ", " en ", " y ", " a ", " los ", " del ", " se ", " por " },
    fr = { " de ", " la ", " le ", " et ", " les ", " des ", " en ", " un ", " du ", " une ", " que " },
    de = { " der ", " die ", " und ", " in ", " den ", " von ", " zu ", " das ", " mit ", " sich ", " des " },
    zh = { "的", "一", "是", "不", "了", "人", "我", "在", "有", "他" }
}

return M
