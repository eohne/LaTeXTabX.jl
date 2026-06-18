# Dependency-free smoke test of the IR + renderer (no StatsAPI / model packages).
# Run from the package root:  julia test/smoke_render.jl

using Printf

include(joinpath(@__DIR__, "..", "src", "format.jl"))
include(joinpath(@__DIR__, "..", "src", "ir.jl"))
include(joinpath(@__DIR__, "..", "src", "render_latex.jl"))

# --- formatting sanity checks ---
@assert fmt_number(-0.005; digits=3) == "-0.005"
@assert fmt_number(-0.0; digits=3) == "0.000"            # negative zero normalized
@assert fmt_integer(719121) == "719,121"
@assert fmt_number(2547.34; digits=2, commas=true) == "2,547.34"
@assert sig_stars(0.004) == "***"
@assert sig_stars(0.03) == "**"
@assert sig_stars(0.08) == "*"
@assert sig_stars(0.5) == ""
@assert latex_escape("log_dc & x") == "log\\_dc \\& x"

# --- a hand-built table mirroring the "scale and skill" header style ---
t = TabXTable(4; colspec="lYYY")
push!(t.rows, TabXRule(:doublemid))
push!(t.rows, TabXRow([TabXCell(""), TabXCell("High Connectedness"; align=:c),
                       TabXCell("Low Connectedness"; align=:c), TabXCell("Difference"; align=:c)]))
push!(t.rows, TabXRule(:mid))
push!(t.rows, TabXRow([TabXCell("\\multicolumn{4}{l}{\\textit{Panel A: Skill}}")]))
push!(t.rows, TabXRow([TabXCell("Bias-adjusted mean"), TabXCell("0.072"), TabXCell("0.132"),
                       TabXCell("\$-0.060^{***}\$")]))
push!(t.rows, TabXRule(:doublemid))
t.notes = ["Note: \$^{\\mathrm{NT}}\$ indicates the difference is not formally tested."]

println(to_latex(t))
println("\nsmoke_render OK")
