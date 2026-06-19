# Render a `TabXTable` to a LaTeX string in the house style:
#   \begin{tabularx}{\textwidth}{lY...Y}
#   double \midrule top/bottom, single \midrule separators, \cmidrule(lr) under
#   grouped headers, full-width \multicolumn note rows.

"""
    to_latex(t::TabXTable) -> String

Render a table to a LaTeX `tabularx` string. (`render`/`write_tex` were renamed
to avoid colliding with Latexify's `render` and TexTables' `write_tex`/`to_tex`.)
"""
function to_latex(t::TabXTable)
    io = IOBuffer()
    if t.float
        println(io, "\\begin{table}[$(t.position)]")
        t.centering && println(io, "  \\centering")
        isempty(t.caption) || println(io, "  \\caption{$(t.caption)}")
        isempty(t.label)   || println(io, "  \\label{$(t.label)}")
    end
    println(io, "\\begin{tabularx}{$(t.width)}{$(t.colspec)}")
    for r in t.rows
        line = _render_row(r, t.ncols)
        isempty(line) || println(io, line)   # a :none rule renders to "" and is skipped
    end
    for note in t.notes
        println(io, "    \\multicolumn{$(t.ncols)}{l}{\\scriptsize \\textit{$(note)}} \\\\")
    end
    println(io, "\\end{tabularx}")
    t.float && println(io, "\\end{table}")
    return String(take!(io))
end

function _render_row(r::TabXRow, ::Int)
    parts = String[]
    for c in r.cells
        if c.multicol || c.span > 1 || c.align != :l
            letter = get(_ALIGN_LETTER, c.align, "l")
            push!(parts, "\\multicolumn{$(c.span)}{$(letter)}{$(c.text)}")
        else
            push!(parts, c.text)
        end
    end
    return "    " * join(parts, " & ") * " \\\\"
end

function _render_row(r::TabXRule, ::Int)
    r.kind === :top       && return "    \\toprule"
    r.kind === :mid       && return "    \\midrule"
    r.kind === :doublemid && return "    \\midrule\\midrule"
    r.kind === :bottom    && return "    \\bottomrule"
    r.kind === :none      && return ""
    return "    \\midrule"
end

_render_row(r::TabXCmidRule, ::Int) =
    "    " * join(["\\cmidrule(lr){$(a)-$(b)}" for (a, b) in r.spans], " ")

_render_row(r::TabXRaw, ::Int) = r.latex

# Valid rule kinds for the `toprule` / `bottomrule` builder keywords (and the IR).
const _RULE_KINDS = (:top, :mid, :doublemid, :bottom, :none)

# Validate a `toprule`/`bottomrule` value, returning it. `:doublemid` is the
# house default; `:top`/`:bottom` give the booktabs \toprule/\bottomrule, and
# `:none` omits the outer rule entirely.
function _check_rule(kind::Symbol)
    kind in _RULE_KINDS ||
        throw(ArgumentError("rule kind :$(kind) not recognised — use one of $(_RULE_KINDS)"))
    return kind
end

"""
    _apply_outer_rules!(rows, toprule, bottomrule)

Swap the first and last horizontal rules of a freshly built row vector for the
requested `toprule` / `bottomrule` kinds (default `:doublemid` preserves the
house `\\midrule\\midrule`; `:none` omits the rule). Every builder calls this so
the outer rules are overridable without touching the inner separators. Returns
`rows`.
"""
function _apply_outer_rules!(rows, toprule::Symbol, bottomrule::Symbol)
    _check_rule(toprule); _check_rule(bottomrule)
    idxs = findall(r -> r isa TabXRule, rows)
    isempty(idxs) && return rows
    rows[last(idxs)] = TabXRule(bottomrule)        # bottom-most rule
    first(idxs) == last(idxs) || (rows[first(idxs)] = TabXRule(toprule))  # top-most rule
    return rows
end

"""
    write_latex(path, t::TabXTable) -> path

Render `t` and write it to `path`.
"""
function write_latex(path::AbstractString, t::TabXTable)
    open(path, "w") do io
        write(io, to_latex(t))
    end
    return path
end

# Display integration: `display(latexreg(...))` renders LaTeX in Pluto/Jupyter,
# and `show(io, t)` prints the LaTeX. Defined on our own type — not type piracy.
Base.show(io::IO, ::MIME"text/latex", t::TabXTable) = print(io, to_latex(t))
Base.show(io::IO, t::TabXTable) = print(io, to_latex(t))
