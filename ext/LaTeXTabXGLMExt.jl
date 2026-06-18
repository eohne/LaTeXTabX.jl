module LaTeXTabXGLMExt

using GLM
import LaTeXTabX: _responsename, _estimator

# `lm`/`glm` return a StatsModels.TableRegressionModel. Pull the response name
# from its formula's left-hand side. Best-effort: fall back to "" on any change
# in internals.
function _responsename(m::GLM.StatsModels.TableRegressionModel)
    try
        return string(m.mf.f.lhs)
    catch
        return ""
    end
end

# OLS for linear models; infer the family from the GLM type for the rest.
function _estimator(m::GLM.StatsModels.TableRegressionModel)
    mm = m.model
    mm isa GLM.LinearModel && return "OLS"
    s = string(typeof(mm))
    occursin("ProbitLink", s) && return "Probit"
    occursin("LogitLink", s) && return "Logit"
    occursin("Poisson", s) && return "Poisson"
    occursin("NegativeBinomial", s) && return "Neg. Binomial"
    return "GLM"
end

end # module
