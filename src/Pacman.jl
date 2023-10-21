"""
## Gameplay
```julia
using Snake
```
The game will start automatically.
- Hit `esc` to pause the game.
- Resume with `play()` or restart the game with `restart()`

## Controls (wasd)
* `a` and `d` to apply left and right velocity
* `s` to apply down velocity
* `w` to apply up velocity
* `backtick` to pause, then `play()` to resume

## Emoji support

To play using emojis, run:

```julia
play(emoji=true)
```

## Other options
- `play(walls=true)`: Restart the game when hitting walls (default `true`)
- `play(size=(20,20))`: Change game field dimensions (default `(20,20)`)
"""
module Pacman

using Random
using Distributions
using Statistics

export play, restart, resetdelays!

# play when running `using Pacman`
__init__() = restart()


Base.@kwdef struct StyledChars
    pacman = "⬤"
    dead_pacman = "×"
    ghost = "■" # "☗" # ᗣ
    dot = "ᐧ"
    super_dot = "•"
    screen = "╎"
end


Base.@kwdef struct RawChars
    pacman = "x"
    dead_pacman = "X"
    ghosts = (
        inky = "𝕀",
        blinky = "𝔹",
        pinky = "ℙ",
        clyde = "ℂ",
    )
    dot = "d"
    super_dot = "o"
    portal_left = "<"
    portal_right = ">"
    portal_passage = "-"
    score = "#"
    screen = "="
    # | * " "
end

paint_ghost(params, color; endcolor=params.colors.reset) = paint(params.styled.ghost, color, endcolor)

Base.@kwdef struct GameParams
    styled = StyledChars()
    raw = RawChars()
    keys = (
        up = 'w',
        left = 'a',
        down = 's',
        right = 'd',
        tick = '`',
    )
    scores = (
        ghost = 100,
        dot = 10,
        super_dot = 10,
    )
    timers = (
        super = 15, # seconds
        super_blink = 12, # seconds
    )
    dirs = [[-1,0], [1,0], [0,-1], [0,1]] # up, down, left, right
    colors = (
        black = "\e[0;30m",
        blue = "\e[38;5;19m", # "\e[34m"
        white = "\e[37m",
        red = "\e[38;5;196m", # "\e[31m"
        purple = "\e[35m",
        pink = "\e[38;5;213m",
        cyan = "\e[38;5;51m",
        yellow = "\e[33m",
        orange = "\e[38;5;215m",
        lightred = "\e[38;5;217m",
        brightblue = "\e[38;5;21m",
        darkred = "\e[38;5;52m",
        reset = "\e[0m",
    )
    ghost_colors = (
        inky = colors[:cyan],
        pinky = colors[:pink],
        blinky = colors[:red],
        clyde = colors[:orange],
        blue = colors[:brightblue],
        blinking = colors[:white],
    )
end

Base.@kwdef mutable struct GhostInfo
    mark = " "
    init_pos = missing
    pos = missing
    dir = [0, 0]
    isout = false
    isblue = false
    tblue = 0
    isblinking = false
    blinkingon = false
    tblink = 0
end

Base.@kwdef mutable struct Motion
    x::Int = 0
    y::Int = 0
    dx::Int = 0
    dy::Int = 0
end


function setmotion!(motion, x, y)
    # motion.
end


