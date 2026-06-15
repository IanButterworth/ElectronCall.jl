# Smooth, animated interaction recording for ElectronCall.
#
# This is the Electron counterpart to Makie's `fake_interaction.jl`: a small
# event DSL that drives an *animated* on-screen cursor through a real app and
# records a smooth video of the result.
#
# Two pieces make it smooth where naive screenshot loops are not:
#
#  1. Frame pump (main process). `start_recording` subscribes to the window's
#     compositor frames via `webContents.beginFrameSubscription` and pipes the
#     raw BGRA buffers straight into an `ffmpeg` child process at a *constant*
#     frame rate (a `setInterval` re-emits the latest frame every 1/fps s).
#     Capture never round-trips through Julia, so we get a real 30/60 fps video
#     instead of the ~5 fps a `capturePage`-per-frame loop manages.
#
#  2. Animated cursor (renderer). `install_cursor` injects an SVG arrow cursor
#     that tweens between positions with `requestAnimationFrame` and a saccadic
#     easing, dispatching genuine `pointer`/`mouse` events at every step. Each
#     `move_to`/`drag` call returns a Promise that Julia blocks on, so wall-clock
#     stays in sync with the animation without manual `sleep` bookkeeping.
#
# Because the cursor drives real pointer events, drag-and-drop on rich widgets
# (e.g. BonitoWidgets `Workspace` tabs and floating windows) works end to end.
#
# Usage:
#     install_cursor(ctx; start = (60, 60))
#     record_video(ctx, "walkthrough.mp4"; fps = 30) do
#         play(ctx, [
#             MouseTo(Sel("#run")), Click(),
#             MouseTo((400, 300)), Wait(0.5),
#         ])
#     end

# ── Injected JS: animated cursor controller ─────────────────────────────────

const CURSOR_CONTROLLER_JS = let path = joinpath(@__DIR__, "cursor.js")
    include_dependency(path)   # recompile when the JS changes
    read(path, String)
end

# ── Injected JS: frame-pump recorder (main process) ─────────────────────────

const RECORDER_JS = let path = joinpath(@__DIR__, "recorder.js")
    include_dependency(path)
    read(path, String)
end

# ── Cursor control ──────────────────────────────────────────────────────────

"""
    install_cursor(ctx; start = nothing)

Inject the animated SVG cursor overlay into the page. Call once after the app
has loaded. Pass `start = (x, y)` to place the cursor at a starting point.
"""
function install_cursor(ctx::TestContext; start = nothing)
    eval_js(ctx, CURSOR_CONTROLLER_JS)
    if start !== nothing
        set_cursor(ctx, start[1], start[2])
    end
    return nothing
end

"""
    set_cursor(ctx, x, y)

Teleport the cursor to `(x, y)` without animating or dispatching events.
"""
set_cursor(ctx::TestContext, x::Real, y::Real) =
    (eval_js(ctx, "window.__fc && window.__fc.setPos($(Float64(x)), $(Float64(y)))"); nothing)

"""
    cursor_pos(ctx) -> (x, y)

Return the cursor's current position in CSS pixels.
"""
function cursor_pos(ctx::TestContext)
    p = eval_js(ctx, "window.__fc ? [window.__fc.x, window.__fc.y] : null")
    p === nothing && return (0.0, 0.0)
    return (Float64(p[1]), Float64(p[2]))
end

# ── Targets ─────────────────────────────────────────────────────────────────

"""
    Sel(selector; rel = (0.5, 0.5), offset = (0, 0))

A target that resolves to a point inside the element matching `selector`:
`rel` is the fractional position within its bounding box (`(0,0)` = top-left,
`(1,1)` = bottom-right), plus a pixel `offset`.
"""
struct Sel
    selector::String
    rel::Tuple{Float64,Float64}
    offset::Tuple{Float64,Float64}
end
Sel(sel::AbstractString; rel = (0.5, 0.5), offset = (0.0, 0.0)) =
    Sel(String(sel), (Float64(rel[1]), Float64(rel[2])), (Float64(offset[1]), Float64(offset[2])))

