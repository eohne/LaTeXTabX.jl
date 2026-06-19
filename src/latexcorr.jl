# latexcorr: a (multi-panel) correlation matrix from a Tables.jl table (e.g. a
# DataFrame) or a numeric matrix. Each requested `method` (Pearson, Spearman, or
# a custom function) is rendered as its own stacked block; `panels` additionally
# groups the variable rows into labelled sub-blocks (same meaning as in
# `latexsummary`).

"""
    latexcorr(data; methods=[:pearson, :spearman], kwargs...) -> TabXTable

Build a correlation table from `data` — any Tables.jl table (e.g. a `DataFrame`)
or an observations-by-variables numeric matrix. Each entry of `methods`
(`:pearson` / `:spearman` / `"Label" => f(matrix)`) becomes a stacked block.
Correlations use complete cases (rows with a `missing`/`NaN` in any selected
variable are dropped).

Keywords:
- `vars` — variables/columns to include (default: all numeric columns).
- `panels` — `["Returns" => [:a,:b], "Risk" => [:c]]` to group the variable rows
  into labelled sub-blocks (same as in `latexsummary`); the matrix is computed
  over all panel variables. Overrides `vars`.
- `labels` — `Dict` mapping variable names to display (row) labels.
- `methods` — which correlations; each is a stacked block. `panel_labels` for the
  method header text; `bold_panel` to bold it.
- `col_groups` / `col_group_rule` / `col_labels` — multi-level column headers,
  e.g. `col_groups=["Connectedness" => 1:2]`; `col_labels` sets column-header
  labels independently of the row labels in `labels`.
- `digits` (default 3), `diagonal` (show the `1.000` diagonal), `lower` (lower
  triangle only).
- `toprule` / `bottomrule` — outermost rules (default `:doublemid`; use
  `:top`/`:bottom` for booktabs `\\toprule`/`\\bottomrule`, `:none` to omit).
- plus `notes`, `title`/`caption`, `label`, `float`, `width`, `colspec`, `file`.
"""
function latexcorr(data;
        methods = [:pearson, :spearman],
        vars = nothing,
        panels = nothing,
        labels::AbstractDict = Dict{String,String}(),
        digits::Integer = 3,
        diagonal::Bool = true,
        lower::Bool = false,
        panel_labels::AbstractDict = Dict(:pearson => "Pearson", :spearman => "Spearman"),
        bold_panel::Bool = true,
        col_groups = nothing,
        col_group_rule::Bool = true,
        col_labels = nothing,
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

    # variable order + (optional) row-panel grouping
    if panels === nothing
        panelspecs = nothing
        varorder = vars
    else
        panelspecs = Tuple{String,Vector{String}}[(string(first(p)), String[string(v) for v in last(p)]) for p in panels]
        varorder = String[]
        for (_, vs) in panelspecs
            append!(varorder, vs)
        end
    end

    X, nms = _corr_matrix(data, varorder)
    p = size(X, 2)
    p >= 1 || throw(ArgumentError("latexcorr needs at least one numeric variable"))
    ncols = p + 1

    displaynames = String[haskey(labels, n) ? labels[n] : latex_escape(n) for n in nms]
    coldisp = col_labels === nothing ? displaynames :
              String[haskey(col_labels, n) ? col_labels[n] : displaynames[i] for (i, n) in enumerate(nms)]

    # contiguous row ranges per panel (varorder = flattened panel vars)
    rowpanels = if panelspecs === nothing
        Tuple{String,UnitRange{Int}}[("", 1:p)]
    else
        rng = Tuple{String,UnitRange{Int}}[]
        start = 1
        for (plab, vs) in panelspecs
            len = length(vs)
            push!(rng, (plab, start:(start + len - 1)))
            start += len
        end
        rng
    end

    rows = AbstractTabXRow[]
    push!(rows, TabXRule(:doublemid))

    for method in methods
        plab, corrfn = _resolve_method(method, panel_labels)
        C = corrfn(X)
        for hr in _corr_header_rows(plab, coldisp, col_groups, bold_panel, col_group_rule)
            push!(rows, hr)
        end
        push!(rows, TabXRule(:mid))

        for (pix, (panlabel, rng)) in enumerate(rowpanels)
            if !isempty(panlabel)
                pix > 1 && push!(rows, TabXRule(:mid))
                push!(rows, TabXRow(TabXCell[TabXCell("\\multicolumn{$(ncols)}{l}{$(panlabel)}")]))
                push!(rows, TabXRule(:mid))
            end
            for i in rng
                cells = TabXCell[TabXCell(displaynames[i])]
                for j in 1:p
                    blank = (lower && j > i) || (!diagonal && i == j)
                    push!(cells, TabXCell(blank ? "" : fmt_number(C[i, j]; digits=digits)))
                end
                push!(rows, TabXRow(cells))
            end
        end
        push!(rows, TabXRule(:doublemid))
    end
    _apply_outer_rules!(rows, toprule, bottomrule)

    cspec = colspec === nothing ? labelcol * repeat(coltype, p) : colspec
    cap = caption !== nothing ? caption : (title !== nothing ? title : "")
    t = TabXTable(ncols; colspec=cspec, width=width, rows=rows, float=float,
                  position=position, caption=cap, label=(label === nothing ? "" : label),
                  notes=collect(notes))
    file !== nothing && write_latex(file, t)
    return t
end

_corr(X, method::Symbol) =
    method === :pearson  ? Statistics.cor(X) :
    method === :spearman ? Statistics.cor(_rankcols(X)) :
    throw(ArgumentError("unknown correlation method :$(method) (use :pearson or :spearman)"))

# Resolve a `methods` entry to (panel label, matrix -> correlation-matrix fn).
# An entry is `:pearson`/`:spearman`, or a `"Label" => f(matrix)` pair for ANY
# custom correlation (Kendall, partial, robust, weighted, ...).
function _resolve_method(method, panel_labels)
    if method isa Symbol
        return (get(panel_labels, method, string(method)), X -> _corr(X, method))
    elseif method isa Pair
        return (string(first(method)), last(method))
    else
        throw(ArgumentError("each method must be a Symbol or a \"Label\" => f(matrix) pair"))
    end
end

_asrange(r::AbstractUnitRange) = first(r):last(r)
_asrange(r::Integer) = Int(r):Int(r)
_asrange(r) = first(r):last(r)

# Column-header rows for one block. With `col_groups`, grouped variables show the
# group name spanning a top row and their `coldisp` labels in a sub-row.
function _corr_header_rows(panel_label, coldisp, col_groups, bold_panel, col_group_rule)
    head = bold_panel ? "\\textbf{$(panel_label)}" : panel_label
    p = length(coldisp)
    if col_groups === nothing
        hdr = TabXCell[TabXCell(head)]
        for dn in coldisp
            push!(hdr, TabXCell(dn; align=:c))
        end
        return AbstractTabXRow[TabXRow(hdr)]
    end

    groups = Tuple{String,UnitRange{Int}}[(string(first(g)), _asrange(last(g))) for g in col_groups]
    top = TabXCell[TabXCell(head)]
    sub = TabXCell[TabXCell("")]
    topspans = Tuple{Int,Int}[]
    anygroup = false
    j = 1
    while j <= p
        gi = findfirst(g -> first(g[2]) == j, groups)
        if gi === nothing
            push!(top, TabXCell(coldisp[j]; align=:c))
            push!(sub, TabXCell(""))
            push!(topspans, (j + 1, j + 1))   # underline single top-level headers too
            j += 1
        else
            glab, rng = groups[gi]
            span = length(rng)
            push!(top, TabXCell(glab; span=span, align=:c))
            push!(topspans, (j + 1, j + span))
            for k in rng
                push!(sub, TabXCell(coldisp[k]; align=:c))
            end
            anygroup = true
            j += span
        end
    end

    out = AbstractTabXRow[TabXRow(top)]
    (col_group_rule && !isempty(topspans)) && push!(out, TabXCmidRule(topspans))
    anygroup && push!(out, TabXRow(sub))
    return out
end

function _rankcols(X)
    R = Matrix{Float64}(undef, size(X, 1), size(X, 2))
    for j in 1:size(X, 2)
        R[:, j] = _tiedrank(view(X, :, j))
    end
    return R
end

# Average (tied) ranks — Spearman = Pearson correlation of ranks.
function _tiedrank(x)
    n = length(x)
    perm = sortperm(x)
    r = Vector{Float64}(undef, n)
    i = 1
    while i <= n
        j = i
        while j < n && x[perm[j + 1]] == x[perm[i]]
            j += 1
        end
        avg = (i + j) / 2
        for k in i:j
            r[perm[k]] = avg
        end
        i = j + 1
    end
    return r
end

# Build a complete-case Float64 matrix + variable names from a table or matrix.
function _corr_matrix(data, vars)
    if data isa AbstractMatrix
        nms = vars === nothing ? String["x$(i)" for i in 1:size(data, 2)] :
              String[string(v) for v in vars]
        vectors = Any[collect(view(data, :, j)) for j in 1:size(data, 2)]
        X, _ = _complete_matrix(vectors)
        return X, nms
    end
    cols = Tables.columns(data)
    allnames = Tables.columnnames(cols)
    selected = vars === nothing ?
        Symbol[Symbol(n) for n in allnames if _isnumeric(Tables.getcolumn(cols, n))] :
        Symbol[Symbol(v) for v in vars]
    nms = String[string(n) for n in selected]
    vectors = Any[Tables.getcolumn(cols, n) for n in selected]
    X, _ = _complete_matrix(vectors)
    return X, nms
end

_isnumeric(v) = eltype(v) <: Union{Missing,Number}

function _complete_matrix(vectors)
    p = length(vectors)
    n = p == 0 ? 0 : length(first(vectors))
    keep = trues(n)
    for v in vectors, i in 1:n
        xi = v[i]
        (ismissing(xi) || (xi isa AbstractFloat && isnan(xi))) && (keep[i] = false)
    end
    idx = findall(keep)
    X = Matrix{Float64}(undef, length(idx), p)
    for j in 1:p
        v = vectors[j]
        for (ii, i) in enumerate(idx)
            X[ii, j] = float(v[i])
        end
    end
    return X, idx
end
