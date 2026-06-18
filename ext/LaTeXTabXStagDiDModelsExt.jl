module LaTeXTabXStagDiDModelsExt

using StagDiDModels
import LaTeXTabX: _estimator

# Response names and coefficients (`_ATT` for static, `τ::<h>` for dynamic) come
# through the generic StatsAPI `coeftable` path; here we only label the estimator
# so a mixed table identifies each column's method automatically.
# Citations match StagDiDModels.jl's own references. The `\&` is escaped so the
# label is valid inside a table cell.
_estimator(::StagDiDModels.BJSModel)     = "Borusyak, Jaravel, Spiess (2023)"
_estimator(::StagDiDModels.GardnerModel) = "Gardner (2022)"
_estimator(::StagDiDModels.SunabModel)   = "Sun \\& Abraham (2021)"
_estimator(::StagDiDModels.TWFEModel)    = "TWFE"

end # module
