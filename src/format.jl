# Number formatting, significance stars, and LaTeX escaping.
# Depends only on Printf + Base so it can be smoke-tested standalone.

"""
    fmt_number(x; digits=3, commas=false)

Format a real number with a fixed number of decimal places. `commas` controls the
thousands separator inserted into the integer part: `true` uses `,`, `false`
(default) inserts none, or pass any separator string (e.g. `" "`, `"\\,"`, or `""`
to disable). `missing`/`NaN` -> "".
"""
function fmt_number(x::Real; digits::Integer=3, commas=false)
    (x isa AbstractFloat && isnan(x)) && return ""
    s = Printf.format(Printf.Format("%.$(digits)f"), float(x))
    # normalize negative zero ("-0.000" -> "0.000")
    if startswith(s, "-") && all(c -> c == '0' || c == '.', s[2:end])
        s = s[2:end]
    end
    return _add_commas(s, _thousands_sep(commas))
end
fmt_number(::Missing; kwargs...) = ""

"""
    fmt_integer(x; commas=true)

Format a number as an integer (rounded). `commas` sets the thousands separator:
`true` (default) uses `,`, `false` none, or any separator string (`""` disables).
"""
function fmt_integer(x::Real; commas=true)
    s = string(round(Int, x))
    return _add_commas(s, _thousands_sep(commas))
end
fmt_integer(::Missing; kwargs...) = ""

# Resolve a `commas` argument to a separator string: `true` -> ",", `false` -> "",
# or a user-supplied separator string verbatim (`""` disables). Lets every builder's
# `commas` keyword accept the historical Bool or a custom separator.
_thousands_sep(c::Bool) = c ? "," : ""
_thousands_sep(c::AbstractString) = String(c)
_thousands_sep(c) = throw(ArgumentError(
    "`commas` must be a Bool or a separator String (e.g. \",\", \" \", \"\"); got $(typeof(c))"))

# Insert `sep` as a thousands separator into the integer part of a numeric string,
# preserving a leading sign and any decimal fraction. Empty `sep` -> unchanged.
function _add_commas(s::AbstractString, sep::AbstractString=",")
    isempty(sep) && return String(s)
    neg = startswith(s, "-")
    body = neg ? s[2:end] : s
    if occursin('.', body)
        intpart, frac = split(body, '.'; limit=2)
        frac = "." * frac
    else
        intpart, frac = body, ""
    end
    chars = collect(intpart)
    n = length(chars)
    buf = IOBuffer()
    for (i, c) in enumerate(chars)
        print(buf, c)
        rem = n - i
        if rem > 0 && rem % 3 == 0
            print(buf, sep)
        end
    end
    return (neg ? "-" : "") * String(take!(buf)) * frac
end

"""
    sig_stars(p; cutoffs=(0.01, 0.05, 0.1), symbols=("***", "**", "*"))

Return the significance marker for a p-value. `cutoffs` must be ascending and is
checked smallest-first (p < 0.01 -> "***"). `missing`/`NaN` -> "".
"""
function sig_stars(p::Real; cutoffs=(0.01, 0.05, 0.1), symbols=("***", "**", "*"))
    isnan(p) && return ""
    for (c, sym) in zip(cutoffs, symbols)
        if p < c
            return sym
        end
    end
    return ""
end
sig_stars(::Missing; kwargs...) = ""

const _LATEX_ESCAPES = ('&' => "\\&", '%' => "\\%", '#' => "\\#", '_' => "\\_")

"""
    latex_escape(s)

Escape the LaTeX special characters that show up in raw coefficient names
(`& % # _`). Intentional math/markup in user-supplied labels is left untouched —
escaping is only applied by builders to raw, un-relabeled names.
"""
function latex_escape(s::AbstractString)
    out = String(s)
    for (c, r) in _LATEX_ESCAPES
        out = replace(out, c => r)
    end
    return out
end
