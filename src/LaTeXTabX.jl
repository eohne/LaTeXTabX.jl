module LaTeXTabX

using Printf
import StatsAPI
import Statistics
import Tables

# --- core intermediate representation + renderer (no model dependencies) ---
include("format.jl")
include("ir.jl")
include("render_latex.jl")

# --- high-level builders ---
include("latexreg.jl")
include("latexsummary.jl")
include("latexcorr.jl")
include("latexpanel.jl")
include("latextable.jl")

# IR + renderer
export TabXTable, TabXCell, TabXRow, TabXRule, TabXCmidRule, TabXRaw
export to_latex, write_latex

# builders
export latexreg, latexsummary, latexcorr, latexpanel, latextable, panel

# model extraction hook (extensions add methods to these)
export modeldata

end # module
