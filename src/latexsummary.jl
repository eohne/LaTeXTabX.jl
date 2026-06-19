# latexsummary: descriptive statistics (per variable) from a Tables.jl table
# (e.g. a DataFrame) or a numeric matrix, optionally grouped into labelled panels.

const _SUMMARY_STAT_LABELS = Dict{Symbol,String}(
    :mean => "Mean", :std => "Stdv", :median => "Median",
    :q25 => "Q25", :q75 => "Q75", :min => "Min", :max => "Max",
    :n => "N", :count => "N", :sum => "Sum",
)

"""
    latexsummary(data; stats=[:mean,:std,:q25,:median,:q75], panels=nothing, kwargs...) -> TabXTable

Summary-statistics table from `data` (any Tables.jl table such as a `DataFrame`,
or an observations-by-variables numeric matrix). Each statistic is computed per
variable over its non-missing values.

Keywords:
- `stats` — vector of stat symbols (`:mean :std :median :q25 :q75 :min :max :n
  :sum`) and/or `"Label" => f(vector)` pairs for any custom statistic.
- `panels` — `["Manager Level Data:" => [:a,:b], "Fund Level Data:" => [:c]]` to
  group variables under labelled panels; default is one ungrouped block.
- `vars` — variables to include when `panels` is not given (default: all numeric).
- `labels` — `Dict` of variable display labels; `stat_labels` for the header.
- `digits` (default 2), `commas` (thousands separators, default true).
- `toprule` / `bottomrule` — outermost rules (default `:doublemid`; use
  `:top`/`:bottom` for booktabs `\\toprule`/`\\bottomrule`, `:none` to omit).
- plus `notes`, `title`/`caption`, `label`, `float`, `width`, `colspec`, `file`.
"""
function latexsummary(data;
        stats = [:mean, :std, :q25, :median, :q75],
        panels = nothing,
        vars = nothing,
        labels::AbstractDict = Dict{String,String}(),
        stat_labels::AbstractDict = _SUMMARY_STAT_LABELS,
        digits::Integer = 2,
        commas::Bool = true,
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

    allnames, coltab = _summary_data(data)

    statlabels = String[_summary_statlabel(s, stat_labels) for s in stats]
    nstat = length(stats)
    nstat >= 1 || throw(ArgumentError("latexsummary needs at least one statistic"))
    ncols = nstat + 1

    rows = AbstractTabXRow[]
    push!(rows, TabXRule(:doublemid))

    hdr = TabXCell[TabXCell("")]
    for sl in statlabels
        push!(hdr, TabXCell(sl; align=:c))
    end
    push!(rows, TabXRow(hdr))
    push!(rows, TabXRule(:mid))

    panellist = if panels === nothing
        names = vars === nothing ? allnames : String[string(v) for v in vars]
        Tuple{String,Vector{String}}[("", names)]
    else
        Tuple{String,Vector{String}}[(string(first(p)), String[string(v) for v in last(p)]) for p in panels]
    end

    for (plabel, varnames) in panellist
        if !isempty(plabel)
            push!(rows, TabXRow(TabXCell[TabXCell("\\multicolumn{$(ncols)}{l}{$(plabel)}")]))
            push!(rows, TabXRule(:mid))
        end
        for vn in varnames
            haskey(coltab, vn) || throw(ArgumentError("variable \"$(vn)\" not found as a numeric column"))
            col = coltab[vn]
            disp = haskey(labels, vn) ? labels[vn] : latex_escape(vn)
            cells = TabXCell[TabXCell(disp)]
            for s in stats
                val = _summary_statvalue(_summary_statspec(s), col)
                push!(cells, TabXCell(fmt_number(val; digits=digits, commas=commas)))
            end
            push!(rows, TabXRow(cells))
        end
        push!(rows, TabXRule(:doublemid))
    end
    _apply_outer_rules!(rows, toprule, bottomrule)

    cspec = colspec === nothing ? labelcol * repeat(coltype, nstat) : colspec
    cap = caption !== nothing ? caption : (title !== nothing ? title : "")
    t = TabXTable(ncols; colspec=cspec, width=width, rows=rows, float=float,
                  position=position, caption=cap, label=(label === nothing ? "" : label),
                  notes=collect(notes))
    file !== nothing && write_latex(file, t)
    return t
end

# Header label for a stat entry (Symbol -> stat_labels lookup; pair -> its label).
_summary_statlabel(s::Symbol, stat_labels) = get(stat_labels, s, string(s))
_summary_statlabel(s::Pair, stat_labels) = string(first(s))
_summary_statlabel(s, stat_labels) = throw(ArgumentError("each stat must be a Symbol or a \"Label\" => f(vector) pair"))

# The statistic itself: a Symbol (built-in) or the function from a pair.
_summary_statspec(s::Symbol) = s
_summary_statspec(s::Pair) = last(s)

# Compute one statistic over a column's non-missing values.
_summary_statvalue(f, col) = f(col)                 # custom function statistic
function _summary_statvalue(s::Symbol, col)
    nm = skipmissing(col)
    if s === :mean
        return Statistics.mean(nm)
    elseif s === :std
        return Statistics.std(nm)
    elseif s === :median
        return Statistics.median(nm)
    elseif s === :q25
        return Statistics.quantile(collect(nm), 0.25)
    elseif s === :q75
        return Statistics.quantile(collect(nm), 0.75)
    elseif s === :min
        return minimum(nm)
    elseif s === :max
        return maximum(nm)
    elseif s === :sum
        return sum(nm)
    elseif s === :n || s === :count
        return count(!ismissing, col)
    else
        throw(ArgumentError("unknown summary stat :$(s) — use a \"Label\" => f(vector) pair for custom"))
    end
end

# Ordered numeric variable names + a name->column lookup (columns keep missings;
# each statistic skips them per-variable).
function _summary_data(data)
    if data isa AbstractMatrix
        nms = String["x$(i)" for i in 1:size(data, 2)]
        cols = Any[collect(view(data, :, j)) for j in 1:size(data, 2)]
        return nms, Dict{String,Any}(zip(nms, cols))
    end
    tcols = Tables.columns(data)
    nms = String[]
    cols = Any[]
    for n in Tables.columnnames(tcols)
        v = Tables.getcolumn(tcols, n)
        if _isnumeric(v)
            push!(nms, string(n))
            push!(cols, v)
        end
    end
    return nms, Dict{String,Any}(zip(nms, cols))
end