Base.@kwdef mutable struct GameState
    params = GameParams()
    cells = missing
    ghost_chars = [params.raw.ghosts.inky, params.raw.ghosts.blinky, params.raw.ghosts.pinky, params.raw.ghosts.clyde]
    ghosts = (
        inky = (endcolor=params.colors.reset) -> paint_ghost(params, params.ghost_colors.inky; endcolor),
        blinky = (endcolor=params.colors.reset) -> paint_ghost(params, params.ghost_colors.blinky; endcolor),
        pinky = (endcolor=params.colors.reset) -> paint_ghost(params, params.ghost_colors.pinky; endcolor),
        clyde = (endcolor=params.colors.reset) -> paint_ghost(params, params.ghost_colors.clyde; endcolor),
        blue = (endcolor=params.colors.reset) -> paint_ghost(params, params.ghost_colors.blue; endcolor),
        blinking = (endcolor=params.colors.reset) -> paint_ghost(params, params.ghost_colors.blinking; endcolor),
    )
    ghost_infos = Dict{String,Any}()
    maze_type = 1 # 1 == classic PacMan, 2 = PocMan 17x19, 3 = 9x18, 4 = SISL 10x22
    is_pocman = false
    random_pellets = false
    motion = Motion()
    motion′ = Motion()
    delay = 0.05 # seconds
    delay′ = delay
    horiz_delay = delay
    vert_delay = horiz_delay # horiz_delay*(15/8) # (15/8) for terminal (14/6) for VS Code
    done_delay = 3 # seconds
    timeout = 0
    max_timeout = 120/delay
    score = 0
    paused = false
    key = nothing
    subpixel = 2
    frame_update = 8
    portal_locations = Dict{String,Any}(
        params.raw.portal_left=>missing,
        params.raw.portal_right=>missing,
    )
    mark = " " # current mark PacMan is on top of
    buffer = nothing
end


hide_cursor() = print("\e[?25l")
show_cursor() = println("\e[?25h")
paint(pix, color, endcolor=gs.params.colors[:reset]) = "$(color)$(pix)$(endcolor)"
normalize1(X) = X ./ sum(X)


function resetstate!(gs)
    _gs = GameState()
    for k in propertynames(gs)
        setproperty!(gs, k, getproperty(_gs, k))
    end
    return gs
end


function restart(gs=GameState(); kwargs...)
    resetstate!(gs)
    play(gs; kwargs...)
end


"""
Pacman options:
...
"""
function play(gs::GameState=GameState();
              maze_type::Int=gs.maze_type,
              is_pocman::Bool=gs.is_pocman,
              random_pellets::Bool=gs.random_pellets,
              delay::Number=gs.delay)
    if ismissing(gs.cells)
        resetstate!(gs)
    else
        gs.timeout = 0
        gs.paused = false
    end

    local kbtask
    params = gs.params
    
    try
        hide_cursor()
        clearscreen()

        if ismissing(gs.cells) || is_pocman != gs.is_pocman || maze_type != gs.maze_type || random_pellets != gs.random_pellets
            gs.maze_type = maze_type
            gs.random_pellets = random_pellets
            resetfield!(gs)
        end
        gs.is_pocman = is_pocman
        gs.maze_type = maze_type
        gs.random_pellets = random_pellets
        gs.delay = delay

        set_keyboard_input_mode()
        kbtask = capture_keyboard_input!(gs)

        t0 = time()

        # TODO: GameState
        flicker = false
        tflicker = t0
        flickerdelay = 0.4 # s

        subpixelmove = false
        frames = 0

        while !gs.paused
            t = time()
            subpixelmove = mod(frames, gs.frame_update) == 0

            kbtask = game!(gs; flicker, subpixelmove, kbtask, t)
            frames += 1

            if abs(tflicker - t) > flickerdelay
                flicker = !flicker
                tflicker = t
            end

            sleep(eps())
        end

        gs.motion = Motion()
        gs.motion′ = Motion()
    
        close_keyboard_buffer()
        show_cursor()
        closetask(kbtask)
        # pausegame()
    catch err
        close_keyboard_buffer()
        show_cursor()
        closetask(kbtask)
        rethrow(err)
    end

    return nothing
end


