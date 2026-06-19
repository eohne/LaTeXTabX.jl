module LaTeXTabXFixedEffectModelsExt

using FixedEffectModels
import LaTeXTabX: _responsename, _estimator, _fixedeffects, _se_info, _regstat_ext

_responsename(m::FixedEffectModel) = try
    string(m.responsename)
catch
    ""
end

# IV models carry a first-stage (Kleibergen-Paap) F; it is `NaN` for non-IV fits,
# so a finite value flags 2SLS. (`F_kp` is always a `Float64` field — comparing it
# to `nothing` is always true, hence the explicit `isnan`.)
_estimator(m::FixedEffectModel) = try
    isnan(m.F_kp) ? "OLS" : "IV (2SLS)"
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

# Package-specific statistics: within-R², overall F-stat and its p-value, plus the
# IV first-stage Kleibergen-Paap rk Wald F and its p-value (`F_kp`/`p_kp`). The KP
# F is FixedEffectModels' only first-stage diagnostic, so `:firststage_F`/`_p`
# alias it. Both are `NaN` for non-IV fits -> `missing` -> a blank cell, so the
# rows are simply ignored for OLS columns. (Wrapped by the core `_regstat`
# try/catch, so a missing field -> blank.)
function _regstat_ext(s::Symbol, m::FixedEffectModel)
    s === :r2_within && return m.r2_within
    s === :fstat && return m.F
    s === :fstat_pval && return m.p
    (s === :F_kp || s === :firststage_F) && return isnan(m.F_kp) ? missing : m.F_kp
    (s === :p_kp || s === :firststage_p) && return isnan(m.p_kp) ? missing : m.p_kp
    return missing
end

end # module
