# LaTeXTabX.jl — API Reference

Complete reference for **LaTeXTabX.jl**, a package that renders publication-style
LaTeX tables (`tabularx` + `booktabs`) from `DataFrame`s and fitted regression
models. This document is self-contained: it is meant to let an agent wire the
package into another project without reading the source.

- For a visual gallery of every table type, see [`../README.md`](../README.md).
- The runnable source of the gallery is [`showcase.jl`](showcase.jl).

---

## 1. Installation & loading

```julia
using Pkg
Pkg.add(url = "https://github.com/<owner>/LaTeXTabX.jl")   # not registered
# local dev: Pkg.develop(path = "path/to/RegressionTable_TabX")

using LaTeXTabX
```

Model-backend support (GLM, FixedEffectModels, StagDiDModels, Regress) loads
**automatically** via package extensions the moment both LaTeXTabX and that package
are loaded — no extra imports. Extensions are keyed by package UUID, so the model
package need not be registered.

### LaTeX preamble (required to typeset the output)

```latex
\usepackage{tabularx}
\usepackage{booktabs}
\usepackage{amsmath}      % for $\times$, math in notes
\usepackage{amssymb}      % for \checkmark
\newcolumntype{Y}{>{\centering\arraybackslash}X}   % the default data column
```

---

## 2. Output model

- Every builder returns a **`TabXTable`** (an intermediate representation: a column
  spec + a vector of rows). Nothing is printed until you render it.
- Rendering: `to_latex(t)::String`, `write_latex(path, t)`, or pass `file="…"` to a
  builder. `display(t)` / `show(io, MIME"text/latex"(), t)` emits LaTeX (Pluto/Jupyter).
- The default render is a **bare `\begin{tabularx}…\end{tabularx}`** — no floating
  `table` wrapper, no caption — so it drops directly into a document. Set
  `float=true` to wrap in a `table` environment with `caption`/`label`/`centering`.
- **Cells are final LaTeX.** The builders format numbers and escape data where
  documented, but text you pass in `labels`, `notes`, `header`, panel labels, etc.
  is emitted verbatim. Escape `&`, `%`, `#`, `_` yourself in those, and use math
  mode for `<`/`>` (see §11 Gotchas).

---

## 3. Exports

```
# Builders
latexreg, latexsummary, latexcorr, latextable, latexpanel, panel
# IR types
TabXTable, TabXCell, TabXRow, TabXRule, TabXCmidRule, TabXRaw
# Rendering
to_latex, write_latex
# Model extraction (extensions add methods)
modeldata
```

Extension hooks (`_responsename`, `_estimator`, `_fixedeffects`, `_se_info`,
`_regstat_ext`) are **not** exported; reach them via `LaTeXTabX._se_info` or
`import LaTeXTabX: _se_info` (see §8).

---

## 4. `latexreg(models...; kwargs...) -> TabXTable`

Regression table from one or more fitted models. Models are read through the
StatsAPI `coeftable` interface plus extension hooks; pass them positionally (one
column each).

```julia
latexreg(m1, m2, logit;
    labels        = Dict("x" => "Treatment", "(Intercept)" => "Constant"),
    depvar_labels = ["y", "y", "z"],
    order         = ["x"],
    estimator     = :auto,
    stats         = [:nobs, :r2, :adjr2],
    file          = "table.tex")
```

### Coefficient selection & labelling

| Keyword | Type / default | Meaning |
|---|---|---|
| `labels` | `AbstractDict` = `Dict()` | Map raw coefficient **and** response **and** FE/cluster names to display labels. Applies everywhere a name is shown. |
| `keep` | `nothing` | Keep only these coefficients. `String`, `Regex`, or a vector of them. |
| `drop` | `nothing` | Drop these coefficients (same forms). |
| `order` | `nothing` | Force this leading order; remaining coefficients follow in first-seen order. |
| `drop_intercept` | `Bool` = `false` | Also drop `(Intercept)`. **Intercept is kept by default.** |

### Below-estimate line & stars

| Keyword | Type / default | Meaning |
|---|---|---|
| `below` | `Symbol` = `:se` | What prints under each estimate: `:se` (parentheses), `:tstat`, `:confint`, or `:none`. |
| `confint_z` | `Real` = `1.959964` | z multiplier for `below=:confint`. |
| `digits` | `Integer` = `3` | Decimals for coefficients/SEs. |
| `star_cutoffs` | `(0.01, 0.05, 0.1)` | p-value thresholds (descending) for significance stars. |
| `star_symbols` | `("***","**","*")` | Symbols matched to `star_cutoffs`. |