function game!(gs::GameState; flicker=false, subpixelmove=true, kbtask=missing, t=missing)
    motion = gs.motion
    motion′ = gs.motion′

    cells = gs.cells
    gridx = size(cells,2)
    gridy = size(cells,1)

    keypress!(gs)

    # get postion
    p = [findfirst(c->c == gs.params.raw.pacman, cells).I...]
    
    # replace portal indicators
    for (k,v) in gs.portal_locations
        if !ismissing(v) && p != v # only if pacman is not on a portal cell
            cells[v...] = k
        end
    end

    # apply velocity
    # TODO: apply function
    motion.y, motion.x = p
    motion′.y = motion.y + motion′.dy
    motion′.x = motion.x + motion′.dx
    cell′ = cells[motion′.y, motion′.x]

    hit_wall = !islegal(gs, cell′)

    leftportal = cell′ == gs.params.raw.portal_left
    if leftportal
        motion′.y, motion′.x = gs.portal_locations[gs.params.raw.portal_right]
    end

    rightportal = cell′ == gs.params.raw.portal_right
    if rightportal
        motion′.y, motion′.x = gs.portal_locations[gs.params.raw.portal_left]
    end

    # one-step lookahead given existing position and velocity
    py′′ = motion.y + motion.dy
    px′′ = motion.x + motion.dx
    p′′ = [py′′, px′′]
    cell′′ = cells[p′′...]
    mark = nothing
    mark′ = nothing

    p′ = p

    if subpixelmove
        if hit_wall && islegal(gs, cell′′)
            motion′.y = motion.y + motion.dy # keep previous velocity
            motion′.x = motion.x + motion.dx # keep previous velocity
            p′ = [motion′.y, motion′.x] # [row v^, col <>]
            mark′ = cells[p′...]
            if gs.mark == gs.params.raw.screen
                cells[p...] = gs.mark
            else
                cells[p...] = " "
            end
            cells[p′...] = gs.params.raw.pacman
            gs.mark = mark′
        elseif !hit_wall
            # update
            gs.delay = gs.delay′
            motion.x = motion′.x
            motion.y = motion′.y
            motion.dx = motion′.dx
            motion.dy = motion′.dy
            p′ = [motion′.y, motion′.x] # [row v^, col <>]
            mark′ = cells[p′...]
            if gs.mark == gs.params.raw.screen
                cells[p...] = gs.mark
            else
                cells[p...] = " "
            end
            cells[p′...] = gs.params.raw.pacman
            gs.mark = mark′
        end
    end

    if mark′ == gs.params.raw.dot
        gs.score += gs.params.scores.dot
    elseif mark′ == gs.params.raw.super_dot
        gs.score += gs.params.scores.super_dot
        for k in keys(gs.ghost_infos)
            gi = gs.ghost_infos[k]
            gi.isblue = true
            gi.tblue = t
        end
    end

    ghost_on_pacman = false
    pacman_on_ghost = false

    if subpixelmove
        ghost_on_pacman = moveghost!(gs)
        if ghost_on_pacman
            cells[p′...] = gs.params.raw.dead_pacman
            pacman_on_ghost = true
        end
    end

    for k in keys(gs.ghost_infos)
        gi = gs.ghost_infos[k]
        if abs(gi.tblue - t) > gs.params.timers.super
            gi.isblue = false
            gi.tblue = 0
            gi.isblinking = false
            gi.blinkingon = false
            gi.tblink = 0
        elseif abs(gi.tblue - t) > gs.params.timers.super_blink
            gi.isblinking = true
            if gi.tblink == 0
                gi.tblink = t
                gi.blinkingon = true
            end
            if abs(gi.tblink - t) > 0.2
                gi.blinkingon = !gi.blinkingon
                gi.tblink = t
            end
        end
    end

    # Finished level
    finished = sum(cells .== gs.params.raw.dot) + sum(cells .== gs.params.raw.super_dot) == 0 || pacman_on_ghost || ghost_on_pacman
    drawfield(stylemap(gs; score=gs.score, flicker, finished), size(cells,1), size(cells,2))
    
    if finished
        sleep(gs.done_delay)
        closetask(kbtask)

        resetfield!(gs)
        set_keyboard_input_mode()
        kbtask = capture_keyboard_input!(gs)

        gs.motion = Motion()
        gs.motion′ = Motion()
    end

    return kbtask
end


function getmark(gs, cells, pos)
    cell = cells[pos...]
    if onghost(gs, cell)
        non_ghost_mark = ""
        for cg in whichghosts(cell)
            if !onghost(gs, gs.ghost_infos[cg].mark)
                non_ghost_mark = gs.ghost_infos[cg].mark
                break
            end
        end
    else
        non_ghost_mark = cell
    end
    return non_ghost_mark
end


