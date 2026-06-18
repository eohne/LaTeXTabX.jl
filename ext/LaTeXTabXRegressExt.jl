module LaTeXTabXRegressExt

using Regress
import LaTeXTabX: _estimator, _se_info

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

end # module
