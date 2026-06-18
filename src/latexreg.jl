# latexreg: build a regression table (TabXTable) from one or more fitted models.
#
# Extraction is generic over the StatsAPI `RegressionModel` interface (via
# `coeftable`), so anything implementing it works out of the box. Package
# extensions enrich the pieces the generic interface does not expose
# (response names, estimator labels, fixed-effect blocks, clusters, extra stats).

"""
    ModelData

Normalized data pulled from a fitted model, plus a reference to the model itself
(so statistics can be computed on demand). Holds the response name, estimator
label, coefficient names/values/SEs/p-values, fixed-effect indicators, and
cluster names.
"""
struct ModelData
    model::Any
    responsename::String
    estimator::String
    coefnames::Vector{String}
    coefs::Vector{Float64}
    ses::Vector{Float64}
    pvals::Vector{Float64}
    fixedeffects::Vector{Pair{String,Bool}}
    clusters::Vector{String}
    se_kind::Symbol
    se_typelabel::String
end

_try(f) = try f() catch; missing end
_try_string(f) = (r = _try(f); r === missing ? "" : string(r))

# --- hooks overridable by extensions ---
_responsename(m) = _try_string(() -> StatsAPI.responsename(m))
_estimator(m) = ""
_fixedeffects(m) = Pair{String,Bool}[]
# (vcov kind, cluster variable names, precise type label). kind ∈ (:simple,
# :robust, :cluster, :unknown); the label is a precise name for robust SEs
# ("HC1"/"HC3"/"HAC(...)") when the backend exposes it. Extensions override:
# FixedEffectModels reads the fitted vcov; Regress reports the exact HC/HAC/CR kind.
_se_info(m) = (:unknown, String[], "")
# Package-specific statistics (e.g. :r2_within, :fstat). Extensions override.
_regstat_ext(s::Symbol, m) = missing

"""
    modeldata(model) -> ModelData

Extract a `ModelData` from a fitted model using the StatsAPI `coeftable`
interface. Extensions specialize the helper hooks (`_responsename`, `_estimator`,
`_fixedeffects`, `_clusters`, `_regstat_ext`).
"""
function modeldata(m)
    ct = StatsAPI.coeftable(m)
    nms = String[string(n) for n in ct.rownms]
    cols = ct.cols
    est = Float64.(cols[1])
    se = length(cols) >= 2 ? Float64.(cols[2]) : fill(NaN, length(est))
    pcol = hasproperty(ct, :pvalcol) ? ct.pvalcol : 0
    pv = (pcol > 0 && pcol <= length(cols)) ? Float64.(cols[pcol]) : fill(NaN, length(est))
    se_kind, se_vars, se_typelabel = _se_info(m)
    return ModelData(m, _responsename(m), _estimator(m), nms, est, se, pv,
                     _fixedeffects(m), se_vars, se_kind, se_typelabel)
end

# Built-in regression statistics computed via StatsAPI; `missing` if unsupported.
function _regstat(s::Symbol, m)
    return _try() do
        if s === :nobs
            Int(StatsAPI.nobs(m))
        elseif s === :r2
            StatsAPI.r2(m)
        elseif s === :adjr2
            StatsAPI.adjr2(m)
        elseif s === :aic
            StatsAPI.aic(m)
        elseif s === :aicc
            StatsAPI.aicc(m)
        elseif s === :bic
            StatsAPI.bic(m)
        elseif s === :loglikelihood || s === :loglik
            StatsAPI.loglikelihood(m)
        elseif s === :nullloglikelihood
            StatsAPI.nullloglikelihood(m)
        elseif s === :dof
            StatsAPI.dof(m)
        elseif s === :dof_residual
            StatsAPI.dof_residual(m)
        elseif s === :deviance
            StatsAPI.deviance(m)
        elseif s === :nulldeviance
            StatsAPI.nulldeviance(m)
        elseif s === :r2_mcfadden
            StatsAPI.r2(m, :McFadden)
        elseif s === :r2_coxsnell
            StatsAPI.r2(m, :CoxSnell)
        elseif s === :r2_nagelkerke
            StatsAPI.r2(m, :Nagelkerke)
        elseif s === :r2_deviance
            StatsAPI.r2(m, :devianceratio)
        else
            _regstat_ext(s, m)
        end
    end
