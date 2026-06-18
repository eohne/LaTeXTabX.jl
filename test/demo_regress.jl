# Verify the Regress.jl backend (gragusa/Regress.jl, IV) + its estimator
# extension, via the generic StatsAPI path. Unregistered -> installed by URL.
# Run from the package root:  julia --startup-file=no test/demo_regress.jl

using Pkg
Pkg.activate(mktempdir())
Pkg.develop(path = dirname(@__DIR__))
Pkg.add(["DataFrames", "StatsModels"])
Pkg.add(url = "https://github.com/gragusa/Regress.jl")

using LaTeXTabX, Regress, DataFrames
using StatsModels: @formula

n = 500
idx = collect(1:n)
df = DataFrame(z1 = cos.(idx), z2 = sin.(2.0 .* idx), x = (idx .% 5) ./ 5)
df.endo = 0.5 .* df.z1 .+ 0.3 .* df.z2 .+ 0.2 .* cos.(3.0 .* idx)
df.y = 1.0 .+ 0.8 .* df.endo .+ 0.4 .* df.x .+ 0.3 .* sin.(1.7 .* idx)

ols  = Regress.ols(df, @formula(y ~ x + endo))
tsls = Regress.iv(Regress.TSLS(), df, @formula(y ~ x + (endo ~ z1 + z2)))
liml = Regress.iv(Regress.LIML(), df, @formula(y ~ x + (endo ~ z1 + z2)))

t = latexreg(ols, tsls, liml;
    labels = Dict("endo" => "Endogenous", "x" => "Control", "(Intercept)" => "Constant"),
    estimator = :auto,            # OLS / IV (2SLS) / IV (LIML, κ=...) via the extension
    stats = [:nobs, :r2],
    notes = ["Instruments z1, z2."],
)
println(to_latex(t))
println("\nREGRESS_DEMO_OK")