"""
    JS(expr)

A target resolved by evaluating the JavaScript expression `expr`, which must
return `[x, y]` in CSS pixels, or `null` if it matches nothing. Use it for a
point that [`Sel`](@ref) can't describe, such as an element found by its text or
a coordinate computed from several rects. Libraries can provide `JS`-building
helpers so callers don't write the JS themselves (for example the probe helpers
in BonitoWidgets).
"""
struct JS
    expr::String
end
JS(expr::AbstractString) = JS(String(expr))

"""
    Lazy(f)

A target (or event) computed at play time: `f(ctx)` returns another target
(tuple, selector, `Sel`, ...). Use when coordinates depend on the live layout,
e.g. a tab whose position is only known once the workspace has rendered.
"""
struct Lazy
    f::Function
end

"""
    resolve_point(ctx, target) -> (x, y)

Resolve a target to absolute CSS-pixel coordinates. `target` may be a
`(x, y)` tuple, a CSS selector string (its centre), a [`Sel`](@ref), a
[`JS`](@ref) expression, or a [`Lazy`](@ref).
"""
resolve_point(ctx::TestContext, t::Tuple{<:Real,<:Real}) = (Float64(t[1]), Float64(t[2]))
resolve_point(ctx::TestContext, l::Lazy) = resolve_point(ctx, l.f(ctx))
function resolve_point(ctx::TestContext, sel::AbstractString)
    r = dom_rect(ctx, sel)
    r === nothing && error("resolve_point: no element matched selector $(repr(sel))")
    return (r["x"] + r["w"] / 2, r["y"] + r["h"] / 2)
end
function resolve_point(ctx::TestContext, s::Sel)
    r = dom_rect(ctx, s.selector)
    r === nothing && error("resolve_point: no element matched selector $(repr(s.selector))")
    return (r["x"] + s.rel[1] * r["w"] + s.offset[1], r["y"] + s.rel[2] * r["h"] + s.offset[2])
end
function resolve_point(ctx::TestContext, p::JS)
    xy = eval_js(ctx, p.expr)
    xy === nothing && error("resolve_point: JS expression matched nothing:\n$(p.expr)")
    return (Float64(xy[1]), Float64(xy[2]))
end

# ── Imperative primitives ───────────────────────────────────────────────────

# Natural cursor travel time: longer hops take a bit longer, clamped to a
# pleasant range (mirrors Makie's automatic_duration).
function auto_duration(ctx::TestContext, x, y)
    cx, cy = cursor_pos(ctx)
    d = hypot(x - cx, y - cy)
    return clamp(0.35 + d / 1400, 0.35, 1.2)
end

"""
    move_to(ctx, target; duration = nothing) -> (x, y)

Animate the cursor to `target`, dispatching `mousemove`/`pointermove` events
along the way. Blocks until the tween finishes. `duration` defaults to a
distance-based time.
"""
function move_to(ctx::TestContext, target; duration = nothing)
    x, y = resolve_point(ctx, target)
    dur = duration === nothing ? auto_duration(ctx, x, y) : Float64(duration)
    eval_js(ctx, "window.__fc.moveTo($x, $y, $dur)")
    return (x, y)
end

_button_code(b::Symbol) = b === :left ? 0 : b === :right ? 2 : b === :middle ? 1 : 0

"""
    mouse_down(ctx; button = :left)

Press a mouse button at the cursor's current position (`pointerdown` +
`mousedown`).
"""
mouse_down(ctx::TestContext; button::Symbol = :left) =
    (eval_js(ctx, "window.__fc.press($(_button_code(button)))"); nothing)

"""
    mouse_up(ctx; click = true)

Release the held mouse button (`pointerup` + `mouseup`, and a `click` when
`click = true`).
"""
mouse_up(ctx::TestContext; click::Bool = true) =
    (eval_js(ctx, "window.__fc.release($(click))"); nothing)

