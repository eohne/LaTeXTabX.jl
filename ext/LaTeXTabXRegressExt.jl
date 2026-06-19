module LaTeXTabXRegressExt

using Regress
import LaTeXTabX: _estimator, _se_info, _regstat_ext

# Coefficients/SEs come through the generic StatsAPI `coeftable` path. Here we
# label the estimator; the K-class method (TSLS/LIML/Fuller) is read from the
# fitted type when it is encoded there, defaulting to 2SLS.
_estimator(::Regress.OLSEstimator) = "OLS"

# The k-class method is `m.estimator`; the realized kappa is
# `m.postestimation.kappa` (NaN for 2SLS). Show kappa for LIML/Fuller/KClass.
function _estimator(m::Regress.IVEstimator)
    method = try string(nameof(typeof(m.estimator))) catch; "" end
    kappa  = try m.postestimation.kappa catch; NaN end
    kstr = (kappa isa Real && !isnan(kappa)) ? ", \$\\kappa\$=$(round(kappa; digits=3))" : ""
    method == "LIML"   && return "IV (LIML$(kstr))"
    method == "Fuller" && return "IV (Fuller$(kstr))"
    method == "KClass" && return isempty(kstr) ? "IV (k-class)" : "IV (k-class$(kstr))"
    return "IV (2SLS)"
end

# Precise SE-type detection. Regress stores the fitted vcov estimator and exposes
# `vcov_type_name`, which yields "HC0".."HC3", "Bartlett(5)", "CR1", etc.
function _regress_se_info(m)
    vt = try m.vcov_estimator catch; return (:unknown, String[], "") end
    name  = try Regress.vcov_type_name(vt) catch; "" end
    tname = try string(typeof(vt).name.name) catch; "" end
    # cluster-robust (CR0/CR1/CR2/CR3): cluster names are the symbols in `.g`,
    # or the keys of the stored cluster_vars (IV models).
    if startswith(tname, "CR")
        vars = String[]
        try
            for g in vt.g
                g isa Symbol && push!(vars, string(g))
            end
        catch
        end
        if isempty(vars)
            try
                for k in keys(m.postestimation.cluster_vars)
                    push!(vars, string(k))
                end
            catch
            end
        end
        return (:cluster, vars, name)
    end
    # classical / homoskedastic
    (startswith(tname, "Homosk") || startswith(name, "Homosk")) && return (:simple, String[], "")
    # everything else (HC/HR White variants, HAC kernels, ...) is robust; use the
    # precise label, normalising the underlying HRn type name to HCn.
    label = isempty(name) ? (isempty(tname) ? "Robust" : tname) : name
    return (:robust, String[], replace(label, r"^HR" => "HC"))
end

_se_info(m::Regress.OLSEstimator) = _regress_se_info(m)
_se_info(m::Regress.IVEstimator) = _regress_se_info(m)

# IV first-stage diagnostics. Regress exposes three first-stage F-tests, each
# returning a `FirstStageFTest` with `.stat`/`.p`: the Kleibergen-Paap rk Wald F
# (`:F_kp`/`:p_kp`), the robust Wald F (`:firststage_F`/`:firststage_p`), and the
# IID/homoskedastic F (`:firststage_F_iid`/`:firststage_p_iid`). Only IV models
# dispatch here; OLS models hit the generic `_regstat_ext` (missing), and any
# error (e.g. a model fit without first-stage data) is turned into `missing` by
# the core `_regstat` wrapper -> a blank cell.
function _regstat_ext(s::Symbol, m::Regress.IVEstimator)
    s === :F_kp             && return _fs_scalar(Regress.first_stage_F_KP(m).stat)
    s === :p_kp             && return _fs_scalar(Regress.first_stage_F_KP(m).p)
    s === :firststage_F     && return _fs_scalar(Regress.first_stage_F_robust(m).stat)
    s === :firststage_p     && return _fs_scalar(Regress.first_stage_F_robust(m).p)
    s === :firststage_F_iid && return _fs_scalar(Regress.first_stage_F_iid(m).stat)
    s === :firststage_p_iid && return _fs_scalar(Regress.first_stage_F_iid(m).p)
    return missing
end

# A first-stage F/p is a scalar for a single endogenous regressor (and for the
# joint KP statistic); with several endogenous regressors it is a per-endogenous
# vector, which can't go in one cell -> collapse a length-1 vector and otherwise
# return `missing`.
_fs_scalar(x::Real) = float(x)
_fs_scalar(x::AbstractVector) = length(x) == 1 ? float(x[1]) : missing
_fs_scalar(::Any) = missing

end # module
