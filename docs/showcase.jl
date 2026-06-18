# One comprehensive, renderable showcase of LaTeXTabX across all backends.
# Prints each table's LaTeX to stdout AND writes a single compilable document at
# latex/showcase.tex (gitignored) -> compile to showcase.pdf for screenshots.
# Installs GLM + FixedEffectModels + StagDiDModels + Regress, so it is heavy.
# Run from the package root:  julia --startup-file=no docs/showcase.jl
#
# The dataset tells one story: a corporate-finance panel (firms x years) where a
# staggered "treatment" affects ROA; we also have instruments and a binary
# distress outcome. Different builders/backends view different slices of it.

using Pkg
Pkg.activate(mktempdir())
Pkg.develop(path = dirname(@__DIR__))
Pkg.add(["GLM", "DataFrames", "StatsModels", "FixedEffectModels"])
Pkg.add(url = "https://github.com/eohne/StagDiDModels.jl")
Pkg.add(url = "https://github.com/gragusa/Regress.jl")

using LaTeXTabX, DataFrames, Statistics
using GLM, FixedEffectModels, StagDiDModels
import Regress
using StatsModels: @formula

# ---------------------------------------------------------------- collection ---
const SECTIONS = String[]
const TABLES = Tuple{String,String,String,String}[]   # (section, title, desc, latex)
function emit(section, title, desc, t)
    s = to_latex(t)
    println("\n----- ", title, " -----")
    println(s)
    section in SECTIONS || push!(SECTIONS, section)
    push!(TABLES, (section, title, desc, s))
    return t
end

# ============================================================ data: GLM panel ==
N, T = 60, 12
n = N * T
idx = collect(1:n)
df = DataFrame(
    firm = repeat(1:N, inner = T),
    year = repeat(2008:(2008 + T - 1), outer = N),
    treat = 0.5 .+ 0.5 .* cos.(idx ./ 7),                 # treatment intensity
    lev   = 0.30 .+ 0.20 .* sin.(idx ./ 5),               # leverage
    size  = 4.0 .+ 0.8 .* cos.(idx ./ 11) .+ 0.002 .* idx, # firm size
)
df.roa = 0.5 .+ 1.6 .* df.treat .- 0.4 .* df.lev .+ 0.10 .* df.size .+ 0.35 .* cos.(3.0 .* idx)
df.distress = Int.((0.4 .* df.lev .- 0.3 .* df.treat .+ 0.5 .* cos.(5.0 .* idx)) .> 0.15)

reglabels = Dict("treat" => "Treatment", "lev" => "Leverage", "size" => "Size",
                 "(Intercept)" => "Constant")

m1    = lm(@formula(roa ~ treat), df)
m2    = lm(@formula(roa ~ treat + lev), df)
m3    = lm(@formula(roa ~ treat + lev + size), df)
logit = glm(@formula(distress ~ treat + lev), df, Binomial(), LogitLink())

# ================================================== Section: Regression tables ==
emit("Regression tables", "Main results — OLS and Logit side by side",
    "Estimator row, relabelling, reordering, and a rich statistics block; pseudo-R\$^2\$ fills in for the logit.",
    latexreg(m1, m2, logit;
        labels        = reglabels,
        depvar_labels = ["ROA", "ROA", "Distress"],
        order         = ["treat", "lev"],
        estimator     = :auto,
        stats         = [:nobs, :r2, :adjr2, :aic, :bic, :r2_mcfadden],
        notes         = ["Standard errors in parentheses. \$^{*}p<0.1\$, \$^{**}p<0.05\$, \$^{***}p<0.01\$."]))

emit("Regression tables", "Spanning multi-level headers",
    "Adjacent equal labels merge into a \\texttt{\\textbackslash multicolumn} with a \\texttt{\\textbackslash cmidrule}; intercept dropped, automatic \"Controls\" row.",
    latexreg(m2, m3, m2, m3;
        labels  = reglabels,
        drop    = [r"Intercept"],
        depvar  = false,
        number_regressions = false,
        groups  = ["Subsample A" "Subsample A" "Subsample B" "Subsample B"
                   "Short"       "Long"        "Short"       "Long"],
        stats   = [:nobs, :adjr2]))

