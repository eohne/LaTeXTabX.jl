module LaTeXTabXFixedEffectModelsExt

using FixedEffectModels
import LaTeXTabX: _responsename, _estimator, _fixedeffects, _se_info, _regstat_ext

_responsename(m::FixedEffectModel) = try
    string(m.responsename)
catch
    ""
end

# IV models carry first-stage (Kleibergen-Paap) diagnostics; use that to flag 2SLS.
_estimator(m::FixedEffectModel) = try
    (hasproperty(m, :F_kp) && m.F_kp !== nothing) ? "IV (2SLS)" : "OLS"
catch
    "OLS"
end

# Fixed-effect absorbed terms (best-effort; users can always pass `fixedeffects=`).
function _fixedeffects(m::FixedEffectModel)
    out = Pair{String,Bool}[]
    try
        for k in m.fekeys
            push!(out, string(k) => true)
        end
    catch
    end
    return out
end

# Auto-detect the SE type from the fitted covariance estimator.
function _se_info(m::FixedEffectModel)
    vt = try m.vcov_type catch; nothing end
    if vt isa Vcov.ClusterCovariance
        return (:cluster, _fe_cluster_names(m), "")
    elseif vt isa Vcov.RobustCovariance
        return (:robust, String[], "")
    elseif vt isa Vcov.SimpleCovariance
        return (:simple, String[], "")
    end
    nc = try m.nclusters catch; nothing end
    nc === nothing ? (:unknown, String[], "") : (:cluster, _fe_cluster_names(m), "")
end

_fe_cluster_names(m) = try
    String[string(k) for k in keys(m.nclusters)]
catch
    String[]
end

# Package-specific statistics: within-R², overall F-stat and its p-value.
# (Wrapped by the core `_regstat` try/catch, so a missing field -> blank.)
function _regstat_ext(s::Symbol, m::FixedEffectModel)
    s === :r2_within && return m.r2_within
    s === :fstat && return m.F
    s === :fstat_pval && return m.p
    return missing
end

end # module
