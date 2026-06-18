# Runnable source for every example in the README. Each block prints a marker
# (----- <id> -----) + the LaTeX output, AND collects the tables into one
# compilable file at  latex/examples.tex  (gitignored) for visual checking /
# screenshots. Run from the package root:  julia --startup-file=no docs/examples.jl

using Pkg
Pkg.activate(mktempdir())
Pkg.develop(path = dirname(@__DIR__))
Pkg.add(["GLM", "DataFrames"])

using LaTeXTabX, GLM, DataFrames, Statistics

# Deterministic synthetic panel (no RNG, so output is reproducible).
n = 500
idx = collect(1:n)
df = DataFrame(
    firm = repeat(1:50, inner = 10),
    year = repeat(2010:2019, outer = 50),
    x    = idx ./ n,
    z    = float.(idx .% 5),
    w    = cos.(idx ./ 7),
)
df.y = 0.5 .+ 2.0 .* df.x .- 0.3 .* df.z .+ 0.15 .* df.w .+ 0.4 .* cos.(3.0 .* idx)
df.b = Int.((df.y .- 1.0 .+ 0.6 .* cos.(5.0 .* idx)) .> 0)

m1    = lm(@formula(y ~ x), df)
m2    = lm(@formula(y ~ x + z), df)
m3    = lm(@formula(y ~ x + z + w), df)
logit = glm(@formula(b ~ x + z), df, Binomial(), LogitLink())

const TABLES = Tuple{String,String}[]    # (title, latex)
function emit(id, title, t)
    s = to_latex(t)
    println("\n----- ", id, " -----")
    println(s)
    push!(TABLES, (title, s))
    return t
end

# =========================================================================
# Regression tables  (latexreg)
# =========================================================================

emit("reg-basic", "latexreg — minimal", latexreg(m1, m2))

emit("reg-full", "latexreg — relabel, estimator row, rich statistics", latexreg(m1, m2, logit;
    labels        = Dict("x" => "Main Regressor", "z" => "Control", "(Intercept)" => "Constant"),
    depvar_labels = ["y", "y", "b"],
    order         = ["x", "z"],
    estimator     = :auto,
    stats         = [:nobs, :r2, :adjr2, :aic, :bic, :r2_mcfadden],
    notes         = ["Standard errors in parentheses. \$^{*}p<0.1\$, \$^{**}p<0.05\$, \$^{***}p<0.01\$."]))

emit("reg-headers", "latexreg — matrix multi-level headers", latexreg(m2, m3, m2, m3;
    labels   = Dict("x" => "Main Regressor", "z" => "Control", "w" => "Extra"),
    drop     = [r"Intercept"],
    depvar   = false,
    number_regressions = false,
    groups   = ["Sample A"   "Sample A"   "Sample B"   "Sample B"
                "Short"      "Long"       "Short"      "Long"],
    stats    = [:nobs, :adjr2]))

emit("reg-custom", "latexreg — controls indicator, t-stats, manual FE, custom stat", latexreg(m2, m3;
    labels       = Dict("x" => "Main Regressor"),
    keep         = ["x"],
    below        = :tstat,
    fixedeffects = ["Firm" => true, "Year" => [true, false]],
    stats        = [:nobs, :adjr2, "RMSE" => (m -> sqrt(sum(abs2, residuals(m)) / dof_residual(m)))],
    extralines   = [["Sample", "Full", "Full"]]))

emit("reg-fe-compact", "latexreg — compact FE (suffix) + tick / blank markers", latexreg(m2, m3;
    labels       = Dict("x" => "Main Regressor", "z" => "Control", "w" => "Extra"),
    drop         = [r"Intercept"],
    fixedeffects = ["Date" => true, "Firm" => [true, false]],
    fe_style     = :compact,
    yes          = "\\checkmark",
    no           = "",
    stats        = [:nobs, :adjr2]))

