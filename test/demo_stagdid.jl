# Verify the StagDiDModels.jl backend (staggered DiD) through the generic
# StatsAPI/coeftable path. Run from the package root:
#   julia --startup-file=no test/demo_stagdid.jl

using Pkg
Pkg.activate(mktempdir())
Pkg.develop(path = dirname(@__DIR__))
Pkg.add("DataFrames")
Pkg.add(url = "https://github.com/eohne/StagDiDModels.jl")

using LaTeXTabX, StagDiDModels, DataFrames

N, T = 120, 20
years = 2000:2019
df = DataFrame(unit = repeat(1:N, inner = T), year = repeat(collect(years), outer = N))
# staggered cohorts: a third never-treated (g=0), the rest adopt in 2008 / 2014
df.g = map(u -> u <= N ÷ 3 ? 0 : (u <= 2N ÷ 3 ? 2008 : 2014), df.unit)
df.d = Int.((df.g .> 0) .& (df.year .>= df.g))
unit_fe = (df.unit .% 7) ./ 3
year_fe = (df.year .- 2000) .* 0.05
df.dep_var = unit_fe .+ year_fe .+ 0.8 .* df.d .+ 0.3 .* cos.(3.0 .* df.unit .+ df.year)

# Fit several static estimators on the same panel; the estimator row labels each
# with the citation from the StagDiDModels.jl extension.
twfe    = fit_twfe_static(df;    y = :dep_var, id = :unit, t = :year, g = :g, cluster = :unit)
gardner = fit_gardner_static(df; y = :dep_var, id = :unit, t = :year, g = :g, cluster = :unit)
bjs     = fit_bjs_static(df;     y = :dep_var, id = :unit, t = :year, g = :g, cluster = :unit)
sunab   = fit_sunab(df;          y = :dep_var, id = :unit, t = :year, g = :g, cluster = :unit)

t = latexreg(twfe, gardner, bjs, sunab;
    labels = Dict("_ATT" => "ATT"),
    estimator = :show,             # TWFE / Gardner (2022) / BJS (2023) / Sun & Abraham (2021)
    number_regressions = false,
    stats = [:nobs],
    notes = ["Static ATT; SE clustered by unit."],
)
println(to_latex(t))
println("\nSTAGDID_DEMO_OK")