### Headers

| Keyword | Type / default | Meaning |
|---|---|---|
| `depvar` | `Bool` = `true` | Show the dependent-variable header row. |
| `depvar_labels` | `nothing` | Per-model response labels (overrides `labels`/auto). |
| `combine_depvar` | `Bool` = `true` | Merge adjacent equal response names into one spanning `\multicolumn`. |
| `depvar_rule` | `Bool` = `true` | `\cmidrule` under named depvar segments. |
| `groups` | `nothing` | Extra header level(s): either pairs `["A" => 1:3, "B" => 4:5]` (model-index ranges) **or** a matrix / vector-of-vectors where each row is a header level. Adjacent equal labels merge with a `\cmidrule`. |
| `group_rule` | `Bool` = `true` | `\cmidrule`s under `groups`. |
| `number_regressions` | `Bool` = `true` | The `(1) (2) …` row. |

### Estimator row

| Keyword | Type / default | Meaning |
|---|---|---|
| `estimator` | `Symbol` = `:auto` | `:auto` shows the row only when labels differ across models; `:show` always; `:none` never. |
| `estimator_position` | `Symbol` = `:top` | `:top` or `:bottom`. |
| `estimator_label` | `String` = `"Estimator"` | Row label. |
| `estimator_labels` | `nothing` | Override the per-model estimator strings (else taken from the backend). |

### Fixed-effect & controls indicator rows

| Keyword | Type / default | Meaning |
|---|---|---|
| `fixedeffects` | `nothing` | FE rows. `["Firm" => true, "Year" => [true,false]]` — a `Bool` (all models) or per-model `Vector{Bool}`. If omitted, FE-aware backends (FixedEffectModels) auto-fill. |
| `fe_style` | `Symbol` = `:block` | `:block` = a "Fixed Effects" header + indented rows; `:compact` = "Firm FE"/"Year FE" rows, no header. |
| `fe_title` | `String` = `"Fixed Effects"` | Header for `:block`. |
| `fe_suffix` | `String` = `" FE"` | Suffix appended in `:compact`. |
| `yes` / `no` | `"Yes"` / `"No"` | Indicator markers (FE + controls). E.g. `yes="\\checkmark", no=""`. |
| `print_controls` | `Bool` = `true` | Auto "Controls" row when a model has coefficients not shown. |
| `controls_label` | `String` = `"Controls"` | Its label. |

### Standard-error rows (auto-detected — see §7)

| Keyword | Type / default | Meaning |
|---|---|---|
| `print_se` | `Bool` = `true` | Show the "Std. errors" (type) row. |
| `se_label` | `String` = `"Std. errors"` | Its label. |
| `simple_label` | `String` = `"Classical"` | Text for a homoskedastic/classical model. |
| `robust_label` | `String` = `"Robust"` | Fallback text for robust SEs without a precise name. |
| `se_cluster_text` | `String` = `"Clustered"` | Text shown for a clustered model in the SE-type row. |
| `print_cluster` | `Bool` = `true` | Show the separate "Cluster" row (variable names). |
| `cluster_label` | `String` = `"Cluster"` | Its label. |
| `cluster_join` | `String` = `" \\& "` | Joiner for multi-way clusters (two-way → `\&`; interacted → set `" \$\\times\$ "`). |
| `se_collapse` | `Bool` = `true` | Drop an SE/Cluster row that is identical across all columns — **except** clustering, which is always shown when present. |
| `ses` | `nothing` | Per-model SE override; each entry `nothing`, a `Vector` of SEs, or a `coef => se` `Dict`. **Recomputes p-values + stars** (normal approximation). For GLM post-estimation clustering. |
| `se_labels` | `nothing` | Per-model free-text override of the SE-type cell (each entry `nothing` = auto). |
| `cluster_labels` | `nothing` | Per-model free-text override of the Cluster cell. |

### Statistics rows

| Keyword | Type / default | Meaning |
|---|---|---|
| `stats` | `[:nobs, :adjr2]` | Built-in symbols (§9) and/or `"Label" => f(model)` pairs. |
| `stat_labels` | `AbstractDict` | Override the default symbol→label map. |
| `stat_digits` | `Integer` = `3` | Decimals for statistics. |
| `extralines` | `nothing` | Extra rows: each a vector of cells (`["Sample","Full","Full"]`), placed after the stats block. |