emit("Regression tables", "Post-estimation clustered SEs (e.g. for GLM)",
    "GLM cannot cluster natively: feed SEs via \\texttt{ses}; p-values and stars are recomputed. \\texttt{se\\_labels}/\\texttt{cluster\\_labels} fill the bottom rows.",
    latexreg(m2, m2;
        labels         = reglabels,
        depvar_labels  = ["ROA", "ROA"],
        ses            = [nothing, Dict("treat" => 0.45, "lev" => 0.18, "(Intercept)" => 0.30)],
        se_labels      = ["Classical", "Clustered"],
        cluster_labels = [nothing, "Firm"],
        stats          = [:nobs, :adjr2]))

# ============================================ data + tables: Fixed effects ======
N2, Tp = 50, 12
fdf = DataFrame(id = repeat(1:N2, inner = Tp), t = repeat(1:Tp, outer = N2))
fdf.treat = cos.(12.9898 .* fdf.id .+ 78.233 .* fdf.t)
fdf.ctrl  = cos.(fdf.id .+ fdf.t)
fdf.y = 0.8 .* fdf.treat .- 0.2 .* fdf.ctrl .+ 0.05 .* fdf.id .+ 0.1 .* fdf.t .+
        0.3 .* cos.(3.0 .* (fdf.id .+ fdf.t))

felabels = Dict("treat" => "Treatment", "ctrl" => "Control", "id" => "Firm", "t" => "Year", "y" => "Outcome")
fe_c = reg(fdf, @formula(y ~ treat + ctrl + fe(id) + fe(t)))                          # classical
fe_r = reg(fdf, @formula(y ~ treat + ctrl + fe(id) + fe(t)), Vcov.robust())           # robust
fe_1 = reg(fdf, @formula(y ~ treat + ctrl + fe(id) + fe(t)), Vcov.cluster(:id))       # one-way
fe_2 = reg(fdf, @formula(y ~ treat + ctrl + fe(id) + fe(t)), Vcov.cluster(:id, :t))   # two-way

emit("Regression tables", "Fixed effects with auto-detected standard errors",
    "FE rows from the model; the \"Std. errors\" / \"Cluster\" rows are read from each model's vcov — classical, robust, one-way and two-way clustering side by side.",
    latexreg(fe_c, fe_r, fe_1, fe_2;
        labels = felabels,
        stats  = [:nobs, :r2_within],
        notes  = ["SE type and clustering variables are detected from each fitted model."]))

# ============================================ data + tables: Regress SE kinds ===
rsd = DataFrame(firm = repeat(1:30, inner = 8), x = (collect(1:240) .% 5) ./ 5, w = cos.(1:240))
rsd.y = 1.0 .+ 0.7 .* rsd.x .- 0.3 .* rsd.w .+ 0.3 .* cos.(3.0 .* (1:240))
r_hc1 = Regress.ols(rsd, @formula(y ~ x + w))
r_hc3 = Regress.ols(rsd, @formula(y ~ x + w)) + Regress.vcov(Regress.HC3())
r_cr  = Regress.ols(rsd, @formula(y ~ x + w), save_cluster = :firm) + Regress.vcov(Regress.CR1(:firm))

emit("Regression tables", "Precise SE types from Regress.jl",
    "Regress.jl exposes the exact estimator, so HC1 / HC3 / cluster-robust are printed precisely (via CovarianceMatrices.jl).",
    latexreg(r_hc1, r_hc3, r_cr;
        labels = Dict("x" => "Treatment", "w" => "Control", "firm" => "Firm", "y" => "Outcome"),
        stats  = [:nobs, :r2]))

