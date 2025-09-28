# ElectronCall.jl

[![Project Status: Work in progress](http://www.repostatus.org/badges/latest/wip.svg)](http://www.repostatus.org/#active)
[![codecov](https://codecov.io/gh/IanButterworth/ElectronCall.jl/graph/badge.svg)](https://codecov.io/gh/IanButterworth/ElectronCall.jl)

A Julia package for creating desktop applications with Electron. Built with secure defaults, comprehensive error handling, and full compatibility with existing Electron.jl patterns.

## Quick Start

```julia
using ElectronCall

# Create a secure application
app = Application()

# Create a window
win = Window(app, "https://example.com")

# Execute JavaScript securely
title = run(win, "document.title")
println("Page title: $title")

# Clean up
close(app)
```

## Async Messaging

```julia
using ElectronCall

app = Application()
win = Window(app, "<html><button onclick='sendMessageToJulia(\"clicked!\")'>Click me</button></html>")

# Basic messaging (compatible with Electron.jl)
ch = msgchannel(win)
msg = take!(ch)

# Wait with timeout
msg = wait_for_message(win, timeout=5.0)

# Async callback handling
on_message(win) do msg
    println("Received: $msg")
end
```

## Security Configurations

```julia
# Secure defaults (recommended)
app = Application()

# Development mode (disables sandbox for debugging)
app = Application(development_mode = true)

# Custom security
app = Application(
    security = SecurityConfig(
        context_isolation = true,
        sandbox = true,
        node_integration = false
    )
)
```

## Migration from Electron.jl

ElectronCall.jl provides drop-in compatibility with most Electron.jl patterns. See [COMPARISON.md](COMPARISON.md) for detailed migration guidance and feature differences at the time of writing.

## API Reference

### Core Functions

- `Application()` - Create a new Electron application
- `Window()` - Create a new window
- `run(target, js)` - Execute JavaScript code (extends Base.run)
- `load()` - Load content into a window
- `msgchannel()` - Get message channel for communication
- `wait_for_message()` - Wait for messages with optional timeout
- `on_message()` - Register async/sync callback for messages
- `close()` - Clean up applications and windows

### Security

- `SecurityConfig` - Configure security settings
- `secure_defaults()` - Get secure default configuration
- `development_config()` - Get development-friendly configuration

### Testing Packages That Use ElectronCall.jl

When writing tests for packages that use ElectronCall.jl, consider these CI platform requirements:

**Linux CI**: Electron requires a display server and may encounter SUID sandbox restrictions. Use `development_config()` to disable sandboxing in CI:

```julia
using ElectronCall

# In your test setup
function ci_friendly_app()
    if haskey(ENV, "CI") || haskey(ENV, "GITHUB_ACTIONS")
        return Application(security=development_config())
    else
        return Application()  # Use secure defaults locally
    end
end

# Use in tests
app = ci_friendly_app()
win = Window(app, "your-content.html")
# ... your tests
```

**Example GitHub Actions setup**:

```yaml
- name: Run tests
  run: julia --project -e 'using Pkg; Pkg.test()'
  env:
    DISPLAY: ":99"  # Virtual display for Linux
```

This ensures your Electron-based tests work reliably across all CI platforms.

## Related Packages

- [Electron.jl](https://github.com/davidanthoff/Electron.jl)
- [Blink.jl](https://github.com/JunoLab/Blink.jl)
