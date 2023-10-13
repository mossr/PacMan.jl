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

# Modified from Chris DeLeon's 4:30 minute Javascript version
# https://youtu.be/xGmXxpIj6vs

export play, restart, stylemap

# play when running `using Pacman`
__init__() = restart()

global const PM = "⬤"
global const g = "■" # "☗" # ᗣ
global const d = "ᐧ"
global const o = "•"
global const KEY_UP = 'w'
global const KEY_LEFT = 'a'
global const KEY_DOWN = 's'
global const KEY_RIGHT = 'd'
global const KEY_TICK = '`'
global const ─  = "  " # Space character (variable is a box drawing character ASCII 196 ─)
global const SCOREDOT = 10
global const SCORESUPERDOT = 50

hide_cursor() = print("\e[?25l")
show_cursor() = println("\e[?25h")

const Field = Array{String}

global DEFAULTS = (emoji=false, walls=true, size=(20,20))


function resetstate(; emoji=DEFAULTS.emoji, walls=DEFAULTS.walls)
    # global PX = rand(3:gridx-3) # initial player x-position (with some border-buffer)
    # global PY = rand(3:gridy-3) # initial player y-position (with some border-buffer)
    # global ax = rand(2:gridx-1) # initial apple x-position
    # global ay = rand(2:gridy-1) # initial apple y-position
    global VX = 0 # player velocities
    global VY = 0 
    global VX′ = 0 
    global VY′ = 0 
    global SCORE = 0
    global PAUSED = false
    global DELAY = 0.02
    global DELAY′ = DELAY
    global HORIZ_DELAY = DELAY
    global VERT_DELAY = HORIZ_DELAY*2.5
    global MAXTIMEOUT = 120/DELAY
    global TIMEOUT = 0
    global KEY = nothing
    global SUBPIXEL = 2
end


function restart(; kwargs...)
    resetstate(; kwargs...)
    play(; kwargs...)
end


"""
Pacman options:
...
"""
function play(; emoji=DEFAULTS.emoji, walls=DEFAULTS.walls)
    global PAUSED, DELAY′, TIMEOUT, MAXTIMEOUT, SUBPIXEL
    TIMEOUT = 0
    PAUSED = false

    hide_cursor()
    clearscreen()
    cells = resetfield()
    set_keyboard_input_mode()
    task = capture_keyboard_input()

    flicker = false
    cflicker = 0
    maxflicker = 8 * SUBPIXEL

    spc = 0
    subpixelmove = false

    while !PAUSED
        subpixelmove = spc == SUBPIXEL
        if subpixelmove
            spc = 0
        end
        spc += 1

        PAUSED = game!(cells; flicker, subpixelmove)

        flicker = cflicker == maxflicker
        if flicker
            cflicker = 0
        end
        cflicker += 1

        sleep(DELAY)
    end

    close_keyboard_buffer()
    show_cursor()
    try Base.throwto(task, InterruptException()) catch end
    # pausegame()

    return cells
end


function game!(cells; flicker=false, subpixelmove=true)
    global PX, PY, PX′, PY′, VX, VY, VX′, VY′, KEY, DELAY, DELAY′, SCORE, SCOREDOT, SCORESUPERDOT
    global d, o

    gridx = size(cells,2)
    gridy = size(cells,1)

    paused = keypress()

    # get postion
    p = [findall(c->c == "x", cells)[1].I...]
    
    hit_wall = false

    # apply velocity
    PY, PX = p
    PY′ = PY + VY′
    PX′ = PX + VX′
    cell′ = cells[PY′, PX′]

    hit_wall = !islegal(cell′)

    leftportal = cell′ == "<"
    if leftportal
        PX′ = gridx-1
    end

    rightportal = cell′ == ">"
    if rightportal
        PX′ = 2
    end

    # one-step lookahead given existing position and velocity
    py′′ = PY + VY
    px′′ = PX + VX
    cell′′ = cells[py′′, px′′]
    mark = nothing

    if subpixelmove
        if hit_wall && islegal(cell′′)
            PY′ = PY + VY # keep previous velocity
            PX′ = PX + VX # keep previous velocity
            p′ = [PY′, PX′] # [row v^, col <>]
            mark = cells[p′...]
            cells[p...] = " "
            cells[p′...] = "x"
        elseif !hit_wall
            # update
            DELAY = DELAY′
            PX = PX′
            PY = PY′
            VX = VX′
            VY = VY′
            p′ = [PY′, PX′] # [row v^, col <>]
            mark = cells[p′...]
            cells[p...] = " "
            cells[p′...] = "x"
        end
    end
    
    if mark == d
        SCORE += SCOREDOT
    elseif mark == o
        SCORE += SCORESUPERDOT
    end

    # Finished level
    finished = sum(cells .== d) + sum(cells .== o) == 0 || onghost(cell′) || onghost(cell′′)
    drawfield(stylemap(cells; score=SCORE, flicker, finished), size(cells,1), size(cells,2))
    
    if finished
        sleep(3)
        VX = VY = VX′ = VY′ = 0
        cells[:] = resetfield()
    end

    return paused