emit("reg-se-override", "latexreg — override SEs (post-estimation clustering, e.g. for GLM)", latexreg(m2, m2;
    labels         = Dict("x" => "Main Regressor", "z" => "Control", "(Intercept)" => "Constant"),
    ses            = [nothing, Dict("x" => 1.2, "z" => 0.25, "(Intercept)" => 0.3)],
    se_labels      = ["Classical", "Clustered"],
    cluster_labels = [nothing, "Firm"]))

# =========================================================================
# Summary statistics  (latexsummary)
# =========================================================================

emit("sum-panels", "latexsummary — panels", latexsummary(df;
    stats  = [:mean, :std, :min, :median, :max],
    panels = ["Regressors:" => [:x, :z, :w], "Outcomes:" => [:y, :b]],
    labels = Dict("x" => "Main Regressor", "z" => "Control", "w" => "Extra",
                  "y" => "Outcome", "b" => "Event")))

emit("sum-custom", "latexsummary — custom statistic", latexsummary(df;
    vars   = [:x, :z, :y],
    stats  = [:n, :mean, :std, "IQR" => (v -> quantile(v, 0.75) - quantile(v, 0.25))],
    labels = Dict("x" => "Main Regressor", "z" => "Control", "y" => "Outcome")))

# =========================================================================
# Correlation tables  (latexcorr)
# =========================================================================

emit("corr-clean", "latexcorr — Pearson + Spearman", latexcorr(df;
    methods = [:pearson, :spearman],
    vars    = [:x, :z, :y],
    labels  = Dict("x" => "Size", "z" => "Age", "y" => "Return")))

emit("corr-groups", "latexcorr — column groups + lower triangle", latexcorr(df;
    vars       = [:x, :z, :w, :y],
    methods    = [:pearson],
    lower      = true,
    col_groups = ["Firm characteristics" => 1:3],
    labels     = Dict("x" => "Size", "z" => "Age", "w" => "Volatility", "y" => "Return"),
    col_labels = Dict("x" => "Size", "z" => "Age", "w" => "Vol.")))

# =========================================================================
# Plain tables  (latextable)
# =========================================================================

emit("tab-basic", "latextable — a DataFrame", latextable(first(df, 4)))

emit("tab-custom", "latextable — selected columns, relabeled", latextable(first(df, 4);
    vars   = [:firm, :year, :x, :y],
    labels = Dict("firm" => "Firm", "year" => "Year"),
    digits = 4))

# =========================================================================
# Custom multi-panel tables  (latexpanel / panel)
# =========================================================================

emit("panel", "latexpanel — hand-built panels", latexpanel(
    [
        panel("Panel A: Levels",
            ["Mean",   0.072, 0.132, "\$-0.060^{***}\$"],
            :rule,
            ["Median", "\$0.061\$", "\$0.098\$", "\$-0.037^{***}\$"]),
        panel("Panel B: Counts", ["N (managers)", "670", "2,890"]),
    ];
    header = ["High", "Low", "Difference"],
    notes  = ["Hand-built: numbers auto-format, strings pass through verbatim."]))

# --- write one compilable LaTeX file with every table ---
const PREAMBLE = raw"""
\documentclass[11pt]{article}
\usepackage[a4paper,margin=1.5cm]{geometry}
\usepackage{tabularx}
\usepackage{booktabs}
\usepackage{amsmath}
\usepackage{amssymb}
\newcolumntype{Y}{>{\centering\arraybackslash}X}
\setlength{\parindent}{0pt}
\pagestyle{empty}
\begin{document}
\begin{center}\Large\textbf{LaTeXTabX — rendered example tables}\end{center}
\bigskip
"""

outdir = joinpath(dirname(@__DIR__), "latex")
mkpath(outdir)
open(joinpath(outdir, "examples.tex"), "w") do io
    print(io, PREAMBLE)
    for (i, (title, tex)) in enumerate(TABLES)
        println(io, "\\textbf{Table $(i). \\texttt{$(replace(title, "_" => "\\_"))}}\\\\[4pt]")
        println(io, tex)
        println(io, "\\bigskip\n")
    end
    println(io, "\\end{document}")
end
println("\nwrote: ", joinpath(outdir, "examples.tex"))
println("EXAMPLES_OK")
