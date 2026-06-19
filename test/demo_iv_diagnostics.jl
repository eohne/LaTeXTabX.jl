# Verify IV first-stage diagnostics (Kleibergen-Paap F + p, and Regress's
# robust / IID first-stage F) surface through the `stats` keyword, that they are
# blank for non-IV columns, and that the FixedEffectModels estimator label is
# correct (OLS vs IV). Unregistered backends -> installed by URL.
# Run from the package root:  julia --startup-file=no test/demo_iv_diagnostics.jl

using Pkg
Pkg.activate(mktempdir())
Pkg.develop(path = dirname(@__DIR__))
Pkg.add(["DataFrames", "StatsModels", "FixedEffectModels"])
Pkg.add(url = "https://github.com/gragusa/Regress.jl")

using LaTeXTabX, DataFrames, FixedEffectModels, Regress
using StatsModels: @formula
import LaTeXTabX: _estimator   # to check the estimator-label fix directly

n = 500
idx = collect(1:n)
df = DataFrame(z1 = cos.(idx), z2 = sin.(2.0 .* idx), x = (idx .% 5) ./ 5)
df.endo = 0.5 .* df.z1 .+ 0.3 .* df.z2 .+ 0.2 .* cos.(3.0 .* idx)
df.y = 1.0 .+ 0.8 .* df.endo .+ 0.4 .* df.x .+ 0.3 .* sin.(1.7 .* idx)

# ---------------------------------------------------------------- FixedEffectModels
fe_ols = reg(df, @formula(y ~ x + endo))
fe_iv  = reg(df, @formula(y ~ x + (endo ~ z1 + z2)))

# Estimator-label fix: OLS must read OLS (the old `F_kp !== nothing` check called
# every model IV because `F_kp` is always a Float64 field, NaN for non-IV).
@assert _estimator(fe_ols) == "OLS"        "fe OLS mislabelled: $(_estimator(fe_ols))"
@assert _estimator(fe_iv)  == "IV (2SLS)"  "fe IV mislabelled: $(_estimator(fe_iv))"

t_fe = latexreg(fe_ols, fe_iv;
    labels = Dict("endo" => "Endogenous", "x" => "Control", "(Intercept)" => "Constant"),
    estimator = :auto,
    stats = [:nobs, :r2, :F_kp, :p_kp])
s_fe = to_latex(t_fe)
println("\n===== FixedEffectModels (OLS vs IV) =====\n", s_fe)
@assert occursin("Kleibergen-Paap", s_fe) "KP rows missing from FE table"
# The KP F row must have a value in the IV column and a blank in the OLS column.
kp_line = first(filter(l -> occursin(raw"Kleibergen-Paap $F$", l), split(s_fe, '\n')))
cells = strip.(split(kp_line, '&'))
@assert cells[2] == "" "OLS column should have a blank KP F, got $(cells[2])"
@assert !isempty(cells[3]) && cells[3] != raw"\\" "IV column should have a KP F value"
println("FE KP F row: ", kp_line)

# ---------------------------------------------------------------- Regress
r_ols  = Regress.ols(df, @formula(y ~ x + endo))
r_tsls = Regress.iv(Regress.TSLS(), df, @formula(y ~ x + (endo ~ z1 + z2)))

t_rg = latexreg(r_ols, r_tsls;
    labels = Dict("endo" => "Endogenous", "x" => "Control", "(Intercept)" => "Constant"),
    estimator = :auto,
    stats = [:nobs, :r2, :F_kp, :p_kp, :firststage_F, :firststage_F_iid])
s_rg = to_latex(t_rg)
println("\n===== Regress (OLS vs 2SLS) =====\n", s_rg)
for needle in ("Kleibergen-Paap", "First-stage")
    @assert occursin(needle, s_rg) "Regress table missing '$needle'"
end
fsf = first(filter(l -> occursin(raw"First-stage $F$ (IID)", l), split(s_rg, '\n')))
cells = strip.(split(fsf, '&'))
@assert cells[2] == "" "OLS column should have a blank first-stage F (IID)"
@assert !isempty(cells[3]) && cells[3] != raw"\\" "2SLS column should have a first-stage F (IID) value"
println("Regress first-stage F (IID) row: ", fsf)

# ---------------------------------------------------------------- rule override
t_rule = latexreg(r_ols, r_tsls; stats = [:nobs], toprule = :top, bottomrule = :bottom)
s_rule = to_latex(t_rule)
@assert occursin(raw"\toprule", s_rule) && occursin(raw"\bottomrule", s_rule)
@assert !occursin(raw"\midrule\midrule", s_rule)
println("\nrule override (booktabs) OK")

println("\nIV_DIAGNOSTICS_OK")
