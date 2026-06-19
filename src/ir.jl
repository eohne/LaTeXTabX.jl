# Intermediate representation: a table is a column spec + a list of rows.
# Every builder (latexreg, latexsummary, ...) compiles down to a `TabXTable`,
# so they all share one renderer and one consistent style.
#
# IR types are prefixed `TabX` to stay clear of the `Latex*`/`Table`/`Cell`
# names exported by PrettyTables, RegressionTables, TexTables, TypedTables, etc.

const _ALIGN_LETTER = Dict(:l => "l", :c => "c", :r => "r")

"""
    TabXCell(text; span=1, align=:l, multicol=false)

A single table cell. `text` is treated as final LaTeX (the caller is responsible
for escaping/formatting). A cell is emitted as `\\multicolumn` when it spans more
than one column, when `align != :l`, or when `multicol=true`.
"""
struct TabXCell
    text::String
    span::Int
    align::Symbol
    multicol::Bool
end
TabXCell(text; span::Integer=1, align::Symbol=:l, multicol::Bool=false) =
    TabXCell(String(text), Int(span), align, multicol)

abstract type AbstractTabXRow end

"A row of cells. Cell spans should sum to the table's column count."
struct TabXRow <: AbstractTabXRow
    cells::Vector{TabXCell}
end
TabXRow(cells::TabXCell...) = TabXRow(collect(cells))

"A horizontal rule. `kind ∈ (:top, :mid, :doublemid, :bottom, :none)`; `:none`
renders to nothing (used to omit an outer rule)."
struct TabXRule <: AbstractTabXRow
    kind::Symbol
end

"One or more `\\cmidrule(lr){a-b}` partial rules under grouped headers."
struct TabXCmidRule <: AbstractTabXRow
    spans::Vector{Tuple{Int,Int}}
end

"A verbatim LaTeX line inserted as-is."
struct TabXRaw <: AbstractTabXRow
    latex::String
end

"""
    TabXTable(ncols; colspec, width, rows, float, position, caption, label, centering, notes)

A renderable table. `colspec` defaults to `l` followed by `ncols-1` `Y` columns
(tabularx). `notes` render as full-width `\\scriptsize \\textit{...}` rows just
before `\\end{tabularx}`.
"""
mutable struct TabXTable
    ncols::Int
    colspec::String
    width::String
    rows::Vector{AbstractTabXRow}
    float::Bool
    position::String
    caption::String
    label::String
    centering::Bool
    notes::Vector{String}
end

function TabXTable(ncols::Integer;
        colspec::AbstractString = "l" * repeat("Y", max(ncols - 1, 0)),
        width::AbstractString = "\\textwidth",
        rows = AbstractTabXRow[],
        float::Bool = false,
        position::AbstractString = "htb",
        caption::AbstractString = "",
        label::AbstractString = "",
        centering::Bool = true,
        notes = String[])
    return TabXTable(Int(ncols), String(colspec), String(width),
                     Vector{AbstractTabXRow}(rows), float, String(position),
                     String(caption), String(label), centering,
                     String[String(n) for n in notes])
end

addrow!(t::TabXTable, r::AbstractTabXRow) = (push!(t.rows, r); t)