end


"""
Inner repeat `element` `n-1` times in matrix.
"""
function subpixels(X, n=2, element=" ")
    X′ = similar(X, (n*size(X,1)-(n-1), n*size(X,2)-(n-1)))
    i′ = j′ = 0
    for i in axes(X,1)
        for j in axes(X,2)
            for k in 1:n-1
                # io = 0 # (n÷i-n) + 1
                # jo = 0 # (n÷j-n) + 1
                # if i′+k ≤ size(X′,1) && j′+k ≤ size(X′,2)
                try
                    X′[i+i′, j+j′+k] = element
                    X′[i+i′+k, j+j′] = element
                catch err
                end
            end
            j′ += n-1
        end
        i′ += n-1
    end
    # for i in axes(X′,1)
    #     for j in axes(X′,2)
    #         if mod(i, n) == 0 || mod(j, n) == 0
    #             X′[i,j] = element
    #         else
    #             X′[i,j] = X[clamp(i-(i÷n),1,size(X,1)), clamp(j-(j÷n),1,size(X,2))]
    #         end
    #     end
    # end
    return X′
end


function pausegame()
    global gridx
    pause_msg = "PAUSED: play() to resume"
    w = 2*(gridx-2)
    w = max(length(pause_msg)+2, w)
    println("╔", "─"^w, "╗")
    buff = Int((w-length(pause_msg))/2)
    println("║", " "^buff, pause_msg, " "^buff, "║")
    println("╚", "─"^w, "╝")
end


function pausedialog()
    global gridx
    pause_msg = "Hit ` to pause"
    w = 2*(gridx-2)
    w = max(length(pause_msg), w)
    buff = Int((w-length(pause_msg))/2)
    println()
    println(" "^buff, " ", pause_msg, " "^buff)
end


function resetfield() # score::Int
    global d, o
    field = """
                       HIGH SCORE                        
****************************#****************************
*╔═════════════════════════╦═╦═════════════════════════╗*
*║|d d d d d d d d d d d d|║ ║|d d d d d d d d d d d d|║*
*║|d|╔═════╗|d|╔═══════╗|d|║ ║|d|╔═══════╗|d|╔═════╗|d|║*
*║|o|║     ║|d|║       ║|d|║ ║|d|║       ║|d|║     ║|o|║*
*║|d|╚═════╝|d|╚═══════╝|d|╚═╝|d|╚═══════╝|d|╚═════╝|d|║*
*║|d d d d d d d d d d d d d d d d d d d d d d d d d d|║*
*║|d|╔═════╗|d|╔═╗|d|╔═════════════╗|d|╔═╗|d|╔═════╗|d|║*
*║|d|╚═════╝|d|║ ║|d|╚═════╗ ╔═════╝|d|║ ║|d|╚═════╝|d|║*
*║|d d d d d d|║ ║|d d d d|║ ║|d d d d|║ ║|d d d d d d|║*
*╚═════════╗|d|║ ╚═════╗|-|║ ║|-|╔═════╝ ║|d|╔═════════╝*
           ║|d|║ ╔═════╝|-|╚═╝|-|╚═════╗ ║|d|║           
           ║|d|║ ║|- - - - -𝔹- - - - -|║ ║|d|║           
           ║|d|║ ║|-|╔════─────════╗|-|║ ║|d|║           
*══════════╝|d|╚═╝|-|║             ║|-|╚═╝|d|╚══════════*
*< - - - - - d - - -|║  𝕀   ℙ   ℂ  ║|- - - d - - - - - >*
*══════════╗|d|╔═╗|-|║             ║|-|╔═╗|d|╔══════════*
           ║|d|║ ║|-|╚═════════════╝|-|║ ║|d|║           
           ║|d|║ ║|- - - - - - - - - -|║ ║|d|║           
           ║|d|║ ║|-|╔═════════════╗|-|║ ║|d|║           
*╔═════════╝|d|╚═╝|-|╚═════╗ ╔═════╝|-|╚═╝|d|╚═════════╗*
*║|d d d d d d d d d d d d|║ ║|d d d d d d d d d d d d|║*
*║|d|╔═════╗|d|╔═══════╗|d|║ ║|d|╔═══════╗|d|╔═════╗|d|║*
*║|d|╚═══╗ ║|d|╚═══════╝|d|╚═╝|d|╚═══════╝|d|║ ╔═══╝|d|║*
*║|o d d|║ ║|d d d d d d d  x  d d d d d d d|║ ║|d d o|║*
*╠═══╗|d|║ ║|d|╔═╗|d|╔═════════════╗|d|╔═╗|d|║ ║|d|╔═══╣*
*╠═══╝|d|╚═╝|d|║ ║|d|╚═════╗ ╔═════╝|d|║ ║|d|╚═╝|d|╚═══╣*
*║|d d d d d d|║ ║|d d d d|║ ║|d d d d|║ ║|d d d d d d|║*
*║|d|╔═════════╝ ╚═════╗|d|║ ║|d|╔═════╝ ╚═════════╗|d|║*
*║|d|╚═════════════════╝|d|╚═╝|d|╚═════════════════╝|d|║*
*║|d d d d d d d d d d d d d d d d d d d d d d d d d d|║*
*╚═════════════════════════════════════════════════════╝*
*L**L**L*************************************************"""

    field = replace(field, "d"=>d)
    field = replace(field, "o"=>o)
    rows = split(field, "\n")
    cells = mapreduce(permutedims, vcat, split.(rows, ""))

    return cells