### Table chrome & output

| Keyword | Type / default | Meaning |
|---|---|---|
| `notes` | `String[]` | Footnote rows (`\scriptsize \textit{…}`, full width). Use math mode for `<`. |
| `title` / `caption` | `nothing` | Caption (`caption` wins; only emitted when `float=true`). |
| `label` | `nothing` | `\label{…}` (float only). |
| `float` | `Bool` = `false` | Wrap in a `table` environment. |
| `position` | `String` = `"htb"` | Float placement. |
| `width` | `String` = `"\\textwidth"` | tabularx target width. |
| `colspec` | `nothing` | Full LaTeX column spec; overrides `labelcol`/`coltype`. |
| `coltype` | `String` = `"Y"` | Data-column type (`"X"`, `"c"`, `"S"`, `"D{.}{.}{-1}"`, …). |
| `labelcol` | `String` = `"l"` | First (label) column type. |
| `file` | `nothing` | Also write the `.tex` to this path. |

---

## 5. The other builders

### `latexsummary(data; kwargs...)` — descriptive statistics

`data`: any Tables.jl table or numeric matrix. One row per variable, one column per
statistic.

| Keyword | Default | Meaning |
|---|---|---|
| `stats` | `[:mean,:std,:q25,:median,:q75]` | Symbols (§9) and/or `"Label" => f(vector)`. |
| `panels` | `nothing` | `["Group A:" => [:a,:b], "Group B:" => [:c]]` — labelled row groups. Overrides `vars`. |
| `vars` | `nothing` | Variables when not using `panels` (default: all numeric). |
| `labels` | `Dict()` | Variable display labels. |
| `stat_labels` | builtin | Header labels for stats. |
| `digits` | `2` | Decimals. |
| `commas` | `true` | Thousands separators. |
| + `notes`, `title`/`caption`, `label`, `float`, `position`, `width`, `colspec`, `coltype`, `labelcol`, `file` | | as in `latexreg`. |

### `latexcorr(data; kwargs...)` — correlation matrix

| Keyword | Default | Meaning |
|---|---|---|
| `methods` | `[:pearson,:spearman]` | Each becomes a stacked block. `:pearson`, `:spearman`, or `"Label" => f(matrix)` for any custom correlation (Kendall, partial, …). |
| `vars` | `nothing` | Variables (default: all numeric). |
| `panels` | `nothing` | Group the variable **rows** into labelled sub-blocks. |
| `labels` | `Dict()` | Row labels. |
| `digits` | `3` | Decimals. |
| `diagonal` | `true` | Show the `1.000` diagonal. |
| `lower` | `false` | Lower triangle only. |
| `panel_labels` | `Dict(:pearson=>"Pearson",:spearman=>"Spearman")` | Block header text. |
| `bold_panel` | `true` | Bold the block header. |
| `col_groups` | `nothing` | Multi-level column header, e.g. `["Group" => 1:3]`. Every top-level header (grouped or single) is underlined. |
| `col_group_rule` | `true` | `\cmidrule`s under `col_groups`. |
| `col_labels` | `nothing` | Column-header labels distinct from row `labels`. |
| + chrome/output keywords | | as above. |

### `latextable(data; kwargs...)` — a clean DataFrame dump

Column names as the header, rows as the body, **no row-number column**.

| Keyword | Default | Meaning |
|---|---|---|
| `vars` | `nothing` | Columns to include, in order. |
| `header` | `nothing` | Override the whole header row (else `labels`/names). |
| `labels` | `Dict()` | Column display labels. |
| `digits` | `3` | Decimals for `Real`s. |
| `commas` | `false` | Thousands separators. |
| `escape` | `true` | Escape `&%#_` in string cells. (`Bool`→`true`/`false` text, `Integer` kept exact.) |
| + chrome/output keywords | | as above. |

### `latexpanel(panels; kwargs...)` and `panel(label, rows...)` — hand-built tables

For bespoke multi-panel layouts (Barras "scale & skill" / alpaca-style). A panel is
`panel("Panel A: …", row, …)` or `"Panel A: …" => [rows…]`. A row is a vector whose
entries are numbers (auto-formatted), strings (verbatim LaTeX, e.g.
`"\$-0.06^{***}\$"`), or `TabXCell`s. The marker `:rule` inserts a `\midrule`
inside a panel; short rows are padded with blanks.