end

const _DEFAULT_STAT_LABELS = Dict{Symbol,String}(
    :nobs              => "\$N\$",
    :r2                => "\$R^2\$",
    :adjr2             => "Adjusted \$R^2\$",
    :r2_within         => "Within \$R^2\$",
    :r2_mcfadden       => "Pseudo \$R^2\$",
    :r2_coxsnell       => "Cox-Snell \$R^2\$",
    :r2_nagelkerke     => "Nagelkerke \$R^2\$",
    :r2_deviance       => "Deviance \$R^2\$",
    :aic               => "AIC",
    :aicc              => "AICc",
    :bic               => "BIC",
    :loglikelihood     => "Log-likelihood",
    :loglik            => "Log-likelihood",
    :nullloglikelihood => "Null log-likelihood",
    :deviance          => "Deviance",
    :nulldeviance      => "Null deviance",
    :dof               => "DOF",
    :dof_residual      => "Residual DOF",
    :fstat             => "\$F\$",
    :fstat_pval        => "\$F\$ \$p\$-value",
)

"""
    latexreg(models...; kwargs...) -> TabXTable

Build a regression table from one or more fitted models (GLM, FixedEffectModels,
StagDiDModels, Regress, or any StatsAPI `RegressionModel`). Returns a `TabXTable`;
pass `file=...` to also write the `.tex`. Render with `to_latex(t)`.

Key keywords:
- `labels::AbstractDict` — map raw coefficient / response / FE names to display
  labels (RegressionTables-style relabeling).
- `keep` / `drop` / `order` — coefficient names/regex (String, Regex, or a vector).
  `drop_intercept=true` also drops `(Intercept)` (off by default — intercept kept).
- `below` — under each estimate: `:se` (default), `:tstat`, `:confint`, or `:none`.
- `depvar` / `depvar_labels`, `combine_depvar`, `depvar_rule` — dependent-var header.
- `groups` — pairs `["A" => 1:3, ...]` (model-index ranges) OR a matrix /
  vector-of-vectors of header levels; adjacent equal labels merge with `\\cmidrule`.
- `number_regressions` — `(1) (2) ...` row (set `false` to omit).
- `estimator` — `:auto` / `:show` / `:none`; with `estimator_position`
  (`:top`/`:bottom`), `estimator_label`, `estimator_labels`.
- `fixedeffects` — FE rows. `fe_style` `:block` ("Fixed Effects" header +
  indented rows) or `:compact` ("Date FE"/"Firm FE" rows, `fe_suffix`);
  `fe_title`. `yes`/`no` are the indicator markers (default "Yes"/"No"; set
  `no=""` to blank, `yes="\\checkmark"` for a tick) — used by FE rows and the
  `print_controls` controls indicator (`controls_label`).
- `print_se` / `se_label` / `simple_label` / `robust_label` / `se_cluster_text` —
  a "Std. errors" row auto-detected per model from its fitted vcov: the precise
  type ("Classical", "HC1", "HC3", "HAC(...)", "Robust") or `se_cluster_text`
  ("Clustered") when clustered. Backends that expose the exact kind (Regress.jl,
  FixedEffectModels.jl) print it precisely; others fall back to `robust_label`.
- `print_cluster` / `cluster_label` / `cluster_join` — a separate "Cluster" row
  naming the clustering variable(s) (two-way joined by `\\&`; set
  `cluster_join=" \$\\times\$ "` for interacted). Cluster (and FE) names are
  relabeled via `labels`.
- `se_collapse` (default `true`) — drop the SE-type / Cluster row when it is
  identical across every column (show it only when it varies across models).
  Exception: if any model is auto-detected as clustered, both rows are always
  shown — clustering is surfaced even when uniform.
- `ses` / `se_labels` / `cluster_labels` — manual overrides. `ses` replaces a
  model's SEs (e.g. post-estimation clustering for GLM, which can't cluster
  natively): a per-model vector, each entry `nothing`, a vector of SEs, or a
  `coef => se` Dict — p-values and stars are recomputed (normal approximation).
  `se_labels` / `cluster_labels` are per-model free-text arrays for the two rows
  (each entry `nothing` = auto).
- `stats` — vector of stat symbols and/or `"Label" => f(model)` pairs. Built-ins:
  `:nobs :r2 :adjr2 :r2_within :r2_mcfadden :r2_coxsnell :r2_nagelkerke
  :r2_deviance :aic :aicc :bic :loglikelihood :deviance :dof :dof_residual
  :fstat :fstat_pval`. `stat_labels` to relabel.
- `extralines`, `notes`, `title`/`caption`, `label`, `float`, `width`, `colspec`,
  `digits`, `stat_digits`, `star_cutoffs`, `star_symbols`, `confint_z`, `file`.
"""
function latexreg(models...;
        labels::AbstractDict = Dict{String,String}(),
        keep = nothing,
        drop = nothing,
        order = nothing,
        drop_intercept::Bool = false,
        depvar::Bool = true,
        depvar_labels = nothing,
        groups = nothing,
        group_rule::Bool = true,
        number_regressions::Bool = true,
        estimator::Symbol = :auto,
        estimator_position::Symbol = :top,
        estimator_label::AbstractString = "Estimator",
        estimator_labels = nothing,
        fixedeffects = nothing,
        fe_title::AbstractString = "Fixed Effects",
        fe_style::Symbol = :block,
        fe_suffix::AbstractString = " FE",
        yes::AbstractString = "Yes",
        no::AbstractString = "No",
        stats = [:nobs, :adjr2],
        stat_labels::AbstractDict = _DEFAULT_STAT_LABELS,
        digits::Integer = 3,
        stat_digits::Integer = 3,
        below::Symbol = :se,
        confint_z::Real = 1.959964,
        combine_depvar::Bool = true,
        depvar_rule::Bool = true,
        extralines = nothing,
        print_controls::Bool = true,
        controls_label::AbstractString = "Controls",
        print_se::Bool = true,
        se_label::AbstractString = "Std. errors",
        se_cluster_text::AbstractString = "Clustered",
        robust_label::AbstractString = "Robust",
        simple_label::AbstractString = "Classical",
        print_cluster::Bool = true,
        cluster_label::AbstractString = "Cluster",
        cluster_join::AbstractString = " \\& ",
        se_collapse::Bool = true,
        ses = nothing,
        se_labels = nothing,
        cluster_labels = nothing,
        star_cutoffs = (0.01, 0.05, 0.1),
        star_symbols = ("***", "**", "*"),
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
        file = nothing)

    isempty(models) && throw(ArgumentError("latexreg requires at least one model"))
    mds = ModelData[modeldata(m) for m in models]
    nm = length(mds)
    ncols = nm + 1

    getlabel(k) = haskey(labels, k) ? labels[k] : latex_escape(k)
    coefkeys = _coef_order(mds, _aspats(keep), _aspats(drop), _aspats(order), drop_intercept)

    # per-model SE overrides (e.g. post-estimation clustered SEs for GLM):
    # recompute p-values + stars from the new SEs (normal approximation).
    override_ses = Vector{Vector{Float64}}(undef, nm)
    override_pvals = Vector{Vector{Float64}}(undef, nm)
    for (i, md) in enumerate(mds)
        if ses !== nothing && i <= length(ses) && ses[i] !== nothing
            sv = _as_se_vector(ses[i], md.coefnames)
            override_ses[i] = sv
            override_pvals[i] = Float64[_twosided_p(md.coefs[k] / sv[k]) for k in eachindex(sv)]
        else
            override_ses[i] = md.ses
            override_pvals[i] = md.pvals
        end
    end

    ests = estimator_labels !== nothing ? String[string(e) for e in estimator_labels] :
           String[md.estimator for md in mds]
    show_est = estimator === :show ? any(!isempty, ests) :
               estimator === :auto ? (any(!isempty, ests) && length(unique(ests)) > 1) : false

    rows = AbstractTabXRow[]
    push!(rows, TabXRule(:doublemid))

    # dependent-variable header (optionally merging adjacent equal names)
    if depvar
        labs = String[]
        for (i, md) in enumerate(mds)
            push!(labs, depvar_labels !== nothing ? string(depvar_labels[i]) :
                  (haskey(labels, md.responsename) ? labels[md.responsename] : latex_escape(md.responsename)))
        end
        segs = combine_depvar ? _merge_equal(labs) : Tuple{String,Int}[(l, 1) for l in labs]
        cells = TabXCell[TabXCell("")]
        spans = Tuple{Int,Int}[]
        col = 2
        for (lab, span) in segs
            push!(cells, TabXCell(lab; span=span, align=:c))
            isempty(lab) || push!(spans, (col, col + span - 1))   # underline every named depvar
            col += span
        end
        push!(rows, TabXRow(cells))
        (depvar_rule && !isempty(spans)) && push!(rows, TabXCmidRule(spans))
    end

    # estimator row (top placement)
    if show_est && estimator_position === :top
        ecells, _ = _merged_row(estimator_label, ests)
        push!(rows, TabXRow(ecells))
    end

    # grouped header(s): pairs (label => model-range) OR a matrix / vector-of-
    # vectors where each row is a header level (merged on adjacent equal labels)
    if groups !== nothing
        levels = _group_levels(groups)
        if levels === nothing
            gcells = TabXCell[TabXCell("")]
            spans = Tuple{Int,Int}[]
            for (glab, rng) in groups
                push!(gcells, TabXCell(string(glab); span=length(rng), align=:c))
                push!(spans, (first(rng) + 1, last(rng) + 1))
            end
            push!(rows, TabXRow(gcells))
            group_rule && push!(rows, TabXCmidRule(spans))
        else
            for level in levels
                length(level) == nm || throw(ArgumentError(
                    "each groups header level needs $(nm) entries (one per model); got $(length(level))"))
                gcells, spans = _merged_row("", level)
                push!(rows, TabXRow(gcells))
                (group_rule && !isempty(spans)) && push!(rows, TabXCmidRule(spans))
            end
        end
    end

    # regression numbers
    if number_regressions
        cells = TabXCell[TabXCell("")]
        for i in 1:nm
            push!(cells, TabXCell("($(i))"; align=:c))
        end
        push!(rows, TabXRow(cells))
    end

    push!(rows, TabXRule(:mid))

    # coefficient rows (estimate, with the chosen statistic on the line below)
    for k in coefkeys
        crow = TabXCell[TabXCell(getlabel(k))]
        brow = TabXCell[TabXCell("")]
        for (mi, md) in enumerate(mds)
            idx = findfirst(==(k), md.coefnames)
            if idx === nothing
                push!(crow, TabXCell(""))
                push!(brow, TabXCell(""))
            else
                star = sig_stars(override_pvals[mi][idx]; cutoffs=star_cutoffs, symbols=star_symbols)
                push!(crow, TabXCell(fmt_number(md.coefs[idx]; digits=digits) * star))
                push!(brow, TabXCell(_below_str(below, md.coefs[idx], override_ses[mi][idx];
                                                digits=digits, confint_z=confint_z)))
            end
        end
        push!(rows, TabXRow(crow))
        below === :none || push!(rows, TabXRow(brow))
    end

    # fixed-effects block + controls indicator
    feinfo = _resolve_fe(fixedeffects, mds, nm)
    controls_flags = print_controls ? Bool[!isempty(setdiff(md.coefnames, coefkeys)) for md in mds] : Bool[]
    show_controls = print_controls && any(controls_flags)
    # SE-type row ("Classical"/"HC1"/"Robust"/"Clustered", per model) + a separate
    # cluster-variable row. Either can be overridden (se_labels / cluster_labels),
    # toggled (print_se / print_cluster), and is collapsed away when constant across
    # all columns (se_collapse).
    se_cells = String[
        (se_labels !== nothing && i <= length(se_labels) && se_labels[i] !== nothing) ?
            string(se_labels[i]) :
            _se_type_cell(md.se_kind, md.se_typelabel, se_cluster_text, robust_label, simple_label)
        for (i, md) in enumerate(mds)]
    cluster_cells = String[
        (cluster_labels !== nothing && i <= length(cluster_labels) && cluster_labels[i] !== nothing) ?
            string(cluster_labels[i]) :
            ((md.se_kind === :cluster && !isempty(md.clusters)) ?
                join(String[haskey(labels, c) ? labels[c] : c for c in md.clusters], cluster_join) : "")
        for (i, md) in enumerate(mds)]
    # Clustering is always surfaced when present (even if identical across every
    # column); other SE types collapse to nothing when constant.
    any_cluster = any(md -> md.se_kind === :cluster, mds)
    show_se = print_se && any(!isempty, se_cells) &&
              (any_cluster || !(se_collapse && _allsame(se_cells)))
    show_cluster = print_cluster && any(!isempty, cluster_cells) &&
                   (any_cluster || !(se_collapse && _allsame(cluster_cells)))
    if !isempty(feinfo) || show_controls || show_se || show_cluster
        push!(rows, TabXRule(:mid))
        if !isempty(feinfo)
            # :block -> a "Fixed Effects" header + indented rows (Date, Firm, ...)
            # :compact -> no header; each row labelled "Date FE", "Firm FE", ...
            fe_style === :block &&
                push!(rows, TabXRow(vcat(TabXCell(fe_title), [TabXCell("") for _ in 1:nm])))
            for (fename, flags) in feinfo
                felabel = haskey(labels, fename) ? labels[fename] : fename
                rowlabel = fe_style === :compact ? (felabel * fe_suffix) : ("\\hspace{2mm}" * felabel)
                cells = TabXCell[TabXCell(rowlabel)]
                for f in flags
                    push!(cells, TabXCell(f ? yes : no))
                end
                push!(rows, TabXRow(cells))
            end
        end
        if show_controls
            cells = TabXCell[TabXCell(controls_label)]
            for f in controls_flags
                push!(cells, TabXCell(f ? yes : no))
            end
            push!(rows, TabXRow(cells))
        end
        if show_se
            push!(rows, TabXRow(vcat(TabXCell(se_label), TabXCell[TabXCell(c) for c in se_cells])))
        end
        if show_cluster
            push!(rows, TabXRow(vcat(TabXCell(cluster_label), TabXCell[TabXCell(c) for c in cluster_cells])))
        end
    end

    # estimator row (bottom placement)
    if show_est && estimator_position === :bottom
        push!(rows, TabXRule(:mid))
        ecells, _ = _merged_row(estimator_label, ests)
        push!(rows, TabXRow(ecells))
    end

    # statistics (built-in symbols and/or "Label" => f(model) pairs)
    if !isempty(stats)
        push!(rows, TabXRule(:mid))
        for s in stats
            cells = TabXCell[TabXCell(_reg_statlabel(s, stat_labels))]
            for md in mds
                v = s isa Pair ? _safe_apply(last(s), md.model) : _regstat(s, md.model)
                push!(cells, TabXCell(_fmt_regstat(s, v; digits=stat_digits)))
            end
            push!(rows, TabXRow(cells))
        end
    end

    # custom extra rows (sample/controls indicators, hand-computed stats, ...)
    if extralines !== nothing && !isempty(collect(extralines))
        push!(rows, TabXRule(:mid))
        for r in extralines
            push!(rows, TabXRow(_extraline_cells(r, ncols)))
        end
    end

    push!(rows, TabXRule(:doublemid))

    cspec = colspec === nothing ? labelcol * repeat(coltype, nm) : colspec
    cap = caption !== nothing ? caption : (title !== nothing ? title : "")
    lbl = label !== nothing ? label : ""

    t = TabXTable(ncols; colspec=cspec, width=width, rows=rows,
                  float=float, position=position, caption=cap, label=lbl,
                  notes=collect(notes))

    file !== nothing && write_latex(file, t)
    return t
