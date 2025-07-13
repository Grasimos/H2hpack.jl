# make.jl for HPACK.jl Documentation
import Pkg; Pkg.add("Documenter")
using Documenter
using HPACK

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
    repo = "https://github.com/grasimos/H2hpack.jl.git"
)

deploydocs(
    repo = "github.com/grasimos/H2hpack.jl.git",
    devbranch = "main"
)
