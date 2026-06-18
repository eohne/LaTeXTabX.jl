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
        println(io, _render_row(r, t.ncols))
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
    return "    \\midrule"
end

_render_row(r::TabXCmidRule, ::Int) =
    "    " * join(["\\cmidrule(lr){$(a)-$(b)}" for (a, b) in r.spans], " ")

_render_row(r::TabXRaw, ::Int) = r.latex

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