end

# --- statistic helpers ---
_reg_statlabel(s::Symbol, labels) = get(labels, s, string(s))
_reg_statlabel(s::Pair, labels) = string(first(s))
_reg_statlabel(s, labels) = string(s)

_safe_apply(f, m) = try f(m) catch; missing end

function _fmt_regstat(s, v; digits)
    v === missing && return ""
    (s isa Symbol && (s === :nobs || s === :dof || s === :dof_residual || s === :dof_fes)) &&
        return fmt_integer(v; commas=true)
    return fmt_number(float(v); digits=digits)
end

# SE-type cell for one model: the *type* only (the cluster variable, if any, goes
# in a separate row). Robust models use their precise label (e.g. "HC1") when the
# backend provides one, else `robust_label`.
function _se_type_cell(kind, typelabel, se_cluster_text, robust_label, simple_label)
    kind === :cluster && return se_cluster_text
    kind === :robust  && return isempty(typelabel) ? robust_label : typelabel
    kind === :simple  && return simple_label
    return ""
end

# All entries equal? (used to collapse a constant indicator row.)
_allsame(v) = isempty(v) || all(isequal(first(v)), v)

# Two-sided p-value from a z-statistic via a rational erfc approximation
# (Abramowitz & Stegun 7.1.26) — used when SEs are overridden.
function _twosided_p(z)
    (z isa Real && isfinite(z)) || return NaN
    x = abs(z) / sqrt(2)
    t = 1.0 / (1.0 + 0.3275911 * x)
    poly = t * (0.254829592 + t * (-0.284496736 + t * (1.421413741 + t * (-1.453152027 + t * 1.061405429))))
    return poly * exp(-x * x)