"""
    click(ctx, target = nothing; button = :left, duration = nothing, settle = 0.12)

Move to `target` (if given) and click. With no `target`, clicks at the current
position.
"""
function click(ctx::TestContext, target = nothing; button::Symbol = :left,
               duration = nothing, settle::Real = 0.12)
    target !== nothing && move_to(ctx, target; duration = duration)
    mouse_down(ctx; button = button)
    sleep(settle)
    mouse_up(ctx; click = true)
    return nothing
end

"""
    drag(ctx, from, to; grab = nothing, move = nothing, settle = 0.12)

Press at `from`, animate to `to`, and release (no click). `to` may be a single
target or a vector of waypoints (the cursor visits each in turn, which is what
makes drop-zone previews update naturally). Drives the same real pointer events
the app sees from a user, so widget drag-and-drop works.
"""
function drag(ctx::TestContext, from, to; grab = nothing, move = nothing, settle::Real = 0.12)
    move_to(ctx, from; duration = grab)
    mouse_down(ctx)
    sleep(settle)
    if to isa AbstractVector
        for w in to
            move_to(ctx, w; duration = move)
        end
    else
        move_to(ctx, to; duration = move)
    end
    sleep(settle)
    mouse_up(ctx; click = false)
    return nothing
end

"""
    steer_slider(ctx, target, to_fraction; duration = 1.0)

Drag a native range slider to `to_fraction` (0..1 of its range) over `duration`
seconds, gliding the cursor along the track and firing `input` each frame so
bound plots animate live. `target` is the 0-based index among the page's
`input[type=range]` elements, or a CSS selector. Blocks until done.
"""
function steer_slider(ctx::TestContext, target, to_fraction::Real; duration::Real = 1.0)
    sel = target isa Integer ? string(target) : JSON.json(String(target))
    eval_js(ctx, "window.__fc.steerRange($sel, $(Float64(to_fraction)), $(Float64(duration)))")
    return nothing
end

"""
    select_option(ctx, selector, index)

Set the native `<select>` matching `selector` to its option at 0-based `index`
and dispatch `input`+`change` so bound Julia handlers fire. Returns `nothing`.
"""
function select_option(ctx::TestContext, selector::AbstractString, index::Integer)
    eval_js(ctx, """
        (() => {
            const s = document.querySelector($(JSON.json(String(selector))));
            if (!s) return false;
            s.value = s.options[$(Int(index))].value;
            s.dispatchEvent(new Event('input', {bubbles: true}));
            s.dispatchEvent(new Event('change', {bubbles: true}));
            return true;
        })()
    """)
    return nothing
end

"""
    type_text(ctx, text; char_duration = 0.05)

Type `text` into the focused element character by character, dispatching
`keydown`/`input`/`keyup` and updating the element value.
"""
function type_text(ctx::TestContext, text::AbstractString; char_duration::Real = 0.05)
    for c in text
        jc = JSON.json(string(c))
        eval_js(ctx, """
            (() => {
                const el = document.activeElement;
                if (!el) return;
                el.dispatchEvent(new KeyboardEvent('keydown', {key: $jc, bubbles: true}));
                if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') {
                    const set = Object.getOwnPropertyDescriptor(el.constructor.prototype, 'value').set;
                    set.call(el, el.value + $jc);
                    el.dispatchEvent(new Event('input', {bubbles: true}));
                }
                el.dispatchEvent(new KeyboardEvent('keyup', {key: $jc, bubbles: true}));
            })()
        """)
        sleep(char_duration)
    end
    return nothing
end

"""
    press_key(ctx, key; shift = false, ctrl = false, alt = false, meta = false)

Dispatch a `keydown`/`keyup` for `key` on the focused element (or `body`).
"""
function press_key(ctx::TestContext, key::AbstractString;
                   shift::Bool = false, ctrl::Bool = false, alt::Bool = false, meta::Bool = false)
    k = JSON.json(key)
    eval_js(ctx, """
        (() => {
            const el = document.activeElement || document.body;
            const opts = {key: $k, bubbles: true, shiftKey: $shift, ctrlKey: $ctrl, altKey: $alt, metaKey: $meta};
            el.dispatchEvent(new KeyboardEvent('keydown', opts));
            el.dispatchEvent(new KeyboardEvent('keyup', opts));
        })()
    """)
    return nothing