function moveghost!(gs)
    cells = gs.cells
    gridx = size(cells,2)
    gridy = size(cells,1)

    prev_marks = Dict(map(c->Pair(c, ""), gs.ghost_chars))
    prev_pos = Dict(map(c->Pair(c, []), gs.ghost_chars))
    new_pos = Dict(map(c->Pair(c, []), gs.ghost_chars))

    for c_ghost in gs.ghost_chars
        p_ghost = [findfirst(c->occursin(c_ghost,c), cells).I...]

        _p_ghost = p_ghost
        prev_pos[c_ghost] = _p_ghost

        ghostinfo = gs.ghost_infos[c_ghost]
        prev_marks[c_ghost] = ghostinfo.mark

        los_pellets = count_los_pellets(gs, p_ghost, ghostinfo)

        curr_dir = ghostinfo.dir
        
        if curr_dir != [0, 0] && ghostinfo.isout
            # do not double back (i.e., go backwards)
            los_pellets[gs.params.dirs[findfirst(map(d->d == curr_dir .* -1, gs.params.dirs))]] = 0
        end

        pellets_in_dir = map(d->los_pellets[d], gs.params.dirs)
        total_pellets = sum(pellets_in_dir)
        if total_pellets == 0
            if ghostinfo.isout
                mask = map(d->d ∉ [curr_dir .* -1], gs.params.dirs)
                probs = normalize1(mask)
            else
                mask = ones(length(pellets_in_dir))
                if gs.maze_type == 4
                    cage_mask_dir = [-1,0] # do not move up when in cage (SISL maze has cage opening at pointed down)
                else
                    cage_mask_dir = [1,0] # do not move down when in cage
                end
                cage_mask = map(d->d == cage_mask_dir, gs.params.dirs)
                mask[cage_mask] .= 0
                probs = normalize1(mask)
            end
        else
            probs = normalize1(pellets_in_dir)
        end

        distr = Categorical(probs)
        move_dir = gs.params.dirs[rand(distr)]
        p_ghost′ = p_ghost + move_dir

        while !(checkbounds(Bool, cells, p_ghost′...) && islegal(gs, cells[p_ghost′...]; ghost=ghostinfo))
            move_dir = gs.params.dirs[rand(distr)]
            p_ghost′ = p_ghost + move_dir
        end

        cell′ = cells[p_ghost′...]

        leftportal = cell′ == gs.params.raw.portal_left
        if leftportal
            p_ghost′ = gs.portal_locations[gs.params.raw.portal_right] + move_dir # TODO: Why? off by one??
        end
        
        rightportal = cell′ == gs.params.raw.portal_right
        if rightportal
            p_ghost′ = gs.portal_locations[gs.params.raw.portal_left] + move_dir
        end
        
        p_ghost = p_ghost′
        new_pos[c_ghost] = p_ghost

        ghostinfo.mark = getmark(gs, cells, p_ghost)
        ghostinfo.pos = p_ghost
        ghostinfo.dir = move_dir
        ghostinfo.isout = ghostinfo.isout || ghostinfo.mark == "─"
    end

    for (c_ghost, pos) in prev_pos
        cells[pos...] = prev_marks[c_ghost]
    end

    ghost_on_pacman = false

    for (c_ghost, pos) in new_pos
        this_ghost_on_pacman = cells[pos...] == gs.params.raw.pacman
        if this_ghost_on_pacman
            ghostinfo = gs.ghost_infos[c_ghost]
            if ghostinfo.isblue
                cells[pos...] = gs.ghost_infos[c_ghost].mark
                gs.score += gs.params.scores.ghost # update score
                # send ghost to cage
                gs.ghost_infos[c_ghost] = GhostInfo(
                    init_pos=gs.ghost_infos[c_ghost].init_pos,
                    pos=gs.ghost_infos[c_ghost].init_pos)
                    # isout=(gs.maze_type == 4)) # SISL maze defaults to ghosts already being "out"
                cells[gs.ghost_infos[c_ghost].init_pos...] = c_ghost
            else
                ghost_on_pacman = ghost_on_pacman || this_ghost_on_pacman
                cells[pos...] = gs.params.raw.dead_pacman
            end
        else
            if onghost(gs, cells[pos...]; exclude=c_ghost)
                cells[pos...] *= "+"
                cells[pos...] *= c_ghost
            else
                cells[pos...] = c_ghost
            end
        end
        ghostinfo = gs.ghost_infos[c_ghost]
    end

    return ghost_on_pacman