end

# Normalize a per-model SE override (vector or `coef => se` Dict) to a vector
# aligned with the model's coefficient names.
function _as_se_vector(se, coefnames)
    if se isa AbstractDict
        return Float64[haskey(se, c) ? float(se[c]) : NaN for c in coefnames]
    end
    v = collect(se)
    length(v) == length(coefnames) ||
        throw(ArgumentError("ses override has $(length(v)) entries but the model has $(length(coefnames)) coefficients"))
    return Float64[float(x) for x in v]
end

# --- coefficient selection / ordering ---
_aspats(x) = x === nothing ? nothing : (x isa AbstractVector ? collect(x) : [x])

_matches(name::AbstractString, pat::AbstractString) = name == pat
_matches(name::AbstractString, pat::Regex) = occursin(pat, name)
_matches(name::AbstractString, pat) = name == string(pat)

function _coef_order(mds, keep, drop, order, drop_intercept)
    allnames = String[]
    for md in mds, k in md.coefnames
        k in allnames || push!(allnames, k)
    end

    sel = if keep === nothing
        copy(allnames)
    else
        acc = String[]
        for pat in keep, k in allnames
            (_matches(k, pat) && !(k in acc)) && push!(acc, k)
        end
        acc
    end

    droppats = Any[]
    drop === nothing || append!(droppats, drop)
    drop_intercept && push!(droppats, r"^\(Intercept\)$")
    isempty(droppats) || (sel = String[k for k in sel if !any(p -> _matches(k, p), droppats)])

    if order !== nothing
        front = String[]
        for pat in order, k in sel
            (_matches(k, pat) && !(k in front)) && push!(front, k)
        end
        sel = vcat(front, String[k for k in sel if !(k in front)])
    end

    return sel
