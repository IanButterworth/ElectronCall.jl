using Documenter
using ElectronCall

makedocs(;
    modules = [ElectronCall],
    authors = "Ian Butterworth <ian.butterworth@gmail.com> and contributors",
    sitename = "ElectronCall.jl",
    format = Documenter.HTML(;
        canonical = "https://ianbutterworth.github.io/ElectronCall.jl",
        edit_link = "main",
        assets = String[],
    ),
    pages = [
        "Home" => "index.md",
        "Getting Started" => "getting-started.md",
        "Security" => "security.md",
        "API Reference" => "api.md",
        "Migration from Electron.jl" => "migration.md",
        "Examples" => "examples.md",
    ],
)

deploydocs(; repo = "github.com/IanButterworth/ElectronCall.jl", devbranch = "main")
