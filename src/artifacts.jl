# Electron binary management and artifact loading.
#
# Provides utilities for loading the Electron binary from artifacts and
# preparing the test environment.

function conditional_electron_load()
    try
        return artifact"electronjs_app"
    catch error
        return nothing
    end
end

function get_electron_binary_cmd()
    electronjs_path = conditional_electron_load()

    if electronjs_path === nothing
        return "electron"
    elseif Sys.isapple()
        return joinpath(electronjs_path, "Julia.app", "Contents", "MacOS", "Julia")
    elseif Sys.iswindows()
        return joinpath(electronjs_path, "electron.exe")
    else # assume unix layout
        return joinpath(electronjs_path, "electron")
    end
end

"""
    prep_test_env()

Prepare the environment for testing, particularly in CI environments.
Sets up virtual display on Linux headless systems.
"""
function prep_test_env()
    if haskey(ENV, "GITHUB_ACTIONS") && ENV["GITHUB_ACTIONS"] == "true"
        if Sys.islinux()
            run(Cmd(`Xvfb :99 -screen 0 1024x768x24`), wait = false)
            ENV["DISPLAY"] = ":99"
        end
    end
end
