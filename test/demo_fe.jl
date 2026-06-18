# End-to-end check of the FixedEffectModels backend: FE rows, clustered SE,
# within-R^2. Run from the package root:  julia --startup-file=no test/demo_fe.jl

using Pkg
Pkg.activate(mktempdir())
Pkg.develop(path = dirname(@__DIR__))
Pkg.add(["FixedEffectModels", "DataFrames"])

using LaTeXTabX, FixedEffectModels, DataFrames

N, T = 40, 10
df = DataFrame(id = repeat(1:N, inner = T), t = repeat(1:T, outer = N))
df.x = cos.(12.9898 .* df.id .+ 78.233 .* df.t)   # non-separable -> survives FE
df.w = cos.(df.id .+ df.t)
df.y = 0.8 .* df.x .- 0.2 .* df.w .+ 0.05 .* df.id .+ 0.1 .* df.t .+
       0.3 .* cos.(3.0 .* (df.id .+ df.t))

m1 = reg(df, @formula(y ~ x + fe(id) + fe(t)), Vcov.cluster(:id))
m2 = reg(df, @formula(y ~ x + w + fe(id) + fe(t)), Vcov.cluster(:id))

t = latexreg(m1, m2;
    labels = Dict("x" => "Treatment", "w" => "Control",
                  "id" => "Unit", "t" => "Period"),
    stats = [:nobs, :r2, :r2_within, :fstat],
    notes = ["Standard errors clustered by unit in parentheses."],
)
println(to_latex(t))
println("\nFE_DEMO_OK")
