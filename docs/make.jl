# make.jl for HPACK.jl Documentation

using Documenter
using HPACK

makedocs(
    sitename = "HPACK.jl Documentation",
    modules = [HPACK],
    format = Documenter.HTML(),
    pages = [
        "Home" => "index.md",
        "Usage" => "usage.md",
        "API Reference" => "api.md"
    ],
    authors = "Gerasimos Panou",
    repo = "https://github.com/grasimos/Hpack.jl.git"
)

deploydocs(
    repo = "github.com/grasimos/Hpack.jl.git",
    devbranch = "main"
)