end

function _resolve_fe(fixedeffects, mds, nm)
    if fixedeffects === nothing
        names = String[]
        for md in mds, (nme, _) in md.fixedeffects
            nme in names || push!(names, nme)
        end
        isempty(names) && return Pair{String,Vector{Bool}}[]
        out = Pair{String,Vector{Bool}}[]
        for nme in names
            flags = Bool[any(p -> first(p) == nme && last(p), md.fixedeffects) for md in mds]
            push!(out, nme => flags)
        end
        return out
    else
        out = Pair{String,Vector{Bool}}[]
        for (nme, v) in fixedeffects
            flags = v isa Bool ? fill(v, nm) : Vector{Bool}(collect(v))
            push!(out, string(nme) => flags)
        end
        return out
    end
end

# --- header / merging helpers (shared with other builders) ---

# Merge consecutive equal strings into (value, runlength) segments.
function _merge_equal(xs)
    segs = Tuple{String,Int}[]
    for x in xs
        s = string(x)
        if !isempty(segs) && segs[end][1] == s
            segs[end] = (s, segs[end][2] + 1)
        else
            push!(segs, (s, 1))
        end
    end
    return segs
end

# A leading label cell + per-column labels merged on adjacent equals into
# centered \multicolumn cells. Returns (cells, spans) of merged column ranges.
function _merged_row(leadlabel, labels_vec)
    segs = _merge_equal(labels_vec)
    cells = TabXCell[TabXCell(string(leadlabel))]
    spans = Tuple{Int,Int}[]
    col = 2
    for (lab, span) in segs
        push!(cells, TabXCell(lab; span=span, align=:c))
        span > 1 && push!(spans, (col, col + span - 1))
        col += span
    end
    return cells, spans
