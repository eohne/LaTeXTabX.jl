# latextable: render any Tables.jl table (e.g. a DataFrame) or numeric matrix as
# a LaTeX table in the house style — columns become the header, rows become the
# body, and (unlike `display("text/latex", df)`) there is NO row-number column.

"""
    latextable(data; kwargs...) -> TabXTable

Render `data` (any Tables.jl table such as a `DataFrame`, or a matrix) as a LaTeX
table: column names as the header, rows as the body, with no row-number column.
Numbers are formatted (`digits`, `commas`), strings pass through escaped.

Keywords:
- `vars` — columns to include, in order (default: all columns).
- `labels` — `Dict` of column display labels; or pass `header` to override the
  whole header row.
- `digits` (default 3), `escape` (escape string cells, default true).
- `commas` — thousands separators, **off by default** (raw data may hold years/IDs).
  `true` uses `,`, or pass a separator string (`" "`, `"\\,"`, `""`). For mixed
  tables set it **per column**: a collection of column names to separate
  (`commas=[:population, :revenue]`) or a `Dict` of `name => Bool/separator`
  (`Dict(:pop => " ")`); unlisted columns stay un-separated.
- `colspec` (default `l` + `Y`×(ncols-1)), `toprule` / `bottomrule` (outermost
  rules; default `:doublemid`, or `:top`/`:bottom`/`:none`), plus `notes`,
  `title`/`caption`, `label`, `float`, `width`, `file`.
"""
function latextable(data;
        vars = nothing,
        header = nothing,
        labels::AbstractDict = Dict{String,String}(),
        digits::Integer = 3,
        commas = false,
        escape::Bool = true,
        notes = String[],
        title = nothing,
        caption = nothing,
        label = nothing,
        float::Bool = false,
        position::AbstractString = "htb",
        width::AbstractString = "\\textwidth",
        colspec = nothing,
        coltype::AbstractString = "Y",
        labelcol::AbstractString = "l",
        toprule::Symbol = :doublemid,
        bottomrule::Symbol = :doublemid,
        file = nothing)

    nms, cols = _table_columns(data, vars)
    p = length(nms)
    p >= 1 || throw(ArgumentError("latextable needs at least one column"))
    nrows = length(first(cols))

    hdr = header !== nothing ? String[string(h) for h in header] :
          String[haskey(labels, n) ? labels[n] : latex_escape(n) for n in nms]
    length(hdr) == p || throw(ArgumentError("header has $(length(hdr)) entries but data has $(p) columns"))

    # commas can be global (Bool / separator String) or per-column (a collection of
    # column names to separate, or a Dict name => Bool/separator) — so raw ID/year
    # columns stay un-separated while quantity columns get thousands separators.
    colcommas = [_col_commas(commas, nms[j]) for j in 1:p]

    rows = AbstractTabXRow[]
    push!(rows, TabXRule(:doublemid))
    hdrcells = TabXCell[TabXCell(hdr[j]; align = (j == 1 ? :l : :c)) for j in 1:p]
    push!(rows, TabXRow(hdrcells))
    push!(rows, TabXRule(:mid))
    for r in 1:nrows
        push!(rows, TabXRow(TabXCell[TabXCell(_table_cell(cols[j][r], digits, colcommas[j], escape)) for j in 1:p]))
    end
    push!(rows, TabXRule(:doublemid))
    _apply_outer_rules!(rows, toprule, bottomrule)

    cspec = colspec === nothing ? labelcol * repeat(coltype, max(p - 1, 0)) : colspec
    cap = caption !== nothing ? caption : (title !== nothing ? title : "")
    t = TabXTable(p; colspec=cspec, width=width, rows=rows, float=float,
                  position=position, caption=cap, label=(label === nothing ? "" : label),
                  notes=collect(notes))
    file !== nothing && write_latex(file, t)
    return t
end

# Column names + column vectors (all columns, numeric or not).
function _table_columns(data, vars)
    if data isa AbstractMatrix
        nms = vars === nothing ? String["x$(j)" for j in 1:size(data, 2)] :
              String[string(v) for v in vars]
        cols = Any[collect(view(data, :, j)) for j in 1:size(data, 2)]
        return nms, cols
    end
    tcols = Tables.columns(data)
    selected = vars === nothing ? collect(Tables.columnnames(tcols)) : [Symbol(v) for v in vars]
    nms = String[string(n) for n in selected]
    cols = Any[Tables.getcolumn(tcols, n) for n in selected]
    return nms, cols
end

# Resolve the `commas` argument for a single column `n` to a Bool or separator
# string. Global forms (`Bool` / separator `String`) apply to every column; a
# collection of column names is a whitelist (those get `,`); a `Dict` gives a
# per-column Bool/separator (unlisted columns -> off). Comparison is by name string.
function _col_commas(commas, n::AbstractString)
    commas isa Bool && return commas
    commas isa AbstractString && return commas
    if commas isa AbstractDict
        for (k, v) in commas
            string(k) == n && return v
        end
        return false
    end
    if commas isa Union{AbstractVector, AbstractSet, Tuple}
        return any(k -> string(k) == n, commas)
    end
    throw(ArgumentError(
        "`commas` must be a Bool, a separator String, a collection of column names, or a Dict; got $(typeof(commas))"))
end

function _table_cell(v, digits, commas, escape)
    v === missing && return ""
    if v isa Bool
        return string(v)
    elseif v isa Integer
        return fmt_integer(v; commas=commas)
    elseif v isa Real
        return fmt_number(v; digits=digits, commas=commas)
    else
        s = string(v)
        return escape ? latex_escape(s) : s
    end
end