end

# ── Event DSL (mirrors Makie's fake_interaction) ────────────────────────────

"""
    InteractionEvent

Abstract supertype for declarative interaction events played by [`play`](@ref).
Each subtype implements `apply_event!(ctx, e)`.
"""
abstract type InteractionEvent end

"""
    MouseTo(target; duration = nothing)

Animate the cursor to `target` (see [`resolve_point`](@ref) for target forms).
"""
struct MouseTo <: InteractionEvent
    target::Any
    duration::Union{Nothing,Float64}
end
MouseTo(target; duration = nothing) = MouseTo(target, duration === nothing ? nothing : Float64(duration))
apply_event!(ctx::TestContext, e::MouseTo) = (move_to(ctx, e.target; duration = e.duration); nothing)

"""
    MouseDown(; button = :left)

Press a mouse button at the current cursor position.
"""
struct MouseDown <: InteractionEvent
    button::Symbol
end
MouseDown(; button::Symbol = :left) = MouseDown(button)
apply_event!(ctx::TestContext, e::MouseDown) = mouse_down(ctx; button = e.button)

"""
    MouseUp(; click = true)

Release the held mouse button.
"""
struct MouseUp <: InteractionEvent
    click::Bool
end
MouseUp(; click::Bool = true) = MouseUp(click)
apply_event!(ctx::TestContext, e::MouseUp) = mouse_up(ctx; click = e.click)

"""
    Click(target = nothing; button = :left, duration = nothing, settle = 0.12)

Move to `target` (if given) and click.
"""
struct Click <: InteractionEvent
    target::Any
    button::Symbol
    duration::Union{Nothing,Float64}
    settle::Float64
end
Click(target = nothing; button::Symbol = :left, duration = nothing, settle::Real = 0.12) =
    Click(target, button, duration === nothing ? nothing : Float64(duration), Float64(settle))
apply_event!(ctx::TestContext, e::Click) =
    click(ctx, e.target; button = e.button, duration = e.duration, settle = e.settle)

"""
    RightClick(target = nothing)

Move to `target` (if given) and right-click.
"""
RightClick(target = nothing; kw...) = Click(target; button = :right, kw...)

"""
    Drag(from, to; grab = nothing, move = nothing)

Press at `from`, animate to `to` (a target or a vector of waypoints) and
release. Drives real pointer events for widget drag-and-drop.
"""
struct Drag <: InteractionEvent
    from::Any
    to::Any
    grab::Union{Nothing,Float64}
    move::Union{Nothing,Float64}
end
Drag(from, to; grab = nothing, move = nothing) =
    Drag(from, to, grab === nothing ? nothing : Float64(grab), move === nothing ? nothing : Float64(move))
apply_event!(ctx::TestContext, e::Drag) = drag(ctx, e.from, e.to; grab = e.grab, move = e.move)

"""
    Steer(target, to_fraction; duration = 1.0)

Drag a native range slider (`target` = index or selector) to `to_fraction`,
animating bound plots live. See [`steer_slider`](@ref).
"""
struct Steer <: InteractionEvent
    target::Any
    to_fraction::Float64
    duration::Float64
end
Steer(target, to_fraction::Real; duration::Real = 1.0) =
    Steer(target, Float64(to_fraction), Float64(duration))
apply_event!(ctx::TestContext, e::Steer) =
    steer_slider(ctx, e.target, e.to_fraction; duration = e.duration)

"""
    SelectOption(selector, index)

Set the native `<select>` matching `selector` to its 0-based `index` option.
See [`select_option`](@ref).
"""
struct SelectOption <: InteractionEvent
    selector::String
    index::Int
end
SelectOption(selector::AbstractString, index::Integer) = SelectOption(String(selector), Int(index))
apply_event!(ctx::TestContext, e::SelectOption) = select_option(ctx, e.selector, e.index)

