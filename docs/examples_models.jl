# Backend-heavy examples: different estimators side by side (staggered DiD, IV /
# k-class, fixed effects). Installs FixedEffectModels + StagDiDModels + Regress,
# so it is slower than docs/examples.jl. Writes a compilable file at
# latex/examples_models.tex (gitignored). Run from the package root:
#   julia --startup-file=no docs/examples_models.jl

using Pkg
Pkg.activate(mktempdir())
Pkg.develop(path = dirname(@__DIR__))
Pkg.add(["DataFrames", "StatsModels", "FixedEffectModels"])
Pkg.add(url = "https://github.com/eohne/StagDiDModels.jl")
Pkg.add(url = "https://github.com/gragusa/Regress.jl")

using LaTeXTabX, DataFrames, FixedEffectModels, StagDiDModels, Regress
using StatsModels: @formula

const TABLES = Tuple{String,String}[]
function emit(id, title, t)
    s = to_latex(t)
    println("\n----- ", id, " -----")
    println(s)
    push!(TABLES, (title, s))
    return t
end

# =========================================================================
# Staggered DiD — several estimators side by side (static ATT)
# =========================================================================
N, T = 120, 20
sdf = DataFrame(unit = repeat(1:N, inner = T), year = repeat(collect(2000:2019), outer = N))
sdf.g = map(u -> u <= N ÷ 3 ? 0 : (u <= 2N ÷ 3 ? 2008 : 2014), sdf.unit)
sdf.d = Int.((sdf.g .> 0) .& (sdf.year .>= sdf.g))
sdf.dep_var = (sdf.unit .% 7) ./ 3 .+ (sdf.year .- 2000) .* 0.05 .+
              0.8 .* sdf.d .+ 0.3 .* cos.(3.0 .* sdf.unit .+ sdf.year)

twfe    = fit_twfe_static(sdf;    y = :dep_var, id = :unit, t = :year, g = :g, cluster = :unit)
gardner = fit_gardner_static(sdf; y = :dep_var, id = :unit, t = :year, g = :g, cluster = :unit)
bjs     = fit_bjs_static(sdf;     y = :dep_var, id = :unit, t = :year, g = :g, cluster = :unit)

emit("did", "Staggered DiD — TWFE / Gardner / BJS (static ATT)", latexreg(twfe, gardner, bjs;
    labels             = Dict("_ATT" => "ATT"),
    estimator          = :show,
    number_regressions = false,
    stats              = [:nobs],
    notes              = ["Static ATT; SE clustered by unit. Estimator names follow StagDiDModels.jl."]))

# =========================================================================
# Instrumental variables / k-class — OLS / 2SLS / LIML side by side
# =========================================================================
n = 500
idx = collect(1:n)
ivd = DataFrame(z1 = cos.(idx), z2 = sin.(2.0 .* idx), x = (idx .% 5) ./ 5)
ivd.endo = 0.5 .* ivd.z1 .+ 0.3 .* ivd.z2 .+ 0.2 .* cos.(3.0 .* idx)
ivd.y = 1.0 .+ 0.8 .* ivd.endo .+ 0.4 .* ivd.x .+ 0.3 .* sin.(1.7 .* idx)

ols  = Regress.ols(ivd, @formula(y ~ x + endo))
tsls = Regress.iv(Regress.TSLS(), ivd, @formula(y ~ x + (endo ~ z1 + z2)))
liml = Regress.iv(Regress.LIML(), ivd, @formula(y ~ x + (endo ~ z1 + z2)))

emit("iv", "IV — OLS / 2SLS / LIML (k-class) side by side", latexreg(ols, tsls, liml;
    labels    = Dict("endo" => "Endogenous", "x" => "Control", "(Intercept)" => "Constant"),
    estimator = :auto,
    stats     = [:nobs, :r2],
    notes     = ["Instruments: z1, z2. LIML shows the realized \$\\kappa\$."]))

# =========================================================================
# Regress.jl — precise SE detection (HC / HAC / cluster), read from the model
# =========================================================================
rn = 240
ridx = collect(1:rn)
rsd = DataFrame(firm = repeat(1:30, inner = 8), x = (ridx .% 5) ./ 5, w = cos.(ridx))
rsd.y = 1.0 .+ 0.7 .* rsd.x .- 0.3 .* rsd.w .+ 0.3 .* cos.(3.0 .* ridx)

r_hc1 = Regress.ols(rsd, @formula(y ~ x + w))                                          # default HC1
r_hc3 = Regress.ols(rsd, @formula(y ~ x + w)) + vcov(HC3())                            # HC3
r_cr  = Regress.ols(rsd, @formula(y ~ x + w), save_cluster = :firm) + vcov(CR1(:firm)) # clustered

emit("regress-se", "Regress.jl — SE type read from the model (HC1 / HC3 / clustered)", latexreg(r_hc1, r_hc3, r_cr;
    labels = Dict("x" => "Treatment", "w" => "Control", "firm" => "Firm"),
    stats  = [:nobs, :r2],
    notes  = ["SE type auto-detected from each model's vcov estimator (CovarianceMatrices.jl)."]))

# =========================================================================
# Fixed effects — FixedEffectModels, clustered SE, within-R^2, F
# =========================================================================
N2, Tp = 40, 10
fdf = DataFrame(id = repeat(1:N2, inner = Tp), t = repeat(1:Tp, outer = N2))
fdf.x = cos.(12.9898 .* fdf.id .+ 78.233 .* fdf.t)
fdf.w = cos.(fdf.id .+ fdf.t)
fdf.y = 0.8 .* fdf.x .- 0.2 .* fdf.w .+ 0.05 .* fdf.id .+ 0.1 .* fdf.t .+
        0.3 .* cos.(3.0 .* (fdf.id .+ fdf.t))

# Same specification, four different covariance estimators — the "Std. errors"
# row is auto-detected from each model's vcov and may differ across columns.
fe_c = reg(fdf, @formula(y ~ x + w + fe(id) + fe(t)))                          # classical
fe_r = reg(fdf, @formula(y ~ x + w + fe(id) + fe(t)), Vcov.robust())          # robust / White
fe_1 = reg(fdf, @formula(y ~ x + w + fe(id) + fe(t)), Vcov.cluster(:id))      # one-way
fe_2 = reg(fdf, @formula(y ~ x + w + fe(id) + fe(t)), Vcov.cluster(:id, :t))  # two-way

emit("fe", "FixedEffectModels — SE auto-detected per model (classical / robust / clustered)", latexreg(fe_c, fe_r, fe_1, fe_2;
    labels = Dict("x" => "Treatment", "w" => "Control", "id" => "Unit", "t" => "Period"),
    stats  = [:nobs, :r2_within],
    notes  = ["SE type auto-detected from each model's vcov; the cluster variable goes in its own row."]))

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
\begin{center}\Large\textbf{LaTeXTabX — backend example tables}\end{center}
\bigskip
"""

outdir = joinpath(dirname(@__DIR__), "latex")
mkpath(outdir)
open(joinpath(outdir, "examples_models.tex"), "w") do io
    print(io, PREAMBLE)
    for (i, (title, tex)) in enumerate(TABLES)
        println(io, "\\textbf{Model table $(i). $(title)}\\\\[4pt]")
        println(io, tex)
        println(io, "\\bigskip\n")
    end
    println(io, "\\end{document}")
end
println("\nwrote: ", joinpath(outdir, "examples_models.tex"))
println("MODELS_OK")