end

# Interpret a `groups` argument as multi-level headers: a Matrix (each row a
# level) or a vector of vectors. Returns `nothing` for the pair form.
function _group_levels(groups)
    if groups isa AbstractMatrix
        return [String[string(groups[i, j]) for j in 1:size(groups, 2)] for i in 1:size(groups, 1)]
    elseif groups isa AbstractVector && !isempty(groups) && first(groups) isa AbstractVector
        return [String[string(x) for x in lvl] for lvl in groups]
    else
        return nothing
    end
end

# The cell printed under each estimate. Empty (NaN/dropped) values render blank.
_paren(s) = isempty(s) ? "" : "(" * s * ")"
function _below_str(below::Symbol, coef, se; digits, confint_z)
    if below === :tstat
        return _paren(fmt_number(coef / se; digits=digits))
    elseif below === :confint
        lo = fmt_number(coef - confint_z * se; digits=digits)
        hi = fmt_number(coef + confint_z * se; digits=digits)
        return (isempty(lo) || isempty(hi)) ? "" : "[" * lo * ", " * hi * "]"
    else  # :se
        return _paren(fmt_number(se; digits=digits))
    end
end

# Normalize one `extralines` entry into a full row of `ncols` cells.
function _extraline_cells(r, ncols)
    vals = collect(r)
    if length(vals) == ncols
        return TabXCell[TabXCell(string(v)) for v in vals]
    elseif length(vals) == ncols - 1
        return vcat(TabXCell(""), TabXCell[TabXCell(string(v)) for v in vals])
    else
        throw(ArgumentError("extralines row needs $(ncols) or $(ncols - 1) entries; got $(length(vals))"))
    end
end