end


function count_los_pellets(gs::GameState, pos, ghost::GhostInfo)
    C = Dict(map(d->Pair(d, 0), gs.params.dirs))

    for d in gs.params.dirs
        ax = findfirst(abs.(d) .== 1)
        for i in axes(gs.cells, ax)
            pos′ = pos + d*i
            if checkbounds(Bool, gs.cells, pos′...)
                cell′ = gs.cells[pos′...]
                if islegal(gs, cell′; ghost) && !isportal(gs, cell′)
                    C[d] += cell′ ∈ [gs.params.styled.dot, gs.params.styled.super_dot]
                else
                    break
                end
            end
        end
    end
    return C
end


# function pausegame()
#     global gridx
#     pause_msg = "PAUSED: play() to resume"
#     w = 2*(gridx-2)
#     w = max(length(pause_msg)+2, w)
#     println("╔", "─"^w, "╗")
#     buff = Int((w-length(pause_msg))/2)
#     println("║", " "^buff, pause_msg, " "^buff, "║")
#     println("╚", "─"^w, "╝")
# end


# function pausedialog()
#     global gridx
#     pause_msg = "Hit ` to pause"
#     w = 2*(gridx-2)
#     w = max(length(pause_msg), w)
#     buff = Int((w-length(pause_msg))/2)
#     println()
#     println(" "^buff, " ", pause_msg, " "^buff)
# end


