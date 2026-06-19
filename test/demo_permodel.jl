# Verify per-model (per-column) keep/drop/labels and label-keyed coefficient rows:
#  * `labels`/`keep`/`drop` apply globally (a Dict / pattern) or per column (a
#    vector of dicts / pattern-vectors); `order` is always global.
#  * coefficients that resolve to the SAME display label MERGE onto one row, even
#    when they have different raw names across columns (x1_standard / x1_nonstandard
#    -> "X1") -- each column fills its own value.
#  * the auto "Controls" row ignores a dropped intercept.
# Run from the package root:  julia --startup-file=no test/demo_permodel.jl

using Pkg
Pkg.activate(mktempdir())
Pkg.develop(path = dirname(@__DIR__))
Pkg.add(["DataFrames", "StatsModels", "GLM"])

using LaTeXTabX, DataFrames, GLM
using StatsModels: @formula

n = 200
idx = collect(1:n)
df = DataFrame(x1s = cos.(idx), x1n = cos.(idx) .+ 0.01 .* sin.(idx),
               w = sin.(2.0 .* idx))
df.y = 1.0 .+ 0.8 .* df.x1s .- 0.3 .* df.w .+ 0.2 .* cos.(3.0 .* idx)

rowcells(s, label) = begin
    line = first(filter(l -> startswith(strip(l), label), split(s, '\n')))
    strip.(split(replace(line, r"\\\\\s*$" => ""), '&'))
end
# count body rows whose first cell is exactly `label` (avoids prefix collisions
# with stat labels like "Adjusted $R^2$")
nrows(s, label) = count(l -> strip(first(split(l, '&'))) == label, split(s, '\n'))

# ---- merging: x1s (col1) and x1n (col2) both relabelled to "X1" -> one row
m1 = lm(@formula(y ~ x1s + w), df)        # (Intercept), x1s, w
m2 = lm(@formula(y ~ x1n + w), df)        # (Intercept), x1n, w
t_merge = latexreg(m1, m2;
    labels = Dict("x1s" => "X1", "x1n" => "X1", "w" => "Control", "(Intercept)" => "Constant"),
    order  = ["X1", "Control"])           # order by display label
s_merge = to_latex(t_merge)
println("\n===== merge x1s/x1n -> X1 =====\n", s_merge)
@assert nrows(s_merge, "X1") == 1 "x1s and x1n must collapse to ONE X1 row"
xr = rowcells(s_merge, "X1")
@assert !isempty(xr[2]) && xr[2] != raw"\\" "col1 fills X1 from x1s"
@assert !isempty(xr[3]) && xr[3] != raw"\\" "col2 fills X1 from x1n"
# order: X1 row before Control row, both before Constant
lines = split(s_merge, '\n')
posX1   = findfirst(l -> startswith(strip(l), "X1"), lines)
posCtrl = findfirst(l -> startswith(strip(l), "Control"), lines)
posCons = findfirst(l -> startswith(strip(l), "Constant"), lines)
@assert posX1 < posCtrl < posCons "order X1 < Control < Constant; got $posX1 $posCtrl $posCons"
println("label-merge + order-by-label OK")

# ---- controls ignores a dropped intercept (no other hidden regressor)
t_int = latexreg(m1; drop_intercept = true, print_controls = true)
s_int = to_latex(t_int)
@assert !occursin("Controls", s_int) "dropping only the intercept must NOT add a Controls row"
println("controls ignores dropped intercept OK")

# ---- per-model keep masks a REAL regressor -> Controls Yes / No
m1b = lm(@formula(y ~ x1s + w), df)
m2b = lm(@formula(y ~ x1s + w), df)
t_mask = latexreg(m1b, m2b;
    labels = Dict("x1s" => "Treatment", "w" => "Control", "(Intercept)" => "Constant"),
    keep   = [["(Intercept)", "w"], ["(Intercept)", "x1s", "w"]],   # col1 hides x1s
    print_controls = true)
s_mask = to_latex(t_mask)
println("\n===== per-model keep (mask x1s out of col 1) =====\n", s_mask)
tr = rowcells(s_mask, "Treatment")
@assert tr[2] == "" "x1s masked out of column 1"
@assert !isempty(tr[3]) && tr[3] != raw"\\" "x1s shown in column 2"
ctrl = rowcells(s_mask, "Controls")
@assert ctrl[2] == "Yes" "col1 hides a real regressor -> Controls=Yes"
@assert ctrl[3] == "No"  "col2 shows everything -> Controls=No"
println("per-model keep masking + controls flag OK")

# ---- backward compat: single global dict + global drop/order still work
t_glob = latexreg(m1, m2;
    labels = Dict("x1s" => "A", "x1n" => "B", "w" => "Control"),
    drop = [r"Intercept"], order = ["w"])
s_glob = to_latex(t_glob)
@assert occursin("Control", s_glob) && !occursin("Intercept", s_glob)
@assert nrows(s_glob, "A") == 1 && nrows(s_glob, "B") == 1  # different labels -> separate rows
println("global backward-compat OK")

println("\nPERMODEL_OK")
