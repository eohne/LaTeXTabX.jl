# latexpanel: an ergonomic builder for hand-made multi-panel tables (e.g. the
# Barras "scale and skill" / alpaca-style tables) directly over the TabX IR.
#
# A panel is `panel("Panel A: ...", rows...)` (or `"Panel A: ..." => rows`).
# A row is a vector whose entries may be numbers (auto-formatted), strings
# (verbatim LaTeX, e.g. "\$-0.060^{***}\$"), or raw `TabXCell`s. The marker
# `:rule` inserts a `\midrule` inside a panel. Short rows are padded with blanks.

"""
    panel(label, rows...) -> (label, rows)

Construct a panel for [`latexpanel`](@ref). Equivalent to the pair
`label => [rows...]`.
"""
panel(label, rows...) = (string(label), collect(Any, rows))

"""
    latexpanel(panels; header=nothing, kwargs...) -> TabXTable

Assemble a multi-panel table from `panels` (each a [`panel`](@ref) or a
`label => rows` pair). Row entries may be numbers (formatted with `digits`),
strings (verbatim), or `TabXCell`s; `:rule` adds a `\\midrule` within a panel.

Keywords:
- `header` — column header labels (excluding the row-label column); adds a header
  row + rule. `header_align` (default `:c`).
- `panel_format` — function turning a panel label into LaTeX (default italic).
- `digits` — decimals for numeric entries (default 3).
- `ncols` — column count (inferred from `header` or the widest row if omitted).
- plus `notes`, `title`/`caption`, `label`, `float`, `width`, `colspec`, `file`.
"""
function latexpanel(panels;
        header = nothing,
        header_align::Symbol = :c,
        panel_format = s -> "\\textit{$(s)}",
        digits::Integer = 3,
        ncols = nothing,
        colspec = nothing,
        coltype::AbstractString = "Y",
        labelcol::AbstractString = "l",
        width::AbstractString = "\\textwidth",
        notes = String[],
        title = nothing,
        caption = nothing,
        label = nothing,
        float::Bool = false,
        position::AbstractString = "htb",
        file = nothing)

    plist = _normalize_panels(panels)
    nc = ncols !== nothing ? Int(ncols) :
         header !== nothing ? length(header) + 1 :
         _infer_panel_ncols(plist)

    rows = AbstractTabXRow[]
    push!(rows, TabXRule(:doublemid))

    if header !== nothing
        cells = TabXCell[TabXCell("")]
        for h in header
            push!(cells, h isa TabXCell ? h : TabXCell(string(h); align=header_align))
        end
        push!(rows, TabXRow(cells))
        push!(rows, TabXRule(:mid))
    end

    for (pi, (plabel, prows)) in enumerate(plist)
        pi > 1 && push!(rows, TabXRule(:mid))
        isempty(plabel) || push!(rows, TabXRow(TabXCell[TabXCell("\\multicolumn{$(nc)}{l}{$(panel_format(plabel))}")]))
        for r in prows
            if r === :rule || r === :midrule
                push!(rows, TabXRule(:mid))
            elseif r isa AbstractTabXRow
                push!(rows, r)
            else
                push!(rows, TabXRow(_panel_row_cells(r, nc, digits)))
            end
        end
    end

    push!(rows, TabXRule(:doublemid))

    cspec = colspec !== nothing ? colspec : labelcol * repeat(coltype, nc - 1)
    cap = caption !== nothing ? caption : (title !== nothing ? title : "")
    t = TabXTable(nc; colspec=cspec, width=width, rows=rows, float=float,
                  position=position, caption=cap, label=(label === nothing ? "" : label),
                  notes=collect(notes))
    file !== nothing && write_latex(file, t)
    return t
end

function _normalize_panels(panels)
    out = Tuple{String,Vector{Any}}[]
    for p in panels
        if p isa Pair
            push!(out, (string(first(p)), collect(Any, last(p))))
        elseif p isa Tuple && length(p) == 2
            push!(out, (string(p[1]), collect(Any, p[2])))
        else
            throw(ArgumentError("each panel must be `panel(label, rows...)` or `label => rows`"))
        end
    end
    return out
end

function _panel_row_cells(r, nc, digits)
    cells = TabXCell[]
    for v in collect(r)
        if v isa TabXCell
            push!(cells, v)
        elseif v isa Number
            push!(cells, TabXCell(fmt_number(v; digits=digits)))
        else
            push!(cells, TabXCell(string(v)))
        end
    end
    while length(cells) < nc
        push!(cells, TabXCell(""))
    end
    return cells
end

function _infer_panel_ncols(plist)
    n = 0
    for (_, prows) in plist, r in prows
        (r === :rule || r === :midrule || r isa AbstractTabXRow) && continue
        n = max(n, length(collect(r)))
    end
    n == 0 && throw(ArgumentError("cannot infer ncols; pass `header` or `ncols`"))
    return n
end