function resetfield!(gs::GameState) # score::Int
    # defaults to all four ghosts
    gs.ghost_chars = [gs.params.raw.ghosts.inky, gs.params.raw.ghosts.blinky, gs.params.raw.ghosts.pinky, gs.params.raw.ghosts.clyde]

    for c_ghost in gs.ghost_chars
        gs.ghost_infos[c_ghost] = GhostInfo()
    end

    if gs.maze_type == 1
        gs.ghost_infos[gs.params.raw.ghosts.blinky].isout = true # blinky starts outside
        field = """
                       HIGH SCORE                      
***************************#***************************
╔═════════════════════════╦═╦═════════════════════════╗
║|d d d d d d d d d d d d|║ ║|d d d d d d d d d d d d|║
║|d|╔═════╗|d|╔═══════╗|d|║ ║|d|╔═══════╗|d|╔═════╗|d|║
║|o|║     ║|d|║       ║|d|║ ║|d|║       ║|d|║     ║|o|║
║|d|╚═════╝|d|╚═══════╝|d|╚═╝|d|╚═══════╝|d|╚═════╝|d|║
║|d d d d d d d d d d d d d d d d d d d d d d d d d d|║
║|d|╔═════╗|d|╔═╗|d|╔═════════════╗|d|╔═╗|d|╔═════╗|d|║
║|d|╚═════╝|d|║ ║|d|╚═════╗ ╔═════╝|d|║ ║|d|╚═════╝|d|║
║|d d d d d d|║ ║|d d d d|║ ║|d d d d|║ ║|d d d d d d|║
╚═════════╗|d|║ ╚═════╗|-|║ ║|-|╔═════╝ ║|d|╔═════════╝
          ║|d|║ ╔═════╝|-|╚═╝|-|╚═════╗ ║|d|║          
          ║|d|║ ║|- - - - -𝔹- - - - -|║ ║|d|║          
          ║|d|║ ║|-|╔════─────════╗|-|║ ║|d|║          
══════════╝|d|╚═╝|-|║             ║|-|╚═╝|d|╚══════════
< - - - - - d - - -|║  𝕀   ℙ   ℂ  ║|- - - d - - - - - >
══════════╗|d|╔═╗|-|║             ║|-|╔═╗|d|╔══════════
          ║|d|║ ║|-|╚═════════════╝|-|║ ║|d|║          
          ║|d|║ ║|- - - - - - - - - -|║ ║|d|║          
          ║|d|║ ║|-|╔═════════════╗|-|║ ║|d|║          
╔═════════╝|d|╚═╝|-|╚═════╗ ╔═════╝|-|╚═╝|d|╚═════════╗
║|d d d d d d d d d d d d|║ ║|d d d d d d d d d d d d|║
║|d|╔═════╗|d|╔═══════╗|d|║ ║|d|╔═══════╗|d|╔═════╗|d|║
║|d|╚═══╗ ║|d|╚═══════╝|d|╚═╝|d|╚═══════╝|d|║ ╔═══╝|d|║
║|o d d|║ ║|d d d d d d d  x  d d d d d d d|║ ║|d d o|║
╠═══╗|d|║ ║|d|╔═╗|d|╔═════════════╗|d|╔═╗|d|║ ║|d|╔═══╣
╠═══╝|d|╚═╝|d|║ ║|d|╚═════╗ ╔═════╝|d|║ ║|d|╚═╝|d|╚═══╣
║|d d d d d d|║ ║|d d d d|║ ║|d d d d|║ ║|d d d d d d|║
║|d|╔═════════╝ ╚═════╗|d|║ ║|d|╔═════╝ ╚═════════╗|d|║
║|d|╚═════════════════╝|d|╚═╝|d|╚═════════════════╝|d|║
║|d d d d d d d d d d d d d d d d d d d d d d d d d d|║
╚═════════════════════════════════════════════════════╝
L**L**L************************************************"""
    elseif gs.maze_type == 2
        # 17x19 (Silver et al., 2010)
        # https://www.davidsilver.uk/wp-content/uploads/2020/03/pomcp.mp4
        gs.ghost_infos[gs.params.raw.ghosts.blinky].isout = true # blinky starts outside
        field = """
╔═══════════════════════════════════╗
║|d d d d d d d d d d d d d d d d d|║
║|d|═══|d|═════|d|═|d|═════|d|═══|d|║
║|o d d d d d d d d d d d d d d d o|║
║|d|═══|d|╥|d|════╦════|d|╥|d|═══|d|║
║|d d d d|║|d d d|║|d d d|║|d d d d|║
╚═════╗|d|╠════|d|╨|d|════╣|d|╔═════╝
      ║|d|║|      𝔹      |║|d|║      
══════╝|d|║| |╔═─────═╗| |║|d|╚══════
< - - - d|║| |║ 𝕀 ℙ ℂ ║| |║|d - - - >
══════╗|d|║| |╚═══════╝| |║|d|╔══════
      ║|d|║|             |║|d|║      
╔═════╝|d|╨|d|═════════|d|╨|d|╚═════╗
║|d d d d d d d d x d d d d d d d d|║
║|d|══╗|d|═════|d|═|d|═════|d|╔══|d|║
║|o d|║|d d d d d d d d d d d|║|d o|║
╠══|d|╨|d|╥|d|════╦════|d|╥|d|╨|d|══╣
║|d d d d|║|d d d|║|d d d|║|d d d d|║
║|d|══════╩════|d|╨|d|════╩══════|d|║
║|d d d d d d d d d d d d d d d d d|║
╚═══════════════════════════════════╝
SCORE: #*****************************"""
    elseif gs.maze_type == 3
        gs.ghost_chars = [gs.params.raw.ghosts.inky, gs.params.raw.ghosts.clyde]
        field = """
***************************************
╔═════════╦═════════════════╦═════════╗
║|o d d d|║|d d d d d d d d|║|d d d d|║
║|d|╔══|d|╨|d|═══════════|d|╨|d|══╗|d|║
║|d|║|d d d d d d d d d d d d d d|║|d|║
║|d|╨|d|═══|d|╔══─────══╗|d|═══|d|╨|d|║
║|d d d d d d|║  𝕀   ℂ  ║|d d d d d d|║
║|d|╥|d|═══|d|╚═════════╝|d|═══|d|╥|d|║
║|d|║|d d d d d d  x  d d d d d d|║|d|║
║|d|╚══|d|╥|d|═══════════|d|╥|d|══╝|d|║
║|d d d d|║|d d d d d d d d|║|d d d o|║
╚═════════╩═════════════════╩═════════╝
SCORE: #*******************************"""
    elseif gs.maze_type == 4
        gs.ghost_chars = [gs.params.raw.ghosts.inky, gs.params.raw.ghosts.blinky]
        field = """
    ╔══════════════════════════════════════════════════
    ║|d d d d d d d d d d d d d d d d d d   - - - - - >
    ║|d|╭───────╮|d|╭─╮|d|╭───────╮|d|╭─╮| |╔═════╦════
    ║|d|│_╭─────╯|d|│ │|d|│_╭─────╯|d|│ │| |║  𝕀  ║    
    ║|d = = o d d d|│ │|d = =       d|│ │| |║     ║    
    ║|d|│_╰─────╮|d|│ │|d|│_╰─────╮|d|│ │| |║  𝔹  ║    
    ║|d|╰─────╮_│|d|│ │|d|╰─────╮_│|d|│ │| |╚═───═╣    
    ║|d       = = d|│ │|d d d o = = d|│ │|       |║    
    ║|d|╭─────╯_│|d|│ │|d|╭─────╯_│|d|│ ╰─────╮|d|║    
════╝|d|╰───────╯|d|╰─╯|d|╰───────╯|d|╰───────╯|d|║    
< - - d d d d d d d     x           d d d d d d d|║    
══════════════════════════════════════════════════╝    
SCORE: #***********************************************"""
    else
        error("The maze_type of $(gs.maze_type) needs to be either:
        1 = Classic PacMan
        2 = PocMan 17x19 (Silver et al., 2010)
        3 = PocMan 9x18
        4 = SISL 10x22")
    end

    for k in keys(gs.ghost_infos)
        if k ∉ gs.ghost_chars
            # remove ghost character keys that are not present on the maze
            delete!(gs.ghost_infos, k)
        end
    end

    field = replace(field, gs.params.raw.dot=>gs.params.raw.dot)
    field = replace(field, gs.params.raw.super_dot=>gs.params.raw.super_dot)
    rows = split(field, "\n")
    cells = mapreduce(permutedims, vcat, split.(rows, ""))

    if gs.random_pellets
        pellets = map(c->[c.I...], findall(cells .== gs.params.raw.dot))
        b = rand(length(pellets)) .< 0.5 # randomly flip all points with probability 0.5
        off_pellets = pellets[findall(b)]
        for pellet in off_pellets
            cells[pellet...] = " "
        end
    end

    if occursin(gs.params.raw.portal_left, field)
        gs.portal_locations[gs.params.raw.portal_left] = [findfirst(cells .== gs.params.raw.portal_left).I...]
        gs.portal_locations[gs.params.raw.portal_right] = [findfirst(cells .== gs.params.raw.portal_right).I...]
    end

    for (k,v) in gs.ghost_infos
        if ismissing(v.init_pos) && k in gs.ghost_chars
            v.init_pos = [findfirst(cells .== k).I...]
        end
    end

    gs.cells = cells
    return gs.cells
end


function islegal(gs::GameState, cell; ghost::Union{Missing,GhostInfo}=missing)
    legal_marks = [" ", gs.params.raw.dot, gs.params.raw.super_dot, gs.params.raw.portal_left, gs.params.raw.portal_right, "-", gs.params.raw.screen]
    if !ismissing(ghost)
        push!(legal_marks, gs.params.raw.pacman, gs.ghost_chars...)
        if !ghost.isout
            push!(legal_marks, "─")
        end
    end
    return cell in legal_marks
end

isportal(gs, cell) = cell ∈ [gs.params.raw.portal_left, gs.params.raw.portal_right]
onghost(gs, cell; exclude="") = any(map(c->occursin(c, cell), filter(c->c != exclude, gs.ghost_chars)))
whichghosts(cell) = length(cell) == 1 ? [cell] : split(cell, "+")
outofbounds(cell) = cell == "*"
isbumper(cell) = cell == "|"


function stylemap(gs::GameState; score=0, flicker=false, finished=false)
    params = gs.params
    border = finished ? params.colors.white : gs.maze_type == 4 ? params.colors.darkred : params.colors.blue

    # Handle overlapping ghosts
    cells = copy(gs.cells)
    for i in axes(cells,1)
        for j in axes(cells,2)
            if length(cells[i,j]) > 1
                cells[i,j] = string(cells[i,j][1])
            end
        end
    end

    field = border * join(join.(eachrow(cells)), "\n")
    field = replace(field, params.raw.dot=>paint(params.styled.dot, params.colors.white, border)) # dot
    super_dot_color = flicker ? params.colors.black : params.colors.lightred
    field = replace(field, params.raw.super_dot=>paint(params.styled.super_dot, super_dot_color, border)) # super dot

    function repaint_ghost(c_ghost, f_ghost)
        if haskey(gs.ghost_infos, c_ghost)
            gi = gs.ghost_infos[c_ghost]
            if gi.isblue
                if gi.isblinking && gi.blinkingon
                    return gs.ghosts.blinking(border)
                else
                    return gs.ghosts.blue(border)
                end
            else
                return f_ghost(border)
            end
        else
            return ""
        end
    end
    
    field = replace(field, "HIGH SCORE"=>paint("HIGH SCORE", params.colors.white, border))
    field = replace(field, "SCORE:"=>paint("SCORE:", params.colors.white, border))
    field = replace(field, params.raw.score=>paint(score, params.colors.white, border))
    field = replace(field, "_"=>" ") # illegal area
    field = replace(field, "|"=>" ") # illegal area
    field = replace(field, "*"=>" ") # illegal area
    field = replace(field, params.raw.portal_passage=>" ") # legal area
    field = replace(field, params.raw.portal_left=>" ") # left portal
    field = replace(field, params.raw.portal_right=>" ") # right portal
    field = replace(field, params.raw.screen=>params.styled.screen) # pass-through screen
    field = replace(field, params.raw.ghosts.inky=>repaint_ghost(params.raw.ghosts.inky, gs.ghosts.inky))
    field = replace(field, params.raw.ghosts.blinky=>repaint_ghost(params.raw.ghosts.blinky, gs.ghosts.blinky))
    field = replace(field, params.raw.ghosts.pinky=>repaint_ghost(params.raw.ghosts.pinky, gs.ghosts.pinky))
    field = replace(field, params.raw.ghosts.clyde=>repaint_ghost(params.raw.ghosts.clyde, gs.ghosts.clyde))
    field = replace(field, params.raw.pacman=>paint(params.styled.pacman, params.colors.yellow, border))
    field = replace(field, params.raw.dead_pacman=>paint(params.styled.dead_pacman, params.colors.yellow, border))
    return string(field, params.colors.reset)
end

# Move cursor to (1,1), print field, move cursor to end
function drawfield(field, xmax=1, ymax=1)
    print("\033[1;1H$(field)")
    print("\033[$(xmax);$(ymax)H")
end


function clearscreen()
    println("\33[2J")
end


function set_keyboard_input_mode()
    ccall(:jl_tty_set_mode, Int32, (Ptr{Cvoid}, Int32), stdin.handle, true)
end


# Key input handling
function capture_keyboard_input!(gs::GameState)
    gs.buffer = Channel{Char}(100)

    return @async while !gs.paused
        put!(gs.buffer, read(stdin, Char))
    end
end


function closetask(task)
    try Base.throwto(task, InterruptException()) catch end
end


function close_keyboard_buffer()
    ccall(:jl_tty_set_mode, Int32, (Ptr{Cvoid}, Int32), stdin.handle, false)
end


function readinput(gs)
    if isready(gs.buffer)
        take!(gs.buffer)
    end
end


function keypress!(gs::GameState)
    gs.key = readinput(gs)

    if gs.key == gs.params.keys.left
        gs.motion′.dx, gs.motion′.dy = -1, 0
        gs.delay′ = gs.horiz_delay
    elseif gs.key == gs.params.keys.right
        gs.motion′.dx, gs.motion′.dy = 1, 0
        gs.delay′ = gs.horiz_delay
    elseif gs.key == gs.params.keys.down
        gs.motion′.dx, gs.motion′.dy = 0, 1
        gs.delay′ = gs.vert_delay
    elseif gs.key == gs.params.keys.up
        gs.motion′.dx, gs.motion′.dy = 0, -1
        gs.delay′ = gs.vert_delay
    elseif gs.key == gs.params.keys.tick
        gs.paused = true
        return nothing
    else
        gs.timeout += 1
        gs.paused = false
        return nothing
    end
    gs.timeout = 0
    return nothing
end


end # module