| Keyword | Default | Meaning |
|---|---|---|
| `header` | `nothing` | Column header labels (excluding the row-label column). |
| `header_align` | `:c` | Header alignment. |
| `panel_format` | `s -> "\\textit{$(s)}"` | Function turning a panel label into LaTeX. |
| `digits` | `3` | Decimals for numeric entries. |
| `ncols` | `nothing` | Column count (inferred from `header`/widest row if omitted). |
| + `colspec`, `coltype`, `labelcol`, `width`, `notes`, `title`/`caption`, `label`, `float`, `position`, `file` | | as above. |

---

## 6. Intermediate representation (IR) & low-level construction

Every builder compiles to these; you can also build or post-process tables by hand.

```julia
TabXCell(text; span=1, align=:l, multicol=false)   # text is final LaTeX
TabXRow(cells::Vector{TabXCell})  |  TabXRow(cells...)
TabXRule(kind::Symbol)            # :top | :mid | :doublemid | :bottom
TabXCmidRule(spans::Vector{Tuple{Int,Int}})         # \cmidrule(lr){a-b} …
TabXRaw(latex::String)            # a verbatim line
TabXTable(ncols; colspec="l"*"Y"^(ncols-1), width="\\textwidth", rows=[],
          float=false, position="htb", caption="", label="", centering=true, notes=[])
```

A `TabXCell` is emitted as `\multicolumn` when it spans >1 column, when
`align != :l`, or when `multicol=true`. `TabXTable.rows` is a mutable
`Vector{AbstractTabXRow}` — `push!` onto it. `notes` render as full-width
`\scriptsize \textit{…}` rows before `\end{tabularx}`.

```julia
t = TabXTable(4; colspec = "lYYY")
push!(t.rows, TabXRule(:doublemid))
push!(t.rows, TabXRow([TabXCell(""), TabXCell("High"; align=:c),
                       TabXCell("Low"; align=:c), TabXCell("Diff"; align=:c)]))
push!(t.rows, TabXCmidRule([(2, 4)]))
push!(t.rows, TabXRow([TabXCell("Mean"), TabXCell("0.072"),
                       TabXCell("0.132"), TabXCell("\$-0.060^{***}\$")]))
push!(t.rows, TabXRule(:doublemid))
print(to_latex(t))
```

---

## 7. Standard-error detection

`latexreg` reads each fitted model's covariance estimator and prints two optional
rows:

- **"Std. errors"** — the *type*: `Classical`, `Robust`, a precise name
  (`HC0`–`HC5`, `HAC(Bartlett(5))`, …), or `Clustered`.
- **"Cluster"** — the clustering variable(s) when clustered, two-way joined by
  `\&` (interacted via `cluster_join=" $\times$ "`). Names relabel through `labels`.

Detection precision by backend:
- **Regress.jl** — exact kind via CovarianceMatrices.jl: `HC0`–`HC5`, HAC kernels
  with bandwidth, `CR0`–`CR3` cluster-robust (cluster names from the estimator).
- **FixedEffectModels.jl** — classical / robust / one- & two-way clustering, with
  cluster names from `nclusters`.
- Other backends fall back to `robust_label` / no row.