end


function islegal(cell)
    global d, o
    return cell in [" ", d, o, "-", "<", ">"]
end

onghost(cell) = cell in ["𝕀", "𝔹", "ℙ", "ℂ"]

outofbounds(cell) = cell == "*"
isbumper(cell) = cell == "|"


function stylemap(cells; score=0, flicker=false, finished=false)
    global PM, g, d, o

    # https://gist.github.com/JBlond/2fea43a3049b38287e5e9cefc87b2124
    blue = "\e[34m"
    white = "\e[37m"
    red = "\e[31m"
    purple = "\e[35m"
    cyan = "\e[36m"
    yellow = "\e[33m"
    lightyellow = "\e[0;93m"
    colorreset = "\e[0m"
    border = finished ? white : blue

    inky = "$(cyan)$(g)$(border)"
    pinky = "$(purple)$(g)$(border)"
    blinky = "$(red)$(g)$(border)"
    clyde = "$(lightyellow)$(g)$(border)"

    field = white * join(join.(eachrow(cells)), "\n")
    field = replace(field, d=>"$(white)$d$(border)") # dot
    if flicker
        field = replace(field, o=>" ") # super dot
    else
        field = replace(field, o=>"$(red)$(o)$(border)") # super dot
    end
    field = replace(field, "#"=>"$(white)$(score)$(border)") # scire
    field = replace(field, "|"=>" ") # illegal area
    field = replace(field, "*"=>" ") # illegal area
    field = replace(field, "-"=>" ") # legal area
    field = replace(field, ">"=>" ") # right portal
    field = replace(field, "<"=>" ") # left portal
    field = replace(field, "x"=>"$(yellow)$(PM)$(border)")
    field = replace(field, "𝕀"=>inky)
    field = replace(field, "𝔹"=>blinky)
    field = replace(field, "ℙ"=>pinky)
    field = replace(field, "ℂ"=>clyde)
    return string(field, colorreset)
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
global BUFFER
function capture_keyboard_input()
    global BUFFER, PAUSED
    BUFFER = Channel{Char}(100)

    return @async while !PAUSED
        put!(BUFFER, read(stdin, Char))
    end
end


function close_keyboard_buffer()
    ccall(:jl_tty_set_mode, Int32, (Ptr{Cvoid}, Int32), stdin.handle, false)
end


function readinput()
    if isready(BUFFER)
        take!(BUFFER)
    end
end


function keypress()
    global VX′, VY′, KEY, DELAY, DELAY′, TIMEOUT, HORIZ_DELAY, VERT_DELAY
    KEY = readinput()
    if KEY == KEY_LEFT
        VX′, VY′ = -1, 0
        DELAY′ = HORIZ_DELAY
    elseif KEY == KEY_RIGHT
        VX′, VY′ = 1, 0
        DELAY′ = HORIZ_DELAY
    elseif KEY == KEY_DOWN
        VX′, VY′ = 0, 1
        DELAY′ = VERT_DELAY
    elseif KEY == KEY_UP
        VX′, VY′ = 0, -1
        DELAY′ = VERT_DELAY
    elseif KEY == KEY_TICK
        return true # game over
    else
        TIMEOUT += 1
        return false
    end
    TIMEOUT = 0
    return false
end


function drawapple!(field)
    global EMOJI, ax, ay
    apple = EMOJI ? "🍎" : "\e[31;1m$GHST\e[0m"
    field[ay,ax] = apple
end


end # module