# ============================================ data + tables: staggered DiD =======
Nd, Td = 120, 20
sdf = DataFrame(unit = repeat(1:Nd, inner = Td), year = repeat(collect(2000:2019), outer = Nd))
sdf.g = map(u -> u <= Nd ÷ 3 ? 0 : (u <= 2Nd ÷ 3 ? 2008 : 2014), sdf.unit)
sdf.d = Int.((sdf.g .> 0) .& (sdf.year .>= sdf.g))
sdf.dep_var = (sdf.unit .% 7) ./ 3 .+ (sdf.year .- 2000) .* 0.05 .+
              0.8 .* sdf.d .+ 0.3 .* cos.(3.0 .* sdf.unit .+ sdf.year)

twfe    = fit_twfe_static(sdf;    y = :dep_var, id = :unit, t = :year, g = :g, cluster = :unit)
gardner = fit_gardner_static(sdf; y = :dep_var, id = :unit, t = :year, g = :g, cluster = :unit)
bjs     = fit_bjs_static(sdf;     y = :dep_var, id = :unit, t = :year, g = :g, cluster = :unit)

emit("Regression tables", "Staggered DiD — three estimators",
    "Modern heterogeneity-robust estimators side by side; the estimator row names each method from StagDiDModels.jl.",
    latexreg(twfe, gardner, bjs;
        labels             = Dict("_ATT" => "ATT", "dep_var" => "Outcome"),
        estimator          = :show,
        number_regressions = false,
        stats              = [:nobs],
        notes              = ["Static ATT, SE clustered by unit."]))

# ============================================ data + tables: IV / k-class ========
ivd = DataFrame(z1 = cos.(1:500), z2 = sin.(2.0 .* (1:500)), x = ((1:500) .% 5) ./ 5)
ivd.endo = 0.5 .* ivd.z1 .+ 0.3 .* ivd.z2 .+ 0.2 .* cos.(3.0 .* (1:500))
ivd.y = 1.0 .+ 0.8 .* ivd.endo .+ 0.4 .* ivd.x .+ 0.3 .* sin.(1.7 .* (1:500))
ols  = Regress.ols(ivd, @formula(y ~ x + endo))
tsls = Regress.iv(Regress.TSLS(), ivd, @formula(y ~ x + (endo ~ z1 + z2)))
liml = Regress.iv(Regress.LIML(), ivd, @formula(y ~ x + (endo ~ z1 + z2)))

emit("Regression tables", "Instrumental variables / k-class",
    "OLS vs 2SLS vs LIML; the estimator row reports the method and the realized \$\\kappa\$ for LIML.",
    latexreg(ols, tsls, liml;
        labels    = Dict("endo" => "Investment", "x" => "Control", "(Intercept)" => "Constant", "y" => "Outcome"),
        estimator = :auto,
        stats     = [:nobs, :r2],
        notes     = ["Instruments: z1, z2."]))

emit("Regression tables", "Compact fixed-effect markers",
    "\\texttt{fe\\_style=:compact} folds the FE label into the row; ticks for \"yes\", blank for \"no\".",
    latexreg(m2, m3;
        labels       = reglabels,
        drop         = [r"Intercept"],
        depvar_labels = ["ROA", "ROA"],
        fixedeffects = ["Industry" => true, "Year" => [true, false]],
        fe_style     = :compact,
        yes = "\\checkmark", no = "",
        stats = [:nobs, :adjr2]))

# ================================================ Section: Summary statistics ===
emit("Summary statistics", "Descriptives grouped into panels",
    "Variables split into labelled sub-blocks; any set of statistics, in any order.",
    latexsummary(df;
        stats  = [:mean, :std, :min, :median, :max],
        panels = ["Treatment \\& controls:" => [:treat, :lev, :size], "Outcomes:" => [:roa, :distress]],
        labels = Dict("treat" => "Treatment", "lev" => "Leverage", "size" => "Size",
                      "roa" => "ROA", "distress" => "Distress")))

