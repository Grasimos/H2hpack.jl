# make.jl for HPACK.jl Documentation
import Pkg; Pkg.add("Documenter")
using Documenter
using Http2Hpack

makedocs(
    sitename = "HPACK.jl Documentation",
    modules = [HPACK],
    format = Documenter.HTML(),
    checkdocs = :none,
    pages = [
        "Home" => "index.md",
        "Usage" => "usage.md",
        "API Reference" => "api.md"
    ],
    authors = "Gerasimos Panou",
    repo = "https://github.com/grasimos/Http2Hpack.jl.git"
)

deploydocs(
    repo = "github.com/grasimos/Http2Hpack.jl.git",
    devbranch = "main"
)
