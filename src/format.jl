# Number formatting, significance stars, and LaTeX escaping.
# Depends only on Printf + Base so it can be smoke-tested standalone.

"""
    fmt_number(x; digits=3, commas=false)

Format a real number with a fixed number of decimal places. With `commas=true`,
insert thousands separators into the integer part. `missing`/`NaN` -> "".
"""
function fmt_number(x::Real; digits::Integer=3, commas::Bool=false)
    (x isa AbstractFloat && isnan(x)) && return ""
    s = Printf.format(Printf.Format("%.$(digits)f"), float(x))
    # normalize negative zero ("-0.000" -> "0.000")
    if startswith(s, "-") && all(c -> c == '0' || c == '.', s[2:end])
        s = s[2:end]
    end
    return commas ? _add_commas(s) : s
end
fmt_number(::Missing; kwargs...) = ""

"""
    fmt_integer(x; commas=true)

Format a number as an integer (rounded), with optional thousands separators.
"""
function fmt_integer(x::Real; commas::Bool=true)
    s = string(round(Int, x))
    return commas ? _add_commas(s) : s
end
fmt_integer(::Missing; kwargs...) = ""

# Insert thousands separators into the integer part of a numeric string,
# preserving a leading sign and any decimal fraction.
function _add_commas(s::AbstractString)
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
            print(buf, ',')
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