"""
    TypeText(text; char_duration = 0.05)

Type `text` into the focused element.
"""
struct TypeText <: InteractionEvent
    text::String
    char_duration::Float64
end
TypeText(text::AbstractString; char_duration::Real = 0.05) = TypeText(String(text), Float64(char_duration))
apply_event!(ctx::TestContext, e::TypeText) = type_text(ctx, e.text; char_duration = e.char_duration)

"""
    KeyPress(key; shift, ctrl, alt, meta)

Press and release `key` on the focused element.
"""
struct KeyPress <: InteractionEvent
    key::String
    shift::Bool
    ctrl::Bool
    alt::Bool
    meta::Bool
end
KeyPress(key::AbstractString; shift = false, ctrl = false, alt = false, meta = false) =
    KeyPress(String(key), shift, ctrl, alt, meta)
apply_event!(ctx::TestContext, e::KeyPress) =
    press_key(ctx, e.key; shift = e.shift, ctrl = e.ctrl, alt = e.alt, meta = e.meta)

"""
    Wait(seconds)

Hold still for `seconds` (the frame pump keeps recording).
"""
struct Wait <: InteractionEvent
    seconds::Float64
end
Wait(seconds::Real) = Wait(Float64(seconds))
apply_event!(ctx::TestContext, e::Wait) = sleep(e.seconds)

"""
    Focus(selector)

Focus the element matching `selector`.
"""
struct Focus <: InteractionEvent
    selector::String
end
Focus(sel::AbstractString) = Focus(String(sel))
apply_event!(ctx::TestContext, e::Focus) =
    (eval_js(ctx, "document.querySelector($(JSON.json(e.selector)))?.focus()"); nothing)

"""
    Do(f)

Run an arbitrary Julia callback `f(ctx)` as an event — an escape hatch for
driving app state (e.g. nudging a Bonito `Observable`) inline in a sequence.
"""
struct Do <: InteractionEvent
    f::Function
end
apply_event!(ctx::TestContext, e::Do) = (e.f(ctx); nothing)

# Lazy events: resolve to another event at play time.
apply_event!(ctx::TestContext, e::Lazy) = apply_event!(ctx, e.f(ctx))

"""
    play(ctx, events)

Play a sequence of [`InteractionEvent`](@ref)s in order against `ctx`.
"""
function play(ctx::TestContext, events::AbstractVector)
    for e in events
        apply_event!(ctx, e)
    end
    return nothing
end

# ── Frame-pump recording ────────────────────────────────────────────────────

"""
    start_recording(ctx, path; fps = 30, crf = 18) -> (width, height)

Begin recording the window to `path` (an `.mp4`). Subscribes to compositor
frames and pipes them into `ffmpeg` at a constant `fps` from the Electron main
process. Returns the captured frame size in device pixels.
"""
function start_recording(ctx::TestContext, path::AbstractString; fps::Int = 30, crf::Int = 18)
    eval_js(ctx, "0")  # ensure renderer is responsive
    run(ctx.app, RECORDER_JS)
    mkpath(dirname(abspath(path)))
    dims = run(ctx.app, "globalThis.__startRec($(ctx.window.id), $(JSON.json(String(path))), $fps, $crf)")
    return dims
end

"""
    stop_recording(ctx) -> String

Stop the active recording, flush `ffmpeg`, and finalize the file. Returns a
status string.
"""
function stop_recording(ctx::TestContext)
    msg = run(ctx.app, "globalThis.__stopRec($(ctx.window.id))")
    return msg
end

"""
    record_video(f, ctx, path; fps = 30, crf = 18) -> String

Run `f()` while recording the window to `path`. Stops and finalizes even if
`f` throws. Returns `path`.

    record_video(ctx, "out.mp4") do
        play(ctx, [MouseTo((400, 300)), Click(), Wait(1)])
    end
"""
function record_video(f, ctx::TestContext, path::AbstractString; fps::Int = 30, crf::Int = 18)
    start_recording(ctx, path; fps = fps, crf = crf)
    try
        f()
    finally
        stop_recording(ctx)
    end
    return path
end