Behaviour: types may differ per column; an identical row collapses away
(`se_collapse=true`) **except** clustering, which is always surfaced. Disable with
`print_se=false` / `print_cluster=false`. Override per column with `se_labels` /
`cluster_labels`. Swap the actual SEs with `ses` (recomputes p-values + stars via a
normal approximation — for GLM, which can't cluster natively).

---

## 8. Backends & adding a new model type

A model works with `latexreg` if it implements the **StatsAPI `coeftable`**
interface. The extraction (`LaTeXTabX.modeldata`) reads, from `coeftable(m)`:
`.rownms` (coef names), `.cols` (col 1 = estimate, col 2 = SE), and `.pvalcol`
(index of the p-value column). It also calls `StatsAPI.nobs(m)` for `:nobs`.

Refine the presentation by adding methods to these (own-function, no piracy) hooks:

| Hook | Returns | Purpose |
|---|---|---|
| `StatsAPI.coeftable(m)` | a CoefTable-like with `.rownms`, `.cols`, `.pvalcol` | **Required.** Source of coefs/SEs/p-values. |
| `StatsAPI.nobs(m)` | `Int` | The `:nobs` statistic. |
| `LaTeXTabX._responsename(m)` | `String` | Dependent-variable header. Default: `StatsAPI.responsename`. |
| `LaTeXTabX._estimator(m)` | `String` | Estimator-row label. Default `""`. |
| `LaTeXTabX._fixedeffects(m)` | `Vector{Pair{String,Bool}}` | Auto FE rows. Default empty. |
| `LaTeXTabX._se_info(m)` | `(kind::Symbol, clustervars::Vector{String}, typelabel::String)` | SE detection. `kind ∈ (:simple,:robust,:cluster,:unknown)`; `typelabel` is a precise robust name (e.g. `"HC1"`) or `""`. Default `(:unknown, String[], "")`. |
| `LaTeXTabX._regstat_ext(s::Symbol, m)` | value or `missing` | Package-specific stats (e.g. `:r2_within`, `:fstat`). |

**Minimal example — bring in a foreign model (e.g. an R result via RCall).** A
plain struct + a NamedTuple `coeftable` is enough; no StatsBase dependency:

```julia
import LaTeXTabX
const StatsAPI = LaTeXTabX.StatsAPI
import LaTeXTabX: _responsename, _estimator, _fixedeffects, _se_info

struct ForeignModel
    coefnames::Vector{String}; coefs::Vector{Float64}
    ses::Vector{Float64}; zs::Vector{Float64}; pvals::Vector{Float64}
    n::Int; fe::Vector{Pair{String,Bool}}; clusters::Vector{String}; resp::String
end
StatsAPI.coeftable(m::ForeignModel) =
    (rownms = m.coefnames, cols = Any[m.coefs, m.ses, m.zs, m.pvals], pvalcol = 4)
StatsAPI.nobs(m::ForeignModel) = m.n
_responsename(m::ForeignModel) = m.resp
_estimator(m::ForeignModel)    = "Logit (BC)"
_fixedeffects(m::ForeignModel) = m.fe
_se_info(m::ForeignModel)      = (:cluster, m.clusters, "")

latexreg(fm1, fm2; labels = Dict(...), stats = [:nobs])   # just works
```

(This is exactly how the R/`alpaca` bias-corrected FE-logit bridge is built.)

---

## 9. Statistics catalogue

**`latexreg` `stats` symbols** (any unsupported one renders blank):
`:nobs :r2 :adjr2 :r2_within :r2_mcfadden :r2_coxsnell :r2_nagelkerke :r2_deviance
:aic :aicc :bic :loglikelihood :nullloglikelihood :deviance :nulldeviance :dof
:dof_residual :fstat :fstat_pval`. Plus custom `"Label" => f(model)` where `f`
receives the fitted model.

**`latexsummary` `stats` symbols**: `:mean :std :median :q25 :q75 :min :max :n
(:count) :sum`. Plus custom `"Label" => f(vector)`.

Default stat labels can be overridden via `stat_labels`.

---

## 10. Column types & alignment

All builders default data columns to `Y` (centered tabularx) and the first column
to `l`. Override with:
- `coltype="X"` (left-ragged fill), `"c"`/`"l"`/`"r"`, `"S"` (siunitx number
  alignment), `"D{.}{.}{-1}"` (dcolumn decimal alignment);
- `labelcol="l"` for the first column;
- `colspec="l S S S"` for a full custom spec (overrides `coltype`/`labelcol`).

`S`/`D` require the `siunitx`/`dcolumn` package in the preamble.

---

## 11. Gotchas & conventions

- **`<` and `>` in text** render as inverted marks. In `notes` and labels use math
  mode: `"\$^{*}p<0.1\$"`, not `"p<0.1"`.
- **`&`, `%`, `#`, `_`** are not auto-escaped in `labels`/`notes`/`header`/panel
  labels — escape them (`"Treatment \\& controls"`). `latextable` *does* escape
  string data cells (`escape=true`); `latexreg`/`latexsummary` values are formatted
  numbers, but their labels are verbatim.
- **Interactions are not auto-formatted.** A coefficient like `x:z` prints under
  whatever name the backend gives it; relabel via `labels` (e.g.
  `"x:z" => "\\hspace{5mm}\$\\times\$ z"`).
- **Output is bare `tabularx`.** Add the caption/float yourself or set `float=true`.
- **`ses` override** recomputes p-values with a normal (not t) approximation.
- The package needs `tabularx`, `booktabs`, the `Y` column type, and (for ticks /
  `$\times$`) `amssymb` / `amsmath`.