emit("Summary statistics", "A custom statistic alongside built-ins",
    "Pass \\texttt{\"Label\" => f(vector)} for anything not built in (here the inter-quartile range).",
    latexsummary(df;
        vars   = [:treat, :lev, :roa],
        stats  = [:n, :mean, :std, "IQR" => (v -> quantile(v, 0.75) - quantile(v, 0.25))],
        labels = Dict("treat" => "Treatment", "lev" => "Leverage", "roa" => "ROA")))

# ==================================================== Section: Correlation =======
emit("Correlation tables", "Pearson and Spearman, stacked",
    "Each method is its own block; a clean square matrix with no redundant labels.",
    latexcorr(df;
        methods = [:pearson, :spearman],
        vars    = [:treat, :lev, :size, :roa],
        labels  = Dict("treat" => "Treatment", "lev" => "Leverage", "size" => "Size", "roa" => "ROA")))

emit("Correlation tables", "Grouped columns, lower triangle",
    "Multi-level column header (every top-level group underlined) with the lower triangle only.",
    latexcorr(df;
        vars       = [:treat, :lev, :size, :roa],
        methods    = [:pearson],
        lower      = true,
        col_groups = ["Firm characteristics" => 1:3],
        labels     = Dict("treat" => "Treatment", "lev" => "Leverage", "size" => "Size", "roa" => "ROA"),
        col_labels = Dict("treat" => "Treat.", "lev" => "Lev.", "size" => "Size")))

# ==================================================== Section: Plain & panels ====
emit("Plain tables and hand-built panels", "A DataFrame, printed cleanly",
    "Column names as the header, no row-number column; integers stay integers, strings are escaped.",
    latextable(first(select(df, [:firm, :year, :treat, :roa]), 5);
        labels = Dict("firm" => "Firm", "year" => "Year", "treat" => "Treatment", "roa" => "ROA"),
        digits = 3))

emit("Plain tables and hand-built panels", "Fully hand-built multi-panel table",
    "Numbers auto-format, strings pass through verbatim — for bespoke layouts the builders don't cover.",
    latexpanel(
        [
            panel("Panel A: Average returns",
                ["Equal-weighted", 0.072, 0.132, "\$-0.060^{***}\$"],
                :rule,
                ["Value-weighted", "\$0.061\$", "\$0.098\$", "\$-0.037^{**}\$"]),
            panel("Panel B: Sample",
                ["Funds", "1,287", "412"],
                ["Manager-months", "84,230", "21,905"]),
        ];
        header = ["High skill", "Low skill", "Difference"],
        notes  = ["Spread portfolios sorted on estimated skill; Newey-West \$t\$-statistics."]))

# ----------------------------------------------------- write the showcase file ---
const PREAMBLE = raw"""
\documentclass[11pt]{article}
\usepackage[a4paper,margin=2cm]{geometry}
\usepackage{tabularx}
\usepackage{booktabs}
\usepackage{amsmath}
\usepackage{amssymb}
\newcolumntype{Y}{>{\centering\arraybackslash}X}
\setlength{\parindent}{0pt}
\usepackage{parskip}
\begin{document}
\begin{center}
  {\LARGE\textbf{LaTeXTabX}}\\[3pt]
  {\large A showcase of publication-style tables generated from Julia}
\end{center}
\vspace{1.5em}
"""

outdir = joinpath(dirname(@__DIR__), "latex")
mkpath(outdir)
open(joinpath(outdir, "showcase.tex"), "w") do io
    print(io, PREAMBLE)
    current = ""
    tnum = 0
    for (section, title, desc, tex) in TABLES
        tnum > 0 && println(io, "\\clearpage")   # one table per page for clean screenshots
        if section != current
            current = section
            println(io, "\\section*{$(section)}")
        end
        tnum += 1
        println(io, "\\textbf{Table $(tnum). $(title)}\\\\[1pt]")
        println(io, "{\\small\\itshape $(desc)}\\\\[5pt]")
        println(io, tex)
        println(io, "\\bigskip\n")
    end
    println(io, "\\end{document}")
end
println("\nwrote: ", joinpath(outdir, "showcase.tex"))
println("SHOWCASE_OK")
