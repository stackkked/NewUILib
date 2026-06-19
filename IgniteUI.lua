--==============================================================
-- IGNITE UI LIBRARY v1.0.0
-- Production-ready UI Library for Roblox executors.
-- Single-file, OOP, themeable, persistent, anti-detect.
--
-- Load pattern:
--     local Library = loadstring( game:HttpGet( "..." ) )()
--     local Window  = Library:CreateWindow( { Name = "Ignite" } )
--
-- All colors / fonts / sizes are centralised in Library.Themes.*.
-- All connections / tweens / instances are tracked and cleaned up
-- on :Destroy().
--==============================================================

--!strict
-- ( Internal modules are non-strict; the !strict here is for the
--   top-level file only and is downgraded locally where needed. )

--==============================================================
-- SECTION 1: SERVICES & UTILITIES
--==============================================================

local Services = {}
local function S( name: string ): Instance
    local svc = Services[ name ]
    if not svc then
        svc = game:GetService( name )
        Services[ name ] = svc
    end
    return svc
end

local TweenService       = S( "TweenService" )
local UserInputService   = S( "UserInputService" )
local RunService         = S( "RunService" )
local ContextActionService = S( "ContextActionService" )
local TextService        = S( "TextService" )
local HttpService        = S( "HttpService" )
local Players            = S( "Players" )
local CoreGui            = S( "CoreGui" )
local StarterGui         = S( "StarterGui" )
local Workspace          = S( "Workspace" )
local Lighting           = S( "Lighting" )

local LocalPlayer = Players.LocalPlayer

-- Utils table
local Utils = {}

-- Clamp a number between min and max.
function Utils.clamp( v: number, min: number, max: number ): number
    if v < min then return min end
    if v > max then return max end
    return v
end

-- Linear interpolation.
function Utils.lerp( a: number, b: number, t: number ): number
    return a + ( b - a ) * t
end

-- Round to N decimals.
function Utils.round( v: number, decimals: number? ): number
    local d = decimals or 0
    local m = 10 ^ d
    return math.floor( v * m + 0.5 ) / m
end

-- Deep-copy a table ( handles cycles via cached map ).
function Utils.deepCopy( t: any, seen: any? ): any
    if typeof( t ) ~= "table" then return t end
    seen = seen or {}
    if seen[ t ] then return seen[ t ] end
    local copy = {}
    seen[ t ] = copy
    for k, v in pairs( t ) do
        copy[ k ] = Utils.deepCopy( v, seen )
    end
    return copy
end

-- Merge source into target ( shallow ).
function Utils.merge( target: any, source: any ): any
    for k, v in pairs( source ) do
        target[ k ] = v
    end
    return target
end

-- Convert Color3 to hex string "RRGGBB".
function Utils.colorToHex( c: Color3 ): string
    return string.format(
        "%02X%02X%02X",
        math.floor( c.R * 255 + 0.5 ),
        math.floor( c.G * 255 + 0.5 ),
        math.floor( c.B * 255 + 0.5 )
    )
end

-- Convert hex string to Color3.
function Utils.hexToColor( hex: string ): Color3
    hex = hex:gsub( "#", "" )
    if #hex == 3 then
        hex = hex:sub( 1, 1 ):rep( 2 )
            .. hex:sub( 2, 2 ):rep( 2 )
            .. hex:sub( 3, 3 ):rep( 2 )
    end
    local r = tonumber( hex:sub( 1, 2 ), 16 ) or 0
    local g = tonumber( hex:sub( 3, 4 ), 16 ) or 0
    local b = tonumber( hex:sub( 5, 6 ), 16 ) or 0
    return Color3.fromRGB( r, g, b )
end

-- Convert HSV -> Color3 ( wraps Color3.fromHSV ).
function Utils.hsvToColor( h: number, s: number, v: number ): Color3
    return Color3.fromHSV( h, s, v )
end

-- Convert Color3 -> r, g, b 0..255 integers.
function Utils.colorToRGB( c: Color3 ): ( number, number, number )
    return math.floor( c.R * 255 + 0.5 ),
           math.floor( c.G * 255 + 0.5 ),
           math.floor( c.B * 255 + 0.5 )
end

-- Generate a unique-ish id ( executor-safe, no debug lib needed ).
function Utils.uid( prefix: string? ): string
    prefix = prefix or "id"
    return prefix .. "_" .. tostring( {} ):sub( 8 )
                    .. "_" .. tostring( math.floor( tick() * 1000 ) % 100000 )
end

-- Format a number with optional thousands separator.
function Utils.formatNumber( v: number, decimals: number? ): string
    if decimals and decimals > 0 then
        return string.format( "%." .. decimals .. "f", v )
    end
    return tostring( math.floor( v + 0.5 ) )
end

-- Safe call wrapper.
function Utils.safe( fn: ( ... ) -> ... ): ( boolean, any )
    return pcall( fn )
end

-- Get mouse location accounting for GuiInset.
function Utils.getMouseLocation(): Vector2
    local loc = UserInputService:GetMouseLocation()
    local inset = ( UserInputService:GetGuiInset() )
    return Vector2.new( loc.X, loc.Y - inset.Y )
end

-- Determine GUI parent ( anti-detect: prefer gethui / syn.protect_gui ).
function Utils.getGuiParent(): Instance
    -- 1. gethui() if available
    local ok, hui = pcall( function()
        if type( gethui ) == "function" then return gethui() end
        return nil
    end )
    if ok and typeof( hui ) == "Instance" then
        return hui
    end
    -- 2. syn.protect_gui + CoreGui
    if syn and type( syn.protect_gui ) == "function" then
        -- Caller will wrap with protect_gui; we just give CoreGui.
        return CoreGui
    end
    -- 3. Plain CoreGui ( Studio / less-protected executors )
    return CoreGui
end

-- Apply protect_gui if available, otherwise no-op.
function Utils.protectGui( gui: Instance )
    if syn and type( syn.protect_gui ) == "function" then
        pcall( syn.protect_gui, gui )
    end
end

-- Get executor name ( best-effort ).
function Utils.getExecutorName(): string
    local ok, name = pcall( function()
        if type( identifyexecutor ) == "function" then
            local n, v = identifyexecutor()
            return ( n or "Unknown" ) .. ( v and ( " " .. v ) or "" )
        end
        return "Unknown"
    end )
    if ok and type( name ) == "string" then return name end
    return "Studio"
end

--==============================================================
-- SECTION 2: EASING
--==============================================================

local Easing = {
    Linear       = { Enum.EasingStyle.Linear,       Enum.EasingDirection.InOut },
    QuadIn       = { Enum.EasingStyle.Quad,         Enum.EasingDirection.In    },
    QuadOut      = { Enum.EasingStyle.Quad,         Enum.EasingDirection.Out   },
    QuadInOut    = { Enum.EasingStyle.Quad,         Enum.EasingDirection.InOut },
    CubicIn      = { Enum.EasingStyle.Cubic,        Enum.EasingDirection.In    },
    CubicOut     = { Enum.EasingStyle.Cubic,        Enum.EasingDirection.Out   },
    QuartIn      = { Enum.EasingStyle.Quart,        Enum.EasingDirection.In    },
    QuartOut     = { Enum.EasingStyle.Quart,        Enum.EasingDirection.Out   },
    QuintIn      = { Enum.EasingStyle.Quint,        Enum.EasingDirection.In    },
    QuintOut     = { Enum.EasingStyle.Quint,        Enum.EasingDirection.Out   },
    SineIn       = { Enum.EasingStyle.Sine,         Enum.EasingDirection.In    },
    SineOut      = { Enum.EasingStyle.Sine,         Enum.EasingDirection.Out   },
    SineInOut    = { Enum.EasingStyle.Sine,         Enum.EasingDirection.InOut },
    BackIn       = { Enum.EasingStyle.Back,         Enum.EasingDirection.In    },
    BackOut      = { Enum.EasingStyle.Back,         Enum.EasingDirection.Out   },
    BounceIn     = { Enum.EasingStyle.Bounce,       Enum.EasingDirection.In    },
    BounceOut    = { Enum.EasingStyle.Bounce,       Enum.EasingDirection.Out   },
    ElasticIn    = { Enum.EasingStyle.Elastic,      Enum.EasingDirection.In    },
    ElasticOut   = { Enum.EasingStyle.Elastic,      Enum.EasingDirection.Out   },
}

--==============================================================
-- SECTION 3: SIGNAL
--==============================================================

-- Lightweight RBXScriptSignal replacement.
local Signal = {}
Signal.__index = Signal
Signal._type = "Signal"

function Signal.new()
    local self = setmetatable( {}, Signal )
    self._handlers = {}
    self._deferred = {}
    self._firing = false
    return self
end

function Signal:Connect( fn: ( ... ) -> ... )
    assert( type( fn ) == "function", "Signal:Connect expects a function" )
    local handler = { fn = fn, connected = true }
    table.insert( self._handlers, handler )
    local s = self
    return {
        Disconnect = function()
            if not handler.connected then return end
            handler.connected = false
            if s._firing then
                -- Mark for removal after iteration.
                handler._dead = true
            else
                local i = table.find( s._handlers, handler )
                if i then table.remove( s._handlers, i ) end
            end
        end,
        Connected = function() return handler.connected end,
    }
end

function Signal:Once( fn: ( ... ) -> ... )
    local conn
    conn = self:Connect( function( ... )
        if conn then conn:Disconnect() end
        fn( ... )
    end )
    return conn
end

function Signal:Fire( ... )
    self._firing = true
    for _, h in ipairs( self._handlers ) do
        if h.connected and not h._dead then
            local ok, err = pcall( h.fn, ... )
            if not ok then
                warn( "[Ignite:Signal] handler error: " .. tostring( err ) )
            end
        end
    end
    self._firing = false
    -- Cleanup dead handlers
    for i = #self._handlers, 1, -1 do
        if self._handlers[ i ]._dead or not self._handlers[ i ].connected then
            table.remove( self._handlers, i )
        end
    end
end

function Signal:Wait(): ( ... )
    local thread = coroutine.running()
    local args
    local conn
    conn = self:Connect( function( ... )
        args = table.pack( ... )
        if conn then conn:Disconnect() end
        task.spawn( function()
            coroutine.resume( thread )
        end )
    end )
    coroutine.yield()
    return table.unpack( args, 1, args.n )
end

function Signal:DisconnectAll()
    for _, h in ipairs( self._handlers ) do
        h.connected = false
    end
    self._handlers = {}
end

function Signal:Destroy()
    self:DisconnectAll()
end

--==============================================================
-- SECTION 4: MAID / JANITOR
--==============================================================

local Maid = {}
Maid.__index = Maid
Maid._type = "Maid"

function Maid.new()
    local self = setmetatable( {}, Maid )
    self._tasks = {}
    return self
end

function Maid:GiveTask( task )
    assert( task ~= nil, "Maid:GiveTask expects non-nil" )
    table.insert( self._tasks, task )
    return task
end

function Maid:GivePromise( fn )
    local co = coroutine.create( fn )
    table.insert( self._tasks, co )
    return co
end

function Maid:Clean()
    for _, t in ipairs( self._tasks ) do
        local tt = typeof( t )
        if tt == "Instance" then
            pcall( function() t:Destroy() end )
        elseif tt == "table" then
            if type( t.Disconnect ) == "function" then
                pcall( t.Disconnect, t )
            elseif type( t.Destroy ) == "function" then
                pcall( t.Destroy, t )
            end
        elseif tt == "thread" then
            pcall( function() coroutine.close( t ) end )
        end
    end
    self._tasks = {}
end

Maid.Destroy = Maid.Clean

--==============================================================
-- SECTION 5: THEME
--==============================================================

-- Default dark theme ( Ignite orange / cyberpunk ).
local DarkTheme = {
    -- Background layers
    Background_Darkest    = Color3.fromHex( "0A0A0A" ),
    Background_Base       = Color3.fromHex( "0F0F0F" ),
    Background_Window     = Color3.fromHex( "141414" ),
    Background_Panel      = Color3.fromHex( "1A1A1A" ),
    Background_Card       = Color3.fromHex( "1F1F1F" ),
    Background_CardHover  = Color3.fromHex( "252525" ),
    Background_CardActive = Color3.fromHex( "2D2D2D" ),
    Background_Input      = Color3.fromHex( "0A0A0A" ),
    Background_Console    = Color3.fromHex( "050505" ),
    Background_Overlay    = Color3.fromHex( "000000" ),

    -- Text
    Text_Primary    = Color3.fromHex( "FFFFFF" ),
    Text_Secondary  = Color3.fromHex( "C8C8C8" ),
    Text_Tertiary   = Color3.fromHex( "888888" ),
    Text_Quaternary = Color3.fromHex( "555555" ),
    Text_Accent     = Color3.fromHex( "FFB088" ),
    Text_OnAccent   = Color3.fromHex( "1A0A00" ),
    Text_Success    = Color3.fromHex( "4ADE80" ),
    Text_Warning    = Color3.fromHex( "FBBF24" ),
    Text_Error      = Color3.fromHex( "F87171" ),
    Text_Info       = Color3.fromHex( "60A5FA" ),

    -- Accent
    Accent_Primary        = Color3.fromHex( "FF6600" ),
    Accent_Hover          = Color3.fromHex( "FF8533" ),
    Accent_Pressed        = Color3.fromHex( "CC5200" ),
    Accent_Disabled       = Color3.fromHex( "663300" ),
    Accent_Glow           = Color3.fromHex( "FF6600" ),
    Accent_GradientStart  = Color3.fromHex( "FF6600" ),
    Accent_GradientEnd    = Color3.fromHex( "FF3300" ),

    -- Semantic states
    State_Success_Primary    = Color3.fromHex( "22C55E" ),
    State_Success_Background = Color3.fromHex( "16291C" ),
    State_Warning_Primary    = Color3.fromHex( "F59E0B" ),
    State_Warning_Background = Color3.fromHex( "2A2118" ),
    State_Error_Primary      = Color3.fromHex( "EF4444" ),
    State_Error_Background   = Color3.fromHex( "2A1818" ),
    State_Info_Primary       = Color3.fromHex( "3B82F6" ),
    State_Info_Background    = Color3.fromHex( "1A1F2E" ),

    -- Borders / dividers
    Border_Default  = Color3.fromHex( "2A2A2A" ),
    Border_Hover    = Color3.fromHex( "3A3A3A" ),
    Border_Active   = Color3.fromHex( "FF6600" ),
    Border_Disabled = Color3.fromHex( "1F1F1F" ),
    Border_Subtle   = Color3.fromHex( "1A1A1A" ),
    Divider         = Color3.fromRGB( 255, 255, 255 ),

    -- Transparency
    Transparency_Window       = 0.00,
    Transparency_Panel        = 0.05,
    Transparency_Card         = 0.00,
    Transparency_CardHover    = 0.00,
    Transparency_Popover      = 0.02,
    Transparency_Notification = 0.05,
    Transparency_Overlay      = 0.50,
    Transparency_Disabled     = 0.50,
    Transparency_Divider      = 0.94, -- alpha 0.06

    -- Fonts
    Font_Main     = Enum.Font.GothamMedium,
    Font_Heading  = Enum.Font.GothamBold,
    Font_Body     = Enum.Font.Gotham,
    Font_Caption  = Enum.Font.GothamSmall,
    Font_Mono     = Enum.Font.RobotoMono,

    -- Sizes
    Size_Display    = 24,
    Size_H1         = 20,
    Size_H2         = 16,
    Size_H3         = 14,
    Size_Body       = 13,
    Size_BodySmall  = 12,
    Size_Caption    = 11,
    Size_Micro      = 10,
    Size_Icon_Small = 14,
    Size_Icon_Med   = 18,
    Size_Icon_Large = 24,
    Size_Icon_XL    = 32,

    -- Corner radii
    Corner_Small  = UDim.new( 0, 4 ),
    Corner_Medium = UDim.new( 0, 8 ),
    Corner_Large  = UDim.new( 0, 12 ),
    Corner_XL     = UDim.new( 0, 16 ),

    -- Window defaults
    Window_Width  = 720,
    Window_Height = 520,
    Header_Height = 48,
    Sidebar_Width = 64,
    Sidebar_Width_Expanded = 200,
    TabBar_Height = 36,
    Subsection_Height = 32,

    -- Animation durations ( seconds )
    Anim_Fast     = 0.10,
    Anim_Normal   = 0.18,
    Anim_Slow     = 0.30,
    Anim_Slower   = 0.50,
}

-- AMOLED variant ( pure black background ).
local AmoledTheme = Utils.deepCopy( DarkTheme )
AmoledTheme.Background_Darkest    = Color3.fromHex( "000000" )
AmoledTheme.Background_Base       = Color3.fromHex( "000000" )
AmoledTheme.Background_Window     = Color3.fromHex( "050505" )
AmoledTheme.Background_Panel      = Color3.fromHex( "0A0A0A" )
AmoledTheme.Background_Card       = Color3.fromHex( "0F0F0F" )
AmoledTheme.Background_CardHover  = Color3.fromHex( "161616" )
AmoledTheme.Background_CardActive = Color3.fromHex( "1E1E1E" )
AmoledTheme.Background_Input      = Color3.fromHex( "000000" )

-- Light variant.
local LightTheme = Utils.deepCopy( DarkTheme )
LightTheme.Background_Darkest    = Color3.fromHex( "FFFFFF" )
LightTheme.Background_Base       = Color3.fromHex( "F8F8F8" )
LightTheme.Background_Window     = Color3.fromHex( "FFFFFF" )
LightTheme.Background_Panel      = Color3.fromHex( "F2F2F2" )
LightTheme.Background_Card       = Color3.fromHex( "FFFFFF" )
LightTheme.Background_CardHover  = Color3.fromHex( "EAEAEA" )
LightTheme.Background_CardActive = Color3.fromHex( "E2E2E2" )
LightTheme.Background_Input      = Color3.fromHex( "FAFAFA" )
LightTheme.Background_Overlay    = Color3.fromHex( "000000" )

LightTheme.Text_Primary    = Color3.fromHex( "0A0A0A" )
LightTheme.Text_Secondary  = Color3.fromHex( "333333" )
LightTheme.Text_Tertiary   = Color3.fromHex( "666666" )
LightTheme.Text_Quaternary = Color3.fromHex( "999999" )
LightTheme.Text_OnAccent   = Color3.fromHex( "FFFFFF" )

LightTheme.Border_Default  = Color3.fromHex( "DDDDDD" )
LightTheme.Border_Hover    = Color3.fromHex( "CCCCCC" )
LightTheme.Border_Subtle   = Color3.fromHex( "EAEAEA" )

LightTheme.Divider = Color3.fromRGB( 0, 0, 0 )
LightTheme.Transparency_Divider = 0.92

-- Theme manager ( singleton ).
local ThemeManager = {}
ThemeManager._current = DarkTheme
ThemeManager._changed = Signal.new()

function ThemeManager.get()
    return ThemeManager._current
end

function ThemeManager.set( theme )
    ThemeManager._current = theme
    ThemeManager._changed:Fire( theme )
end

function ThemeManager.override( partial )
    local merged = Utils.merge( Utils.deepCopy( ThemeManager._current ), partial )
    ThemeManager._current = merged
    ThemeManager._changed:Fire( merged )
end

function ThemeManager.copyCurrent()
    return Utils.deepCopy( ThemeManager._current )
end

function ThemeManager.changed()
    return ThemeManager._changed
end

--==============================================================
-- SECTION 6: ICONS
--==============================================================

-- Unicode ( Segoe Fluent Icons / fallback glyphs ) + rbxassetid mapping.
local Icons = {
    -- Sidebar / tabs
    sword      = "\u{1F5E1}",   -- dagger
    eye        = "\u{1F441}",   -- eye
    user       = "\u{1F464}",   -- bust
    gun        = "\u{1F3F9}",   -- bow ( placeholder for "skins" )
    gear       = "\u{2699}",    -- gear
    crosshair  = "\u{1F3AF}",   -- direct hit
    wave       = "\u{1F30A}",   -- wave ( kill aura )
    shield     = "\u{1F6E1}",   -- shield ( anti aim )
    sliders    = "\u{1F39A}",   -- sliders ( modifications )
    fire       = "\u{1F525}",   -- fire ( logo )
    clock      = "\u{23F1}",    -- stopwatch
    chart      = "\u{1F4C8}",   -- chart

    -- Controls
    plus       = "\u{2795}",
    minus      = "\u{2796}",
    close      = "\u{2715}",
    close_x    = "\u{274C}",
    search     = "\u{1F50D}",
    chevron_down  = "\u{25BC}",
    chevron_up    = "\u{25B2}",
    chevron_right = "\u{25B6}",
    chevron_left  = "\u{25C0}",
    check      = "\u{2713}",
    check_circle = "\u{2705}",
    warning    = "\u{26A0}",
    error      = "\u{274C}",
    info       = "\u{2139}",
    save       = "\u{1F4BE}",
    load       = "\u{1F4C2}",
    copy       = "\u{1F4CB}",
    paste      = "\u{1F4CA}",
    refresh    = "\u{21BB}",
    power      = "\u{23FB}",
    download   = "\u{1F4E5}",
    play       = "\u{25B6}",
    sun        = "\u{2600}",
    moon       = "\u{1F319}",
}

-- Fallback: if a glyph is not renderable, use first letter.
local function getIcon( name: string ): string
    local icon = Icons[ name ]
    if icon then return icon end
    return "?"
end

--==============================================================
-- SECTION 7: ANIMATION HELPERS
--==============================================================

-- Tween a single property of an instance with optional easing.
local function Animate( inst: Instance, props: any, duration: number?,
                        easingStyle: Enum.PoseEasingStyle?,
                        easingDir: Enum.EasingDirection? ): Tween
    local t = duration or 0.18
    local style = easingStyle or Enum.EasingStyle.Quad
    local dir = easingDir or Enum.EasingDirection.Out
    local info = TweenInfo.new( t, style, dir )
    local tween = TweenService:Create( inst, info, props )
    tween:Play()
    return tween
end

-- Run a sequence of tweens in order.
local function AnimateSequence( steps: any )
    task.spawn( function()
        for _, step in ipairs( steps ) do
            local t = Animate( step.inst, step.props, step.duration,
                               step.style, step.dir )
            if step.wait ~= false then
                t.Completed:Wait()
            end
        end
    end )
end

--==============================================================
-- SECTION 8: COMPONENT BASE CLASS
--==============================================================

local Component = {}
Component.__index = Component
Component._type = "Component"
Component._destroyed = false

function Component.new()
    local self = setmetatable( {}, Component )
    self._parent = nil
    self._connections = {}
    self._tweens = {}
    self._instances = {}
    self._children = {}
    self._signals = {}
    self._maid = Maid.new()
    self._enabled = true
    self._visible = true
    self._tooltipText = nil
    -- Pre-create the universal "Changed" signal so consumers can
    -- call `comp.Changed:Connect(...)` immediately after construction.
    self.Changed = self:_signal( "Changed" )
    return self
end

function Component:_addConnection( conn )
    table.insert( self._connections, conn )
    return conn
end

function Component:_addInstance( inst, key )
    table.insert( self._instances, inst )
    if key then self._instances[ key ] = inst end
    return inst
end

function Component:_trackTween( tween )
    table.insert( self._tweens, tween )
    local s = self
    tween.Completed:Once( function()
        local i = table.find( s._tweens, tween )
        if i then table.remove( s._tweens, i ) end
    end )
    return tween
end

function Component:_addChild( child )
    table.insert( self._children, child )
    return child
end

function Component:_signal( name )
    if not self._signals[ name ] then
        self._signals[ name ] = Signal.new()
    end
    return self._signals[ name ]
end

-- Polymorphic interface ( overridden by subclasses ).
function Component:SetValue( _value ) end
function Component:GetValue() return nil end
function Component:SetEnabled( state: boolean )
    self._enabled = state
end
function Component:SetVisible( state: boolean )
    self._visible = state
end
function Component:SetTooltip( text: string? )
    self._tooltipText = text
end

function Component:Destroy()
    if self._destroyed then return end
    self._destroyed = true
    -- Disconnect signals first
    for _, s in pairs( self._signals ) do
        pcall( function() s:DisconnectAll() end )
    end
    self._signals = {}
    -- Disconnect connections
    for _, c in ipairs( self._connections ) do
        pcall( function()
            if type( c ) == "table" and c.Disconnect then
                c:Disconnect()
            elseif typeof( c ) == "RBXScriptConnection" then
                c:Disconnect()
            end
        end )
    end
    self._connections = {}
    -- Cancel tweens
    for _, t in ipairs( self._tweens ) do
        pcall( function() t:Cancel() end )
    end
    self._tweens = {}
    -- Destroy child components
    for _, child in ipairs( self._children ) do
        if child and type( child.Destroy ) == "function" then
            pcall( child.Destroy, child )
        end
    end
    self._children = {}
    -- Destroy instances
    for _, inst in ipairs( self._instances ) do
        pcall( function() inst:Destroy() end )
    end
    self._instances = {}
    -- Clean maid
    pcall( function() self._maid:Clean() end )
end

--==============================================================
-- SECTION 9: HELPER BUILDERS
--==============================================================

-- Create a generic Frame with sane defaults.
local function makeFrame( parent: Instance?, props: any, children: any? ): Frame
    local f = Instance.new( "Frame" )
    f.BackgroundColor3 = Color3.fromHex( "1A1A1A" )
    f.BackgroundTransparency = 1
    f.BorderSizePixel = 0
    if props then
        for k, v in pairs( props ) do
            f[ k ] = v
        end
    end
    if children then
        for _, c in ipairs( children ) do
            c.Parent = f
        end
    end
    if parent then f.Parent = parent end
    return f
end

-- Create a TextLabel with sane defaults.
local function makeLabel( parent: Instance?, props: any, children: any? ): TextLabel
    local l = Instance.new( "TextLabel" )
    l.BackgroundTransparency = 1
    l.BorderSizePixel = 0
    l.Font = Enum.Font.Gotham
    l.TextColor3 = Color3.fromHex( "FFFFFF" )
    l.TextSize = 13
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Center
    l.RichText = false
    if props then
        for k, v in pairs( props ) do
            l[ k ] = v
        end
    end
    if children then
        for _, c in ipairs( children ) do
            c.Parent = l
        end
    end
    if parent then l.Parent = parent end
    return l
end

-- Create a TextButton with sane defaults.
local function makeButton( parent: Instance?, props: any, children: any? ): TextButton
    local b = Instance.new( "TextButton" )
    b.BackgroundTransparency = 1
    b.BorderSizePixel = 0
    b.AutoButtonColor = false
    b.Font = Enum.Font.GothamMedium
    b.TextColor3 = Color3.fromHex( "FFFFFF" )
    b.TextSize = 13
    b.TextXAlignment = Enum.TextXAlignment.Center
    b.TextYAlignment = Enum.TextYAlignment.Center
    if props then
        for k, v in pairs( props ) do
            b[ k ] = v
        end
    end
    if children then
        for _, c in ipairs( children ) do
            c.Parent = b
        end
    end
    if parent then b.Parent = parent end
    return b
end

-- Create an ImageLabel with sane defaults.
local function makeImage( parent: Instance?, props: any, children: any? ): ImageLabel
    local i = Instance.new( "ImageLabel" )
    i.BackgroundTransparency = 1
    i.BorderSizePixel = 0
    if props then
        for k, v in pairs( props ) do
            i[ k ] = v
        end
    end
    if children then
        for _, c in ipairs( children ) do
            c.Parent = i
        end
    end
    if parent then i.Parent = parent end
    return i
end

-- Create a ScrollingFrame with sane defaults.
local function makeScroll( parent: Instance?, props: any, children: any? ): ScrollingFrame
    local s = Instance.new( "ScrollingFrame" )
    s.BackgroundTransparency = 1
    s.BorderSizePixel = 0
    s.ScrollBarThickness = 4
    s.ScrollBarImageColor3 = Color3.fromHex( "2A2A2A" )
    s.ScrollBarImageTransparency = 0.2
    s.CanvasSize = UDim2.new( 0, 0, 0, 0 )
    s.AutomaticCanvasSize = Enum.AutomaticSize.Y
    s.ScrollingDirection = Enum.ScrollingDirection.Y
    s.ElasticBehavior = Enum.ElasticBehavior.Never
    if props then
        for k, v in pairs( props ) do
            s[ k ] = v
        end
    end
    if children then
        for _, c in ipairs( children ) do
            c.Parent = s
        end
    end
    if parent then s.Parent = parent end
    return s
end

-- Add a UICorner.
local function addCorner( parent: Instance, radius: UDim ): UICorner
    local c = Instance.new( "UICorner" )
    c.CornerRadius = radius
    c.Parent = parent
    return c
end

-- Add a UIStroke.
local function addStroke( parent: Instance, thickness: number?, color: Color3?,
                          transparency: number?, applyStrokeMode: any? ): UIStroke
    local s = Instance.new( "UIStroke" )
    s.Thickness = thickness or 1
    s.Color = color or Color3.fromHex( "2A2A2A" )
    s.Transparency = transparency or 0
    s.ApplyStrokeMode = applyStrokeMode or Enum.ApplyStrokeMode.Border
    s.Parent = parent
    return s
end

-- Add a UIGradient.
local function addGradient( parent: Instance, colorSeq: ColorSequence,
                            rotation: number? ): UIGradient
    local g = Instance.new( "UIGradient" )
    g.Color = colorSeq
    g.Rotation = rotation or 0
    g.Parent = parent
    return g
end

-- Add a UIPadding.
local function addPadding( parent: Instance, padding: UDim? ): UIPadding
    local p = Instance.new( "UIPadding" )
    if padding then
        p.PaddingTop = padding
        p.PaddingBottom = padding
        p.PaddingLeft = padding
        p.PaddingRight = padding
    else
        p.PaddingTop = UDim.new( 0, 8 )
        p.PaddingBottom = UDim.new( 0, 8 )
        p.PaddingLeft = UDim.new( 0, 8 )
        p.PaddingRight = UDim.new( 0, 8 )
    end
    p.Parent = parent
    return p
end

-- Add a UIListLayout.
local function addList( parent: Instance, fillDir: Enum.FillDirection?,
                        padding: UDim?, horiz: Enum.HorizontalAlignment?,
                        vert: Enum.VerticalAlignment?, sort: Enum.SortOrder? ): UIListLayout
    local l = Instance.new( "UIListLayout" )
    l.FillDirection = fillDir or Enum.FillDirection.Vertical
    l.Padding = padding or UDim.new( 0, 0 )
    l.HorizontalAlignment = horiz or Enum.HorizontalAlignment.Center
    l.VerticalAlignment = vert or Enum.VerticalAlignment.Top
    l.SortOrder = sort or Enum.SortOrder.LayoutOrder
    l.Parent = parent
    return l
end

-- Convenience: tween color/transparency with theme-friendly defaults.
local function tweenHover( inst: Instance, targetColor: Color3,
                           targetTransparency: number, duration: number? )
    return Animate( inst, {
        BackgroundColor3 = targetColor,
        BackgroundTransparency = targetTransparency,
    }, duration or 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out )
end

-- Track hover state on a button-like instance.
local function bindHover( inst: GuiButton, onEnter: ( ) -> (), onLeave: ( ) -> () )
    local enterConn = inst.MouseEnter:Connect( function()
        if onEnter then onEnter() end
    end )
    local leaveConn = inst.MouseLeave:Connect( function()
        if onLeave then onLeave() end
    end )
    return enterConn, leaveConn
end

--==============================================================
-- SECTION 10: TOGGLE COMPONENT
--==============================================================

local Toggle = setmetatable( {}, Component )
Toggle.__index = Toggle
Toggle._type = "Toggle"

function Toggle.new( parent: Instance, config: any )
    local self = setmetatable( Component.new(), Toggle )
    self._value = config.Default == true
    self._flag = config.Flag
    self._keybindInst = nil
    self._callback = config.Callback
    self:_build( parent, config )
    return self
end

function Toggle:_build( parent: Instance, config: any )
    local theme = ThemeManager.get()

    -- Card container
    local card = makeFrame( parent, {
        Name = "ToggleCard",
        Size = UDim2.new( 1, 0, 0, 36 ),
        BackgroundColor3 = theme.Background_Card,
        BackgroundTransparency = theme.Transparency_Card,
        LayoutOrder = config.Order or 0,
    } )
    addCorner( card, theme.Corner_Medium )
    addPadding( card, UDim.new( 0, 12 ) )
    self._card = card
    self:_addInstance( card, "card" )

    -- Left: name (+ description)
    local nameLbl = makeLabel( card, {
        Name = "Name",
        Size = UDim2.new( 0, 200, 1, 0 ),
        Position = UDim2.new( 0, 12, 0, 0 ),
        Font = theme.Font_Body,
        TextColor3 = theme.Text_Secondary,
        TextSize = theme.Size_Body,
        Text = config.Name or "Toggle",
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        ClipsDescendants = false,
    } )
    self:_addInstance( nameLbl, "name" )

    if config.Description then
        nameLbl.Size = UDim2.new( 0, 200, 0, 14 )
        nameLbl.Position = UDim2.new( 0, 12, 0, 6 )
        nameLbl.TextYAlignment = Enum.TextYAlignment.Top
        local desc = makeLabel( card, {
            Name = "Description",
            Size = UDim2.new( 0, 200, 0, 14 ),
            Position = UDim2.new( 0, 12, 0, 20 ),
            Font = theme.Font_Caption,
            TextColor3 = theme.Text_Tertiary,
            TextSize = theme.Size_Caption,
            Text = config.Description,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
        } )
        self:_addInstance( desc, "desc" )
    end

    -- Optional keybind chip on the right of the toggle
    local rightAnchorX = -12
    if config.Keybind then
        local kbChip = makeButton( card, {
            Name = "KeybindChip",
            Size = UDim2.new( 0, 40, 0, 22 ),
            Position = UDim2.new( 1, -64, 0.5, -11 ),
            BackgroundColor3 = theme.Background_Input,
            BackgroundTransparency = 0,
            Text = "[" .. ( config.Keybind.Name or tostring( config.Keybind ) ):match( "%a+$" ) .. "]",
            Font = theme.Font_Mono,
            TextColor3 = theme.Text_Tertiary,
            TextSize = theme.Size_Caption,
            AutoButtonColor = false,
        } )
        addCorner( kbChip, theme.Corner_Small )
        self:_addInstance( kbChip, "keybindChip" )
        self._keybind = config.Keybind
        rightAnchorX = -64 - 8
    end

    -- Toggle switch ( right side )
    local switchWidth, switchHeight = 40, 22
    local switch = makeFrame( card, {
        Name = "Switch",
        Size = UDim2.new( 0, switchWidth, 0, switchHeight ),
        Position = UDim2.new( 1, rightAnchorX - switchWidth, 0.5, -switchHeight / 2 ),
        BackgroundColor3 = theme.Background_Input,
        BackgroundTransparency = 0,
        AnchorPoint = Vector2.new( 0, 0 ),
    } )
    addCorner( switch, UDim.new( 1, 0 ) )
    self._switch = switch
    self:_addInstance( switch, "switch" )

    local knobSize = 16
    local knob = makeFrame( switch, {
        Name = "Knob",
        Size = UDim2.new( 0, knobSize, 0, knobSize ),
        Position = UDim2.new( 0, 3, 0.5, -knobSize / 2 ),
        BackgroundColor3 = theme.Text_Tertiary,
        BackgroundTransparency = 0,
    } )
    addCorner( knob, UDim.new( 1, 0 ) )
    self:_addInstance( knob, "knob" )

    -- Click area ( whole card )
    local clickArea = makeButton( card, {
        Name = "ClickArea",
        Size = UDim2.new( 1, 0, 1, 0 ),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
    } )
    self:_addInstance( clickArea, "clickArea" )

    -- Hover
    local function onEnter()
        self:_trackTween( Animate( card, {
            BackgroundColor3 = theme.Background_CardHover,
        }, theme.Anim_Fast ) )
    end
    local function onLeave()
        self:_trackTween( Animate( card, {
            BackgroundColor3 = theme.Background_Card,
        }, theme.Anim_Fast ) )
    end
    self:_addConnection( clickArea.MouseEnter:Connect( onEnter ) )
    self:_addConnection( clickArea.MouseLeave:Connect( onLeave ) )

    -- Click
    self:_addConnection( clickArea.MouseButton1Click:Connect( function()
        if not self._enabled then return end
        self:SetValue( not self._value )
    end ) )

    -- Apply initial state
    self:_applyVisual( self._value, true )

    -- Keybind handler
    if config.Keybind then
        self:_addConnection( UserInputService.InputBegan:Connect( function( input, gp )
            if gp then return end
            if input.KeyCode == config.Keybind then
                self:SetValue( not self._value )
            end
        end ) )
    end

    -- Tooltip
    if config.Tooltip then self:SetTooltip( config.Tooltip ) end

    -- Theme change
    self:_addConnection( ThemeManager.changed():Connect( function( t )
        theme = t
        card.BackgroundColor3 = t.Background_Card
        nameLbl.TextColor3 = t.Text_Secondary
        switch.BackgroundColor3 = t.Background_Input
        if not self._value then
            knob.BackgroundColor3 = t.Text_Tertiary
        end
        self:_applyVisual( self._value, true )
    end ) )
end

function Toggle:_applyVisual( value: boolean, instant: boolean? )
    local theme = ThemeManager.get()
    local knob = self._knob
    local switch = self._switch
    if not knob or not switch then return end

    local knobX = value and ( 40 - 16 - 3 ) or 3
    local switchColor = value
        and theme.Accent_Primary
        or  theme.Background_Input
    local knobColor = value
        and theme.Text_OnAccent
        or  theme.Text_Tertiary

    if instant then
        knob.Position = UDim2.new( 0, knobX, 0.5, -8 )
        switch.BackgroundColor3 = switchColor
        knob.BackgroundColor3 = knobColor
    else
        self:_trackTween( Animate( knob, {
            Position = UDim2.new( 0, knobX, 0.5, -8 ),
        }, theme.Anim_Normal, Enum.EasingStyle.Back, Enum.EasingDirection.Out ) )
        self:_trackTween( Animate( switch, {
            BackgroundColor3 = switchColor,
        }, theme.Anim_Fast ) )
        self:_trackTween( Animate( knob, {
            BackgroundColor3 = knobColor,
        }, theme.Anim_Fast ) )
    end
end

function Toggle:SetValue( value: boolean )
    if self._destroyed then return end
    if typeof( value ) ~= "boolean" then
        error( "Toggle:SetValue expects boolean", 2 )
    end
    self._value = value
    self:_applyVisual( value, false )
    self:_signal( "Changed" ):Fire( value )
    if self._callback then
        local ok, err = pcall( self._callback, value )
        if not ok then warn( "[Ignite:Toggle] callback error: " .. tostring( err ) ) end
    end
end

function Toggle:GetValue(): boolean
    return self._value
end

function Toggle:SetEnabled( state: boolean )
    self._enabled = state
    local card = self._card
    if card then
        self:_trackTween( Animate( card, {
            BackgroundTransparency = state and 0 or ThemeManager.get().Transparency_Disabled,
        }, 0.15 ) )
    end
end

function Toggle:SetTooltip( text: string? )
    self._tooltipText = text
    -- Tooltip integration deferred to TooltipManager
    if text and self._card and TooltipManagerGlobal then
        TooltipManagerGlobal:Bind( self._card, text )
    end
end

--==============================================================
-- SECTION 11: SLIDER COMPONENT
--==============================================================

local Slider = setmetatable( {}, Component )
Slider.__index = Slider
Slider._type = "Slider"

function Slider.new( parent: Instance, config: any )
    local self = setmetatable( Component.new(), Slider )
    self._min = config.Min or 0
    self._max = config.Max or 100
    self._default = config.Default or self._min
    self._step = config.Step or 0
    self._decimals = config.Decimals or 0
    self._suffix = config.Suffix or ""
    self._prefix = config.Prefix or ""
    self._value = self._default
    self._flag = config.Flag
    self._callback = config.Callback
    self._dragging = false
    self:_build( parent, config )
    return self
end

function Slider:_build( parent: Instance, config: any )
    local theme = ThemeManager.get()

    local card = makeFrame( parent, {
        Name = "SliderCard",
        Size = UDim2.new( 1, 0, 0, 44 ),
        BackgroundColor3 = theme.Background_Card,
        BackgroundTransparency = theme.Transparency_Card,
        LayoutOrder = config.Order or 0,
    } )
    addCorner( card, theme.Corner_Medium )
    addPadding( card, UDim.new( 0, 12 ) )
    self._card = card
    self:_addInstance( card, "card" )

    -- Name + value
    local nameLbl = makeLabel( card, {
        Name = "Name",
        Size = UDim2.new( 0, 200, 0, 18 ),
        Position = UDim2.new( 0, 12, 0, 6 ),
        Font = theme.Font_Body,
        TextColor3 = theme.Text_Secondary,
        TextSize = theme.Size_Body,
        Text = config.Name or "Slider",
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
    } )
    self:_addInstance( nameLbl, "name" )

    local valueLbl = makeLabel( card, {
        Name = "Value",
        Size = UDim2.new( 0, 120, 0, 18 ),
        Position = UDim2.new( 1, -132, 0, 6 ),
        Font = theme.Font_Mono,
        TextColor3 = theme.Text_Primary,
        TextSize = theme.Size_BodySmall,
        Text = self:_formatValue( self._value ),
        TextXAlignment = Enum.TextXAlignment.Right,
        TextYAlignment = Enum.TextYAlignment.Center,
    } )
    self:_addInstance( valueLbl, "value" )

    -- Track + fill + thumb
    local trackY = 30
    local track = makeFrame( card, {
        Name = "Track",
        Size = UDim2.new( 1, -24, 0, 6 ),
        Position = UDim2.new( 0, 12, 0, trackY ),
        BackgroundColor3 = theme.Background_Input,
        BackgroundTransparency = 0,
    } )
    addCorner( track, UDim.new( 1, 0 ) )
    self:_addInstance( track, "track" )

    local fill = makeFrame( track, {
        Name = "Fill",
        Size = UDim2.new( self:_ratio( self._value ), 0, 1, 0 ),
        BackgroundColor3 = theme.Accent_Primary,
        BackgroundTransparency = 0,
    } )
    addCorner( fill, UDim.new( 1, 0 ) )
    addGradient( fill, ColorSequence.new( theme.Accent_GradientStart,
                                          theme.Accent_GradientEnd ), 0 )
    self:_addInstance( fill, "fill" )

    local thumb = makeFrame( track, {
        Name = "Thumb",
        Size = UDim2.new( 0, 14, 0, 14 ),
        Position = UDim2.new( self:_ratio( self._value ), -7, 0.5, -7 ),
        BackgroundColor3 = theme.Text_Primary,
        BackgroundTransparency = 0,
    } )
    addCorner( thumb, UDim.new( 1, 0 ) )
    self:_addInstance( thumb, "thumb" )

    -- Tooltip for current value ( shows while dragging )
    local dragTooltip = makeFrame( nil, {
        Name = "SliderTooltip",
        Size = UDim2.new( 0, 50, 0, 22 ),
        BackgroundColor3 = theme.Background_Window,
        BackgroundTransparency = 0,
        Visible = false,
    } )
    addCorner( dragTooltip, theme.Corner_Small )
    addStroke( dragTooltip, 1, theme.Border_Default, 0 )
    local ttLbl = makeLabel( dragTooltip, {
        Size = UDim2.new( 1, 0, 1, 0 ),
        Font = theme.Font_Mono,
        TextColor3 = theme.Text_Primary,
        TextSize = theme.Size_Caption,
        Text = "",
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
    } )
    self._dragTooltip = dragTooltip
    self._dragTooltipLabel = ttLbl
    self:_addInstance( dragTooltip, "dragTooltip" )

    -- Hover & drag handlers
    local function updateFromMouse( x: number )
        local trackPos = track.AbsolutePosition.X
        local trackSize = track.AbsoluteSize.X
        local rel = Utils.clamp( ( x - trackPos ) / trackSize, 0, 1 )
        local raw = self._min + rel * ( self._max - self._min )
        if self._step and self._step > 0 then
            raw = math.floor( ( raw - self._min ) / self._step + 0.5 ) * self._step + self._min
        end
        if self._decimals and self._decimals > 0 then
            raw = Utils.round( raw, self._decimals )
        else
            raw = math.floor( raw + 0.5 )
        end
        raw = Utils.clamp( raw, self._min, self._max )
        self:SetValue( raw )
    end

    local dragging = false
    self:_addConnection( UserInputService.InputBegan:Connect( function( input, gp )
        if gp then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1
           or input.UserInputType == Enum.UserInputType.Touch then
            local mousePos = UserInputService:GetMouseLocation()
            local guiInset = UserInputService:GetGuiInset()
            local x = mousePos.X
            local y = mousePos.Y - guiInset.Y
            -- Check if mouse is on track/thumb
            local tp = track.AbsolutePosition
            local ts = track.AbsoluteSize
            if x >= tp.X - 6 and x <= tp.X + ts.X + 6
               and y >= tp.Y - 6 and y <= tp.Y + ts.Y + 6 then
                dragging = true
                self._dragging = true
                dragTooltip.Parent = parent
                dragTooltip.Visible = true
                -- Scale thumb
                self:_trackTween( Animate( thumb, {
                    Size = UDim2.new( 0, 18, 0, 18 ),
                    Position = UDim2.new( self:_ratio( self._value ), -9, 0.5, -9 ),
                }, 0.1 ) )
                updateFromMouse( x )
            end
        end
    end ) )

    self:_addConnection( UserInputService.InputChanged:Connect( function( input )
        if dragging and ( input.UserInputType == Enum.UserInputType.MouseMovement
                       or input.UserInputType == Enum.UserInputType.Touch ) then
            local mousePos = UserInputService:GetMouseLocation()
            local guiInset = UserInputService:GetGuiInset()
            local x = mousePos.X
            updateFromMouse( x )
        end
    end ) )

    self:_addConnection( UserInputService.InputEnded:Connect( function( input )
        if input.UserInputType == Enum.UserInputType.MouseButton1
           or input.UserInputType == Enum.UserInputType.Touch then
            if dragging then
                dragging = false
                self._dragging = false
                dragTooltip.Visible = false
                dragTooltip.Parent = nil
                self:_trackTween( Animate( thumb, {
                    Size = UDim2.new( 0, 14, 0, 14 ),
                    Position = UDim2.new( self:_ratio( self._value ), -7, 0.5, -7 ),
                }, 0.1 ) )
            end
        end
    end ) )

    -- Hover
    local function onEnter()
        self:_trackTween( Animate( card, {
            BackgroundColor3 = theme.Background_CardHover,
        }, theme.Anim_Fast ) )
    end
    local function onLeave()
        self:_trackTween( Animate( card, {
            BackgroundColor3 = theme.Background_Card,
        }, theme.Anim_Fast ) )
    end
    self:_addConnection( track.MouseEnter:Connect( onEnter ) )
    self:_addConnection( track.MouseLeave:Connect( onLeave ) )

    if config.Tooltip then self:SetTooltip( config.Tooltip ) end

    -- Theme change
    self:_addConnection( ThemeManager.changed():Connect( function( t )
        theme = t
        card.BackgroundColor3 = t.Background_Card
        nameLbl.TextColor3 = t.Text_Secondary
        track.BackgroundColor3 = t.Background_Input
        fill.BackgroundColor3 = t.Accent_Primary
        thumb.BackgroundColor3 = t.Text_Primary
    end ) )
end

function Slider:_ratio( v: number ): number
    if self._max == self._min then return 0 end
    return Utils.clamp( ( v - self._min ) / ( self._max - self._min ), 0, 1 )
end

function Slider:_formatValue( v: number ): string
    local s
    if self._decimals and self._decimals > 0 then
        s = string.format( "%." .. self._decimals .. "f", v )
    else
        s = tostring( math.floor( v + 0.5 ) )
    end
    return self._prefix .. s .. self._suffix
end

function Slider:SetValue( v: number )
    if self._destroyed then return end
    if typeof( v ) ~= "number" then error( "Slider:SetValue expects number", 2 ) end
    v = Utils.clamp( v, self._min, self._max )
    if self._step and self._step > 0 then
        v = math.floor( ( v - self._min ) / self._step + 0.5 ) * self._step + self._min
    end
    self._value = v
    if self._valueLbl then
        self._valueLbl.Text = self:_formatValue( v )
    end
    if self._fill and self._thumb then
        local r = self:_ratio( v )
        self:_trackTween( Animate( self._fill, {
            Size = UDim2.new( r, 0, 1, 0 ),
        }, 0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out ) )
        self:_trackTween( Animate( self._thumb, {
            Position = UDim2.new( r, -7, 0.5, -7 ),
        }, 0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out ) )
    end
    if self._dragTooltipLabel and self._dragging then
        self._dragTooltipLabel.Text = self:_formatValue( v )
        if self._thumb then
            local abs = self._thumb.AbsolutePosition
            local sz = self._thumb.AbsoluteSize
            self._dragTooltip.Position = UDim2.new( 0, abs.X + sz.X / 2 - 25,
                                                    0, abs.Y - 28 )
        end
    end
    self:_signal( "Changed" ):Fire( v )
    if self._callback then
        local ok, err = pcall( self._callback, v )
        if not ok then warn( "[Ignite:Slider] callback error: " .. tostring( err ) ) end
    end
end

function Slider:GetValue(): number
    return self._value
end

function Slider:SetEnabled( state: boolean )
    self._enabled = state
    if self._card then
        self:_trackTween( Animate( self._card, {
            BackgroundTransparency = state and 0
                or ThemeManager.get().Transparency_Disabled,
        }, 0.15 ) )
    end
end

--==============================================================
-- SECTION 12: DROPDOWN COMPONENT
--==============================================================

local Dropdown = setmetatable( {}, Component )
Dropdown.__index = Dropdown
Dropdown._type = "Dropdown"

function Dropdown.new( parent: Instance, config: any )
    local self = setmetatable( Component.new(), Dropdown )
    self._options = config.Options or {}
    self._default = config.Default
    self._multi = config.Multi == true
    self._searchable = config.Searchable == true
    self._value = config.Default
    self._flag = config.Flag
    self._callback = config.Callback
    self._open = false
    self:_build( parent, config )
    return self
end

function Dropdown:_build( parent: Instance, config: any )
    local theme = ThemeManager.get()

    local card = makeFrame( parent, {
        Name = "DropdownCard",
        Size = UDim2.new( 1, 0, 0, 44 ),
        BackgroundColor3 = theme.Background_Card,
        BackgroundTransparency = theme.Transparency_Card,
        LayoutOrder = config.Order or 0,
    } )
    addCorner( card, theme.Corner_Medium )
    addPadding( card, UDim.new( 0, 12 ) )
    self._card = card
    self._parent = parent
    self:_addInstance( card, "card" )

    local nameLbl = makeLabel( card, {
        Name = "Name",
        Size = UDim2.new( 0, 200, 0, 18 ),
        Position = UDim2.new( 0, 12, 0, 6 ),
        Font = theme.Font_Body,
        TextColor3 = theme.Text_Secondary,
        TextSize = theme.Size_Body,
        Text = config.Name or "Dropdown",
        TextXAlignment = Enum.TextXAlignment.Left,
    } )
    self:_addInstance( nameLbl, "name" )

    -- Right side: chevron + value
    local chevron = makeLabel( card, {
        Name = "Chevron",
        Size = UDim2.new( 0, 16, 0, 16 ),
        Position = UDim2.new( 1, -28, 0.5, -8 ),
        Font = theme.Font_Main,
        TextColor3 = theme.Text_Tertiary,
        TextSize = 12,
        Text = getIcon( "chevron_down" ),
        TextXAlignment = Enum.TextXAlignment.Right,
    } )
    self:_addInstance( chevron, "chevron" )

    local valueLbl = makeLabel( card, {
        Name = "Value",
        Size = UDim2.new( 0, 160, 0, 18 ),
        Position = UDim2.new( 1, -178, 0, 6 ),
        Font = theme.Font_Mono,
        TextColor3 = theme.Text_Primary,
        TextSize = theme.Size_BodySmall,
        Text = self:_formatValue( self._value ),
        TextXAlignment = Enum.TextXAlignment.Right,
        TextTruncate = Enum.TextTruncate.AtEnd,
    } )
    self:_addInstance( valueLbl, "value" )

    -- Click area
    local clickArea = makeButton( card, {
        Name = "ClickArea",
        Size = UDim2.new( 1, 0, 1, 0 ),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
    } )
    self:_addInstance( clickArea, "clickArea" )

    -- Popover ( created on demand, parented to Library._popoverGui )
    self._popover = nil

    local function openPopover()
        if self._open then return end
        self._open = true
        self:_trackTween( Animate( chevron, {
            Rotation = 180,
        }, theme.Anim_Fast ) )
        self:_buildPopover()
    end

    local function closePopover()
        if not self._open then return end
        self._open = false
        self:_trackTween( Animate( chevron, {
            Rotation = 0,
        }, theme.Anim_Fast ) )
        if self._popover then
            self:_trackTween( Animate( self._popover, {
                BackgroundTransparency = 1,
                Position = UDim2.new( 0, self._popover.Position.X.Offset, 0,
                                      self._popover.Position.Y.Offset + 6 ),
            }, theme.Anim_Fast ) )
            task.delay( theme.Anim_Fast, function()
                if self._popover then
                    self._popover:Destroy()
                    self._popover = nil
                end
            end )
        end
    end

    self._closePopover = closePopover

    self:_addConnection( clickArea.MouseButton1Click:Connect( function()
        if not self._enabled then return end
        if self._open then closePopover() else openPopover() end
    end ) )

    -- Hover
    self:_addConnection( clickArea.MouseEnter:Connect( function()
        self:_trackTween( Animate( card, {
            BackgroundColor3 = theme.Background_CardHover,
        }, theme.Anim_Fast ) )
    end ) )
    self:_addConnection( clickArea.MouseLeave:Connect( function()
        self:_trackTween( Animate( card, {
            BackgroundColor3 = theme.Background_Card,
        }, theme.Anim_Fast ) )
    end ) )

    -- Click outside closes popover
    self:_addConnection( UserInputService.InputBegan:Connect( function( input, gp )
        if not self._open then return end
        if gp then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            local mp = UserInputService:GetMouseLocation()
            local inset = UserInputService:GetGuiInset()
            local mx, my = mp.X, mp.Y - inset.Y
            local cp = self._card.AbsolutePosition
            local cs = self._card.AbsoluteSize
            local onCard = mx >= cp.X and mx <= cp.X + cs.X
                        and my >= cp.Y and my <= cp.Y + cs.Y
            local onPopover = false
            if self._popover then
                local pp = self._popover.AbsolutePosition
                local ps = self._popover.AbsoluteSize
                onPopover = mx >= pp.X and mx <= pp.X + ps.X
                         and my >= pp.Y and my <= pp.Y + ps.Y
            end
            if not onCard and not onPopover then
                closePopover()
            end
        end
    end ) )

    if config.Tooltip then self:SetTooltip( config.Tooltip ) end

    -- Theme change
    self:_addConnection( ThemeManager.changed():Connect( function( t )
        theme = t
        card.BackgroundColor3 = t.Background_Card
        nameLbl.TextColor3 = t.Text_Secondary
        valueLbl.TextColor3 = t.Text_Primary
        chevron.TextColor3 = t.Text_Tertiary
    end ) )
end

function Dropdown:_buildPopover()
    if self._popover then self._popover:Destroy() end
    local theme = ThemeManager.get()
    local popoverGui = Library._popoverGui
    if not popoverGui then return end

    local popover = makeFrame( popoverGui, {
        Name = "DropdownPopover",
        Size = UDim2.new( 0, self._card.AbsoluteSize.X - 24, 0, 0 ),
        Position = UDim2.new( 0, self._card.AbsolutePosition.X + 12,
                              0, self._card.AbsolutePosition.Y
                                 + self._card.AbsoluteSize.Y ),
        BackgroundColor3 = theme.Background_Card,
        BackgroundTransparency = theme.Transparency_Popover,
        ClipsDescendants = true,
        ZIndex = 50,
    } )
    addCorner( popover, theme.Corner_Medium )
    addStroke( popover, 1, theme.Border_Default, 0 )

    -- Search box ( if searchable )
    local listY = 0
    if self._searchable then
        local searchBox = Instance.new( "TextBox" )
        searchBox.Size = UDim2.new( 1, 0, 0, 30 )
        searchBox.Position = UDim2.new( 0, 0, 0, 0 )
        searchBox.BackgroundColor3 = theme.Background_Input
        searchBox.BackgroundTransparency = 0
        searchBox.BorderSizePixel = 0
        searchBox.Font = theme.Font_Body
        searchBox.TextColor3 = theme.Text_Primary
        searchBox.PlaceholderColor3 = theme.Text_Tertiary
        searchBox.PlaceholderText = "Search..."
        searchBox.Text = ""
        searchBox.TextSize = theme.Size_BodySmall
        searchBox.TextXAlignment = Enum.TextXAlignment.Left
        searchBox.Parent = popover
        local pad = Instance.new( "UIPadding" )
        pad.PaddingLeft = UDim.new( 0, 10 )
        pad.Parent = searchBox
        self._searchBox = searchBox
        listY = 30
        self:_addConnection( searchBox:GetPropertyChangedSignal( "Text" ):Connect( function()
            self:_filterList( searchBox.Text )
        end ) )
    end

    -- Items list
    local list = makeScroll( popover, {
        Name = "ItemList",
        Size = UDim2.new( 1, 0, 1, -listY ),
        Position = UDim2.new( 0, 0, 0, listY ),
        BackgroundTransparency = 1,
        CanvasSize = UDim2.new( 0, 0, 0, 0 ),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 4,
    } )
    addList( list, Enum.FillDirection.Vertical, UDim.new( 0, 0 ),
             Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top )
    self._itemList = list

    self._popover = popover
    self:_addInstance( popover, "popover" )

    self:_populateList( self._options )

    -- Animate open
    local targetHeight = Utils.clamp( #self._options * 28 + listY + 8, 0, 240 )
    popover.Size = UDim2.new( 0, self._card.AbsoluteSize.X - 24, 0, 0 )
    popover.BackgroundTransparency = 1
    self:_trackTween( Animate( popover, {
        Size = UDim2.new( 0, self._card.AbsoluteSize.X - 24, 0, targetHeight ),
        BackgroundTransparency = theme.Transparency_Popover,
    }, theme.Anim_Normal, Enum.EasingStyle.Quart, Enum.EasingDirection.Out ) )
end

function Dropdown:_populateList( options: any, filter: string? )
    if not self._itemList then return end
    -- Clear existing
    for _, c in ipairs( self._itemList:GetChildren() ) do
        if c:IsA( "GuiObject" ) then c:Destroy() end
    end
    local theme = ThemeManager.get()
    filter = filter and string.lower( filter ) or nil
    local visible = 0
    for _, opt in ipairs( options ) do
        if not filter or string.find( string.lower( tostring( opt ) ), filter, 1, true ) then
            visible = visible + 1
            local item = makeButton( self._itemList, {
                Name = "Item_" .. tostring( opt ),
                Size = UDim2.new( 1, 0, 0, 28 ),
                BackgroundColor3 = theme.Background_Card,
                BackgroundTransparency = 1,
                Text = "",
                AutoButtonColor = false,
                LayoutOrder = visible,
            } )
            local lbl = makeLabel( item, {
                Size = UDim2.new( 1, -20, 1, 0 ),
                Position = UDim2.new( 0, 10, 0, 0 ),
                Font = theme.Font_Body,
                TextColor3 = theme.Text_Secondary,
                TextSize = theme.Size_BodySmall,
                Text = tostring( opt ),
                TextXAlignment = Enum.TextXAlignment.Left,
            } )
            local sel = false
            if self._multi and typeof( self._value ) == "table" then
                for _, v in ipairs( self._value ) do
                    if v == opt then sel = true break end
                end
            else
                sel = ( self._value == opt )
            end
            if sel then
                lbl.TextColor3 = theme.Accent_Primary
                lbl.Font = theme.Font_Heading
            end
            self:_addConnection( item.MouseEnter:Connect( function()
                self:_trackTween( Animate( item, {
                    BackgroundColor3 = theme.Background_CardHover,
                    BackgroundTransparency = 0,
                }, theme.Anim_Fast ) )
            end ) )
            self:_addConnection( item.MouseLeave:Connect( function()
                self:_trackTween( Animate( item, {
                    BackgroundTransparency = 1,
                }, theme.Anim_Fast ) )
            end ) )
            self:_addConnection( item.MouseButton1Click:Connect( function()
                self:_selectOption( opt )
            end ) )
        end
    end
    if visible == 0 then
        local empty = makeLabel( self._itemList, {
            Size = UDim2.new( 1, 0, 0, 28 ),
            Font = theme.Font_Body,
            TextColor3 = theme.Text_Tertiary,
            TextSize = theme.Size_BodySmall,
            Text = "No options",
            TextXAlignment = Enum.TextXAlignment.Center,
        } )
    end
end

function Dropdown:_filterList( text: string )
    self:_populateList( self._options, text )
end

function Dropdown:_selectOption( opt )
    if self._multi then
        if typeof( self._value ) ~= "table" then self._value = {} end
        local idx
        for i, v in ipairs( self._value ) do
            if v == opt then idx = i break end
        end
        if idx then
            table.remove( self._value, idx )
        else
            table.insert( self._value, opt )
        end
    else
        self._value = opt
        if self._closePopover then self._closePopover() end
    end
    if self._valueLbl then
        self._valueLbl.Text = self:_formatValue( self._value )
    end
    self:_signal( "Changed" ):Fire( self._value )
    if self._callback then
        local ok, err = pcall( self._callback, self._value )
        if not ok then warn( "[Ignite:Dropdown] callback error: " .. tostring( err ) ) end
    end
    if self._itemList then
        self:_populateList( self._options,
            self._searchBox and self._searchBox.Text or nil )
    end
end

function Dropdown:_formatValue( v ): string
    if v == nil then return "None" end
    if self._multi then
        if typeof( v ) == "table" then
            if #v == 0 then return "None" end
            return table.concat( v, ", " )
        end
        return tostring( v )
    end
    return tostring( v )
end

function Dropdown:SetValue( v )
    if self._destroyed then return end
    self._value = v
    if self._valueLbl then
        self._valueLbl.Text = self:_formatValue( v )
    end
    self:_signal( "Changed" ):Fire( v )
    if self._callback then
        local ok, err = pcall( self._callback, v )
        if not ok then warn( "[Ignite:Dropdown] callback error: " .. tostring( err ) ) end
    end
    if self._itemList then
        self:_populateList( self._options )
    end
end

function Dropdown:GetValue()
    return self._value
end

function Dropdown:Refresh( options: any )
    self._options = options
    if self._itemList then
        self:_populateList( options )
    end
end

--==============================================================
-- SECTION 13: KEYBIND COMPONENT
--==============================================================

local Keybind = setmetatable( {}, Component )
Keybind.__index = Keybind
Keybind._type = "Keybind"

function Keybind.new( parent: Instance, config: any )
    local self = setmetatable( Component.new(), Keybind )
    self._key = config.Default
    self._mode = config.Mode or "Toggle"
    self._allowedTypes = config.AllowedTypes or { "Keyboard", "Mouse" }
    self._flag = config.Flag
    self._callback = config.Callback
    self._picking = false
    self._active = false
    self:_build( parent, config )
    return self
end

function Keybind:_build( parent: Instance, config: any )
    local theme = ThemeManager.get()

    local card = makeFrame( parent, {
        Name = "KeybindCard",
        Size = UDim2.new( 1, 0, 0, 36 ),
        BackgroundColor3 = theme.Background_Card,
        BackgroundTransparency = theme.Transparency_Card,
        LayoutOrder = config.Order or 0,
    } )
    addCorner( card, theme.Corner_Medium )
    addPadding( card, UDim.new( 0, 12 ) )
    self._card = card
    self:_addInstance( card, "card" )

    local nameLbl = makeLabel( card, {
        Name = "Name",
        Size = UDim2.new( 0, 200, 1, 0 ),
        Position = UDim2.new( 0, 12, 0, 0 ),
        Font = theme.Font_Body,
        TextColor3 = theme.Text_Secondary,
        TextSize = theme.Size_Body,
        Text = config.Name or "Keybind",
        TextXAlignment = Enum.TextXAlignment.Left,
    } )
    self:_addInstance( nameLbl, "name" )

    -- Key chip
    local keyChip = makeButton( card, {
        Name = "KeyChip",
        Size = UDim2.new( 0, 60, 0, 22 ),
        Position = UDim2.new( 1, -72, 0.5, -11 ),
        BackgroundColor3 = theme.Background_Input,
        BackgroundTransparency = 0,
        Text = self:_formatKey( self._key ),
        Font = theme.Font_Mono,
        TextColor3 = theme.Text_Primary,
        TextSize = theme.Size_Caption,
        AutoButtonColor = false,
    } )
    addCorner( keyChip, theme.Corner_Small )
    self:_addInstance( keyChip, "keyChip" )

    -- Mode chip
    local modeChip = makeButton( card, {
        Name = "ModeChip",
        Size = UDim2.new( 0, 60, 0, 22 ),
        Position = UDim2.new( 1, -138, 0.5, -11 ),
        BackgroundColor3 = theme.Background_Input,
        BackgroundTransparency = 0,
        Text = "[" .. self._mode .. "]",
        Font = theme.Font_Mono,
        TextColor3 = theme.Text_Tertiary,
        TextSize = theme.Size_Caption,
        AutoButtonColor = false,
    } )
    addCorner( modeChip, theme.Corner_Small )
    self:_addInstance( modeChip, "modeChip" )

    -- Click key chip -> enter pick mode
    self:_addConnection( keyChip.MouseButton1Click:Connect( function()
        if not self._enabled then return end
        self._picking = true
        keyChip.Text = "[...]"
        self:_trackTween( Animate( keyChip, {
            BackgroundColor3 = theme.Accent_Primary,
            TextColor3 = theme.Text_OnAccent,
        }, theme.Anim_Fast ) )
    end ) )

    -- Click mode chip -> cycle mode
    self:_addConnection( modeChip.MouseButton1Click:Connect( function()
        if not self._enabled then return end
        local modes = { "Toggle", "Hold", "Always" }
        local idx = 1
        for i, m in ipairs( modes ) do
            if m == self._mode then idx = i break end
        end
        idx = idx % #modes + 1
        self._mode = modes[ idx ]
        modeChip.Text = "[" .. self._mode .. "]"
    end ) )

    -- Input handlers
    self:_addConnection( UserInputService.InputBegan:Connect( function( input, gp )
        if gp then return end
        if self._picking then
            -- Accept any input as the new bind
            if input.UserInputType == Enum.UserInputType.Keyboard
               or input.UserInputType == Enum.UserInputType.MouseButton1
               or input.UserInputType == Enum.UserInputType.MouseButton2
               or input.UserInputType == Enum.UserInputType.MouseButton3
               or input.UserInputType == Enum.UserInputType.Gamepad1 then
                self._picking = false
                self._key = input.KeyCode
                keyChip.Text = self:_formatKey( self._key )
                self:_trackTween( Animate( keyChip, {
                    BackgroundColor3 = theme.Background_Input,
                    TextColor3 = theme.Text_Primary,
                }, theme.Anim_Fast ) )
                return
            end
        end
        if self._key and input.KeyCode == self._key then
            if self._mode == "Toggle" then
                self._active = not self._active
                self:_fireCallback( self._key, self._mode, self._active )
            elseif self._mode == "Hold" then
                self._active = true
                self:_fireCallback( self._key, self._mode, true )
            elseif self._mode == "Always" then
                self._active = true
                self:_fireCallback( self._key, self._mode, true )
            end
        end
    end ) )

    self:_addConnection( UserInputService.InputEnded:Connect( function( input )
        if self._key and input.KeyCode == self._key then
            if self._mode == "Hold" then
                self._active = false
                self:_fireCallback( self._key, self._mode, false )
            end
        end
    end ) )

    -- Hover
    self:_addConnection( keyChip.MouseEnter:Connect( function()
        if not self._picking then
            self:_trackTween( Animate( keyChip, {
                BackgroundColor3 = theme.Background_CardHover,
            }, theme.Anim_Fast ) )
        end
    end ) )
    self:_addConnection( keyChip.MouseLeave:Connect( function()
        if not self._picking then
            self:_trackTween( Animate( keyChip, {
                BackgroundColor3 = theme.Background_Input,
            }, theme.Anim_Fast ) )
        end
    end ) )

    if config.Tooltip then self:SetTooltip( config.Tooltip ) end

    -- Register with KeybindListManager
    if KeybindListManagerGlobal then
        KeybindListManagerGlobal:Register( self, config.Name or "Keybind" )
    end

    -- Theme change
    self:_addConnection( ThemeManager.changed():Connect( function( t )
        theme = t
        card.BackgroundColor3 = t.Background_Card
        nameLbl.TextColor3 = t.Text_Secondary
        if not self._picking then
            keyChip.BackgroundColor3 = t.Background_Input
            keyChip.TextColor3 = t.Text_Primary
        end
        modeChip.BackgroundColor3 = t.Background_Input
        modeChip.TextColor3 = t.Text_Tertiary
    end ) )
end

function Keybind:_formatKey( key: Enum.KeyCode? ): string
    if not key then return "None" end
    local name = tostring( key ):gsub( "Enum.KeyCode.", "" )
    return name
end

function Keybind:_fireCallback( key: Enum.KeyCode, mode: string, active: boolean )
    self:_signal( "Changed" ):Fire( key, mode, active )
    if self._callback then
        local ok, err = pcall( self._callback, key, mode )
        if not ok then warn( "[Ignite:Keybind] callback error: " .. tostring( err ) ) end
    end
end

function Keybind:SetMode( mode: string )
    assert( mode == "Toggle" or mode == "Hold" or mode == "Always",
            "Keybind:SetMode expects Toggle/Hold/Always" )
    self._mode = mode
    if self._modeChip then
        self._modeChip.Text = "[" .. mode .. "]"
    end
end

function Keybind:SetValue( key: Enum.KeyCode )
    self._key = key
    if self._keyChip then
        self._keyChip.Text = self:_formatKey( key )
    end
    self:_signal( "Changed" ):Fire( key, self._mode, self._active )
end

function Keybind:GetValue()
    return self._key, self._mode, self._active
end

--==============================================================
-- SECTION 14: COLORPICKER COMPONENT
--==============================================================

local ColorPicker = setmetatable( {}, Component )
ColorPicker.__index = ColorPicker
ColorPicker._type = "ColorPicker"

function ColorPicker.new( parent: Instance, config: any )
    local self = setmetatable( Component.new(), ColorPicker )
    self._value = config.Default or Color3.fromRGB( 255, 102, 0 )
    self._alpha = config.Alpha == true and 1 or nil
    self._flag = config.Flag
    self._callback = config.Callback
    self._open = false
    self._h, self._s, self._v = self._value:ToHSV()
    self:_build( parent, config )
    return self
end

function ColorPicker:_build( parent: Instance, config: any )
    local theme = ThemeManager.get()

    local card = makeFrame( parent, {
        Name = "ColorPickerCard",
        Size = UDim2.new( 1, 0, 0, 36 ),
        BackgroundColor3 = theme.Background_Card,
        BackgroundTransparency = theme.Transparency_Card,
        LayoutOrder = config.Order or 0,
    } )
    addCorner( card, theme.Corner_Medium )
    addPadding( card, UDim.new( 0, 12 ) )
    self._card = card
    self._parent = parent
    self:_addInstance( card, "card" )

    local nameLbl = makeLabel( card, {
        Name = "Name",
        Size = UDim2.new( 0, 200, 1, 0 ),
        Position = UDim2.new( 0, 12, 0, 0 ),
        Font = theme.Font_Body,
        TextColor3 = theme.Text_Secondary,
        TextSize = theme.Size_Body,
        Text = config.Name or "Color",
        TextXAlignment = Enum.TextXAlignment.Left,
    } )
    self:_addInstance( nameLbl, "name" )

    -- Swatch ( right side )
    local swatch = makeFrame( card, {
        Name = "Swatch",
        Size = UDim2.new( 0, 40, 0, 22 ),
        Position = UDim2.new( 1, -52, 0.5, -11 ),
        BackgroundColor3 = self._value,
        BackgroundTransparency = 0,
    } )
    addCorner( swatch, theme.Corner_Small )
    addStroke( swatch, 1, theme.Border_Default, 0 )
    self:_addInstance( swatch, "swatch" )

    local clickArea = makeButton( card, {
        Name = "ClickArea",
        Size = UDim2.new( 1, 0, 1, 0 ),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
    } )
    self:_addInstance( clickArea, "clickArea" )

    local function openPopover()
        if self._open then return end
        self._open = true
        self:_buildPopover()
    end
    local function closePopover()
        if not self._open then return end
        self._open = false
        if self._popover then
            self:_trackTween( Animate( self._popover, {
                BackgroundTransparency = 1,
            }, theme.Anim_Fast ) )
            task.delay( theme.Anim_Fast, function()
                if self._popover then
                    self._popover:Destroy()
                    self._popover = nil
                end
            end )
        end
    end
    self._closePopover = closePopover

    self:_addConnection( clickArea.MouseButton1Click:Connect( function()
        if not self._enabled then return end
        if self._open then closePopover() else openPopover() end
    end ) )

    self:_addConnection( clickArea.MouseEnter:Connect( function()
        self:_trackTween( Animate( card, {
            BackgroundColor3 = theme.Background_CardHover,
        }, theme.Anim_Fast ) )
    end ) )
    self:_addConnection( clickArea.MouseLeave:Connect( function()
        self:_trackTween( Animate( card, {
            BackgroundColor3 = theme.Background_Card,
        }, theme.Anim_Fast ) )
    end ) )

    self:_addConnection( UserInputService.InputBegan:Connect( function( input, gp )
        if not self._open then return end
        if gp then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            local mp = UserInputService:GetMouseLocation()
            local inset = UserInputService:GetGuiInset()
            local mx, my = mp.X, mp.Y - inset.Y
            local cp = self._card.AbsolutePosition
            local cs = self._card.AbsoluteSize
            local onCard = mx >= cp.X and mx <= cp.X + cs.X
                        and my >= cp.Y and my <= cp.Y + cs.Y
            local onPopover = false
            if self._popover then
                local pp = self._popover.AbsolutePosition
                local ps = self._popover.AbsoluteSize
                onPopover = mx >= pp.X and mx <= pp.X + ps.X
                         and my >= pp.Y and my <= pp.Y + ps.Y
            end
            if not onCard and not onPopover then
                closePopover()
            end
        end
    end ) )

    if config.Tooltip then self:SetTooltip( config.Tooltip ) end

    self:_addConnection( ThemeManager.changed():Connect( function( t )
        theme = t
        card.BackgroundColor3 = t.Background_Card
        nameLbl.TextColor3 = t.Text_Secondary
    end ) )
end

function ColorPicker:_buildPopover()
    if self._popover then self._popover:Destroy() end
    local theme = ThemeManager.get()
    local popoverGui = Library._popoverGui
    if not popoverGui then return end

    local popover = makeFrame( popoverGui, {
        Name = "ColorPickerPopover",
        Size = UDim2.new( 0, 220, 0, 220 ),
        Position = UDim2.new( 0, self._card.AbsolutePosition.X + 12,
                              0, self._card.AbsolutePosition.Y
                                 + self._card.AbsoluteSize.Y ),
        BackgroundColor3 = theme.Background_Card,
        BackgroundTransparency = theme.Transparency_Popover,
        ZIndex = 50,
    } )
    addCorner( popover, theme.Corner_Medium )
    addStroke( popover, 1, theme.Border_Default, 0 )
    self._popover = popover
    self:_addInstance( popover, "popover" )

    -- SV picker ( 200x140 )
    local sv = makeFrame( popover, {
        Name = "SVPicker",
        Size = UDim2.new( 0, 196, 0, 140 ),
        Position = UDim2.new( 0, 12, 0, 12 ),
        BackgroundColor3 = Color3.fromHSV( self._h, 1, 1 ),
        BackgroundTransparency = 0,
        ClipsDescendants = true,
    } )
    -- White-to-transparent ( horizontal )
    local whiteGrad = Instance.new( "UIGradient" )
    whiteGrad.Color = ColorSequence.new( Color3.fromRGB( 255, 255, 255 ),
                                         Color3.fromRGB( 0, 0, 0 ) )
    whiteGrad.Rotation = 0
    whiteGrad.Parent = sv
    -- Black-to-transparent ( vertical )
    local blackOverlay = makeFrame( sv, {
        Size = UDim2.new( 1, 0, 1, 0 ),
        BackgroundColor3 = Color3.fromRGB( 0, 0, 0 ),
        BackgroundTransparency = 1,
    } )
    local blackGrad = Instance.new( "UIGradient" )
    blackGrad.Color = ColorSequence.new( Color3.fromRGB( 0, 0, 0 ),
                                         Color3.fromRGB( 255, 255, 255 ) )
    blackGrad.Rotation = 90
    blackGrad.Parent = blackOverlay
    local svThumb = makeFrame( sv, {
        Name = "SVThumb",
        Size = UDim2.new( 0, 8, 0, 8 ),
        Position = UDim2.new( self._s, -4, 1 - self._v, -4 ),
        BackgroundColor3 = Color3.fromRGB( 255, 255, 255 ),
        BackgroundTransparency = 0,
    } )
    addCorner( svThumb, UDim.new( 1, 0 ) )
    addStroke( svThumb, 1, Color3.fromRGB( 0, 0, 0 ), 0 )
    self._sv = sv
    self._svThumb = svThumb

    -- Hue slider ( 196x12 )
    local hue = makeFrame( popover, {
        Name = "HueSlider",
        Size = UDim2.new( 0, 196, 0, 12 ),
        Position = UDim2.new( 0, 12, 0, 162 ),
        BackgroundColor3 = Color3.fromRGB( 255, 255, 255 ),
        BackgroundTransparency = 0,
    } )
    local hueGrad = Instance.new( "UIGradient" )
    hueGrad.Color = ColorSequence.new(
        Color3.fromRGB( 255, 0, 0 ),
        Color3.fromRGB( 255, 255, 0 ),
        Color3.fromRGB( 0, 255, 0 ),
        Color3.fromRGB( 0, 255, 255 ),
        Color3.fromRGB( 0, 0, 255 ),
        Color3.fromRGB( 255, 0, 255 ),
        Color3.fromRGB( 255, 0, 0 )
    )
    hueGrad.Parent = hue
    local hueThumb = makeFrame( hue, {
        Name = "HueThumb",
        Size = UDim2.new( 0, 4, 0, 16 ),
        Position = UDim2.new( self._h, -2, 0.5, -8 ),
        BackgroundColor3 = Color3.fromRGB( 255, 255, 255 ),
        BackgroundTransparency = 0,
    } )
    addCorner( hueThumb, UDim.new( 1, 0 ) )
    addStroke( hueThumb, 1, Color3.fromRGB( 0, 0, 0 ), 0 )
    self._hue = hue
    self._hueThumb = hueThumb

    -- Hex input
    local hexBox = Instance.new( "TextBox" )
    hexBox.Size = UDim2.new( 0, 80, 0, 22 )
    hexBox.Position = UDim2.new( 0, 12, 0, 184 )
    hexBox.BackgroundColor3 = theme.Background_Input
    hexBox.BackgroundTransparency = 0
    hexBox.BorderSizePixel = 0
    hexBox.Font = theme.Font_Mono
    hexBox.TextColor3 = theme.Text_Primary
    hexBox.TextSize = theme.Size_Caption
    hexBox.Text = "#" .. Utils.colorToHex( self._value )
    hexBox.PlaceholderText = "#RRGGBB"
    hexBox.ClearTextOnFocus = false
    hexBox.Parent = popover
    addCorner( hexBox, theme.Corner_Small )
    self._hexBox = hexBox
    self:_addConnection( hexBox.FocusLost:Connect( function()
        local text = hexBox.Text:gsub( "#", "" )
        if #text == 6 then
            local c = Utils.hexToColor( text )
            self._h, self._s, self._v = c:ToHSV()
            self:_updateColor( c, true )
        else
            hexBox.Text = "#" .. Utils.colorToHex( self._value )
        end
    end ) )

    -- Drag handlers
    local svDragging = false
    self:_addConnection( UserInputService.InputBegan:Connect( function( input, gp )
        if gp then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            local mp = UserInputService:GetMouseLocation()
            local inset = UserInputService:GetGuiInset()
            local mx, my = mp.X, mp.Y - inset.Y
            local sp = sv.AbsolutePosition
            local ss = sv.AbsoluteSize
            if mx >= sp.X and mx <= sp.X + ss.X
               and my >= sp.Y and my <= sp.Y + ss.Y then
                svDragging = true
                self:_updateSV( mx, my )
            end
        end
    end ) )
    self:_addConnection( UserInputService.InputChanged:Connect( function( input )
        if svDragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local mp = UserInputService:GetMouseLocation()
            local inset = UserInputService:GetGuiInset()
            self:_updateSV( mp.X, mp.Y - inset.Y )
        end
    end ) )
    self:_addConnection( UserInputService.InputEnded:Connect( function( input )
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            svDragging = false
        end
    end ) )

    local hueDragging = false
    self:_addConnection( UserInputService.InputBegan:Connect( function( input, gp )
        if gp then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            local mp = UserInputService:GetMouseLocation()
            local inset = UserInputService:GetGuiInset()
            local mx, my = mp.X, mp.Y - inset.Y
            local hp = hue.AbsolutePosition
            local hs = hue.AbsoluteSize
            if mx >= hp.X and mx <= hp.X + hs.X
               and my >= hp.Y - 4 and my <= hp.Y + hs.Y + 4 then
                hueDragging = true
                self:_updateHue( mx )
            end
        end
    end ) )
    self:_addConnection( UserInputService.InputChanged:Connect( function( input )
        if hueDragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local mp = UserInputService:GetMouseLocation()
            self:_updateHue( mp.X )
        end
    end ) )
    self:_addConnection( UserInputService.InputEnded:Connect( function( input )
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            hueDragging = false
        end
    end ) )

    -- Open animation
    popover.BackgroundTransparency = 1
    popover.Size = UDim2.new( 0, 220, 0, 0 )
    self:_trackTween( Animate( popover, {
        Size = UDim2.new( 0, 220, 0, 220 ),
        BackgroundTransparency = theme.Transparency_Popover,
    }, theme.Anim_Normal, Enum.EasingStyle.Quart, Enum.EasingDirection.Out ) )
end

function ColorPicker:_updateSV( mx: number, my: number )
    if not self._sv then return end
    local sp = self._sv.AbsolutePosition
    local ss = self._sv.AbsoluteSize
    local s = Utils.clamp( ( mx - sp.X ) / ss.X, 0, 1 )
    local v = Utils.clamp( 1 - ( my - sp.Y ) / ss.Y, 0, 1 )
    self._s = s
    self._v = v
    self:_svThumb.Position = UDim2.new( s, -4, 1 - v, -4 )
    self:_updateColor( Color3.fromHSV( self._h, s, v ) )
end

function ColorPicker:_updateHue( mx: number )
    if not self._hue then return end
    local hp = self._hue.AbsolutePosition
    local hs = self._hue.AbsoluteSize
    local h = Utils.clamp( ( mx - hp.X ) / hs.X, 0, 1 )
    self._h = h
    self._hueThumb.Position = UDim2.new( h, -2, 0.5, -8 )
    self._sv.BackgroundColor3 = Color3.fromHSV( h, 1, 1 )
    self:_updateColor( Color3.fromHSV( h, self._s, self._v ) )
end

function ColorPicker:_updateColor( c: Color3, fromHex: boolean? )
    self._value = c
    if self._swatch then self._swatch.BackgroundColor3 = c end
    if self._hexBox and not fromHex then
        self._hexBox.Text = "#" .. Utils.colorToHex( c )
    end
    self:_signal( "Changed" ):Fire( c, self._alpha or 1 )
    if self._callback then
        local ok, err = pcall( self._callback, c, self._alpha or 1 )
        if not ok then warn( "[Ignite:ColorPicker] callback error: " .. tostring( err ) ) end
    end
end

function ColorPicker:SetValue( c: Color3 )
    if typeof( c ) ~= "Color3" then error( "ColorPicker:SetValue expects Color3", 2 ) end
    self._value = c
    self._h, self._s, self._v = c:ToHSV()
    if self._swatch then self._swatch.BackgroundColor3 = c end
    if self._svThumb then
        self._svThumb.Position = UDim2.new( self._s, -4, 1 - self._v, -4 )
    end
    if self._hueThumb then
        self._hueThumb.Position = UDim2.new( self._h, -2, 0.5, -8 )
    end
    if self._sv then
        self._sv.BackgroundColor3 = Color3.fromHSV( self._h, 1, 1 )
    end
    if self._hexBox then
        self._hexBox.Text = "#" .. Utils.colorToHex( c )
    end
    self:_signal( "Changed" ):Fire( c, self._alpha or 1 )
    if self._callback then
        pcall( self._callback, c, self._alpha or 1 )
    end
end

function ColorPicker:GetValue(): Color3
    return self._value
end

--==============================================================
-- SECTION 15: INPUT ( TEXTBOX ) COMPONENT
--==============================================================

local Input = setmetatable( {}, Component )
Input.__index = Input
Input._type = "Input"

function Input.new( parent: Instance, config: any )
    local self = setmetatable( Component.new(), Input )
    self._value = config.Default or ""
    self._numeric = config.Numeric == true
    self._maxLength = config.MaxLength or 50
    self._clearOnFocus = config.ClearOnFocus == true
    self._flag = config.Flag
    self._callback = config.Callback
    self:_build( parent, config )
    return self
end

function Input:_build( parent: Instance, config: any )
    local theme = ThemeManager.get()

    local card = makeFrame( parent, {
        Name = "InputCard",
        Size = UDim2.new( 1, 0, 0, 36 ),
        BackgroundColor3 = theme.Background_Card,
        BackgroundTransparency = theme.Transparency_Card,
        LayoutOrder = config.Order or 0,
    } )
    addCorner( card, theme.Corner_Medium )
    addPadding( card, UDim.new( 0, 12 ) )
    self._card = card
    self:_addInstance( card, "card" )

    local nameLbl = makeLabel( card, {
        Name = "Name",
        Size = UDim2.new( 0, 120, 1, 0 ),
        Position = UDim2.new( 0, 12, 0, 0 ),
        Font = theme.Font_Body,
        TextColor3 = theme.Text_Secondary,
        TextSize = theme.Size_Body,
        Text = config.Name or "Input",
        TextXAlignment = Enum.TextXAlignment.Left,
    } )
    self:_addInstance( nameLbl, "name" )

    local box = Instance.new( "TextBox" )
    box.Name = "Box"
    box.Size = UDim2.new( 0, 180, 0, 22 )
    box.Position = UDim2.new( 1, -192, 0.5, -11 )
    box.BackgroundColor3 = theme.Background_Input
    box.BackgroundTransparency = 0
    box.BorderSizePixel = 0
    box.Font = theme.Font_Body
    box.TextColor3 = theme.Text_Primary
    box.PlaceholderColor3 = theme.Text_Tertiary
    box.PlaceholderText = config.Placeholder or ""
    box.Text = self._value
    box.TextSize = theme.Size_BodySmall
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.ClearTextOnFocus = false
    box.Numeric = self._numeric
    box.MaxLength = self._maxLength
    box.Parent = card
    addCorner( box, theme.Corner_Small )
    self._boxStroke = addStroke( box, 1, theme.Border_Default, 0 )
    self._box = box
    self:_addInstance( box, "box" )

    local pad = Instance.new( "UIPadding" )
    pad.PaddingLeft = UDim.new( 0, 8 )
    pad.PaddingRight = UDim.new( 0, 8 )
    pad.Parent = box

    self:_addConnection( box.Focused:Connect( function()
        self:_trackTween( Animate( box, {
            BackgroundColor3 = theme.Background_Window,
        }, theme.Anim_Fast ) )
        if self._boxStroke then
            self._boxStroke.Color = theme.Accent_Primary
        end
        if self._clearOnFocus then box.Text = "" end
    end ) )

    self:_addConnection( box.FocusLost:Connect( function( enterPressed )
        self:_trackTween( Animate( box, {
            BackgroundColor3 = theme.Background_Input,
        }, theme.Anim_Fast ) )
        if self._boxStroke then
            self._boxStroke.Color = theme.Border_Default
        end
        self._value = box.Text
        self:_signal( "Changed" ):Fire( self._value )
        if self._callback then
            local ok, err = pcall( self._callback, self._value )
            if not ok then warn( "[Ignite:Input] callback error: " .. tostring( err ) ) end
        end
        if enterPressed and config.OnEnter then
            pcall( config.OnEnter, self._value )
        end
    end ) )

    if config.Tooltip then self:SetTooltip( config.Tooltip ) end

    self:_addConnection( ThemeManager.changed():Connect( function( t )
        theme = t
        card.BackgroundColor3 = t.Background_Card
        nameLbl.TextColor3 = t.Text_Secondary
        box.BackgroundColor3 = t.Background_Input
    end ) )
end

function Input:SetValue( v: string )
    if typeof( v ) ~= "string" then v = tostring( v ) end
    self._value = v
    if self._box then self._box.Text = v end
    self:_signal( "Changed" ):Fire( v )
    if self._callback then pcall( self._callback, v ) end
end

function Input:GetValue(): string
    return self._value
end

--==============================================================
-- SECTION 16: BUTTON COMPONENT
--==============================================================

local Button = setmetatable( {}, Component )
Button.__index = Button
Button._type = "Button"

function Button.new( parent: Instance, config: any )
    local self = setmetatable( Component.new(), Button )
    self._style = config.Style or "Primary"
    self._icon = config.Icon
    self._callback = config.Callback
    self._loading = false
    self:_build( parent, config )
    return self
end

function Button:_build( parent: Instance, config: any )
    local theme = ThemeManager.get()

    local card = makeFrame( parent, {
        Name = "ButtonCard",
        Size = UDim2.new( 1, 0, 0, 36 ),
        BackgroundColor3 = self:_computeColor(),
        BackgroundTransparency = 0,
        LayoutOrder = config.Order or 0,
    } )
    addCorner( card, theme.Corner_Medium )
    self._card = card
    self:_addInstance( card, "card" )

    local lbl = makeLabel( card, {
        Name = "Label",
        Size = UDim2.new( 1, 0, 1, 0 ),
        Font = theme.Font_Heading,
        TextColor3 = self:_computeTextColor(),
        TextSize = theme.Size_Body,
        Text = config.Name or "Button",
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
    } )
    self:_addInstance( lbl, "label" )

    if config.Description then
        card.Size = UDim2.new( 1, 0, 0, 48 )
        lbl.Size = UDim2.new( 1, 0, 0, 18 )
        lbl.Position = UDim2.new( 0, 0, 0, 8 )
        local desc = makeLabel( card, {
            Size = UDim2.new( 1, 0, 0, 14 ),
            Position = UDim2.new( 0, 0, 0, 26 ),
            Font = theme.Font_Caption,
            TextColor3 = self:_computeTextColor( true ),
            TextSize = theme.Size_Caption,
            Text = config.Description,
            TextXAlignment = Enum.TextXAlignment.Center,
        } )
        self:_addInstance( desc, "desc" )
    end

    local clickArea = makeButton( card, {
        Name = "ClickArea",
        Size = UDim2.new( 1, 0, 1, 0 ),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
    } )
    self:_addInstance( clickArea, "clickArea" )

    self:_addConnection( clickArea.MouseButton1Click:Connect( function()
        if not self._enabled or self._loading then return end
        -- Press feedback
        self:_trackTween( Animate( card, {
            Size = UDim2.new( 1, 0, 0, card.AbsoluteSize.Y - 2 ),
            Position = UDim2.new( 0, 0, 0, 1 ),
        }, 0.04 ) )
        task.delay( 0.08, function()
            self:_trackTween( Animate( card, {
                Size = UDim2.new( 1, 0, 0, config.Description and 48 or 36 ),
                Position = UDim2.new( 0, 0, 0, 0 ),
            }, 0.08, Enum.EasingStyle.Back, Enum.EasingDirection.Out ) )
        end )
        if self._callback then
            local ok, err = pcall( self._callback )
            if not ok then warn( "[Ignite:Button] callback error: " .. tostring( err ) ) end
        end
    end ) )

    self:_addConnection( clickArea.MouseEnter:Connect( function()
        self:_trackTween( Animate( card, {
            BackgroundColor3 = self:_computeColor( true ),
        }, theme.Anim_Fast ) )
    end ) )
    self:_addConnection( clickArea.MouseLeave:Connect( function()
        self:_trackTween( Animate( card, {
            BackgroundColor3 = self:_computeColor(),
        }, theme.Anim_Fast ) )
    end ) )

    if config.Tooltip then self:SetTooltip( config.Tooltip ) end
end

function Button:_computeColor( hover: boolean? ): Color3
    local theme = ThemeManager.get()
    if self._style == "Primary" then
        return hover and theme.Accent_Hover or theme.Accent_Primary
    elseif self._style == "Danger" then
        return hover and Color3.fromHex( "DC2626" ) or Color3.fromHex( "EF4444" )
    elseif self._style == "Secondary" then
        return hover and theme.Background_CardHover or theme.Background_Card
    end
    return theme.Background_Card
end

function Button:_computeTextColor( dim: boolean? ): Color3
    local theme = ThemeManager.get()
    if self._style == "Primary" then
        return dim and Color3.fromRGB( 255, 220, 200 ) or theme.Text_OnAccent
    elseif self._style == "Danger" then
        return Color3.fromRGB( 255, 255, 255 )
    elseif self._style == "Secondary" then
        return dim and theme.Text_Tertiary or theme.Text_Primary
    end
    return theme.Text_Primary
end

function Button:SetValue( _v ) end
function Button:GetValue() return nil end

function Button:SetLoading( state: boolean )
    self._loading = state
    if self._label then
        self._label.Text = state and "..." or ( self._config and self._config.Name or "Button" )
    end
end

--==============================================================
-- SECTION 17: LABEL COMPONENT
--==============================================================

local Label = setmetatable( {}, Component )
Label.__index = Label
Label._type = "Label"

function Label.new( parent: Instance, config: any )
    local self = setmetatable( Component.new(), Label )
    self._text = config.Text or ""
    self._style = config.Style or "Body"
    self._richText = config.RichText == true
    self:_build( parent, config )
    return self
end

function Label:_build( parent: Instance, config: any )
    local theme = ThemeManager.get()
    local textSize = theme.Size_Body
    local font = theme.Font_Body
    local color = theme.Text_Secondary
    if self._style == "Section" then
        textSize = theme.Size_H3
        font = theme.Font_Heading
        color = theme.Text_Primary
    elseif self._style == "Caption" then
        textSize = theme.Size_Caption
        font = theme.Font_Caption
        color = theme.Text_Tertiary
    elseif self._style == "Mono" then
        textSize = theme.Size_BodySmall
        font = theme.Font_Mono
        color = theme.Text_Primary
    end

    local lbl = makeLabel( parent, {
        Name = "Label",
        Size = UDim2.new( 1, 0, 0, textSize + 6 ),
        Font = font,
        TextColor3 = color,
        TextSize = textSize,
        Text = self._text,
        RichText = self._richText,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = config.Order or 0,
    } )
    self._lbl = lbl
    self:_addInstance( lbl, "lbl" )

    self:_addConnection( ThemeManager.changed():Connect( function( t )
        if self._style == "Section" then
            lbl.TextColor3 = t.Text_Primary
        elseif self._style == "Caption" then
            lbl.TextColor3 = t.Text_Tertiary
        elseif self._style == "Mono" then
            lbl.TextColor3 = t.Text_Primary
        else
            lbl.TextColor3 = t.Text_Secondary
        end
    end ) )
end

function Label:SetText( text: string )
    self._text = text
    if self._lbl then self._lbl.Text = text end
end

function Label:GetText(): string
    return self._text
end

--==============================================================
-- SECTION 18: DIVIDER COMPONENT
--==============================================================

local Divider = setmetatable( {}, Component )
Divider.__index = Divider
Divider._type = "Divider"

function Divider.new( parent: Instance, config: any )
    local self = setmetatable( Component.new(), Divider )
    self._text = config.Text
    self._thickness = config.Thickness or 1
    self:_build( parent, config )
    return self
end

function Divider:_build( parent: Instance, config: any )
    local theme = ThemeManager.get()

    local container = makeFrame( parent, {
        Name = "Divider",
        Size = UDim2.new( 1, 0, 0, self._text and 24 or 12 ),
        BackgroundTransparency = 1,
        LayoutOrder = config.Order or 0,
    } )
    self._container = container
    self:_addInstance( container, "container" )

    if self._text then
        -- Label centered with lines on both sides
        local line1 = makeFrame( container, {
            Size = UDim2.new( 0.4, 0, 0, self._thickness ),
            Position = UDim2.new( 0, 0, 0.5, -self._thickness / 2 ),
            BackgroundColor3 = theme.Divider,
            BackgroundTransparency = theme.Transparency_Divider,
        } )
        local lbl = makeLabel( container, {
            Size = UDim2.new( 0.2, 0, 1, 0 ),
            Position = UDim2.new( 0.4, 0, 0, 0 ),
            Font = theme.Font_Caption,
            TextColor3 = theme.Text_Tertiary,
            TextSize = theme.Size_Caption,
            Text = self._text,
            TextXAlignment = Enum.TextXAlignment.Center,
        } )
        local line2 = makeFrame( container, {
            Size = UDim2.new( 0.4, 0, 0, self._thickness ),
            Position = UDim2.new( 0.6, 0, 0.5, -self._thickness / 2 ),
            BackgroundColor3 = theme.Divider,
            BackgroundTransparency = theme.Transparency_Divider,
        } )
        self:_addInstance( line1, "line1" )
        self:_addInstance( lbl, "lbl" )
        self:_addInstance( line2, "line2" )
    else
        local line = makeFrame( container, {
            Size = UDim2.new( 1, 0, 0, self._thickness ),
            Position = UDim2.new( 0, 0, 0.5, -self._thickness / 2 ),
            BackgroundColor3 = theme.Divider,
            BackgroundTransparency = theme.Transparency_Divider,
        } )
        self:_addInstance( line, "line" )
    end

    self:_addConnection( ThemeManager.changed():Connect( function( t )
        for _, inst in ipairs( self._instances ) do
            if inst:IsA( "Frame" ) then
                inst.BackgroundColor3 = t.Divider
                inst.BackgroundTransparency = t.Transparency_Divider
            end
        end
    end ) )
end

--==============================================================
-- SECTION 19: SECTION CONTAINER
--==============================================================

local Section = setmetatable( {}, Component )
Section.__index = Section
Section._type = "Section"

function Section.new( parent: Instance, config: any )
    local self = setmetatable( Component.new(), Section )
    self._name = config.Name or "Section"
    self._collapsible = config.Collapsible == true
    self._collapsed = config.DefaultCollapsed == true
    self._components = {}
    self:_build( parent, config )
    return self
end

function Section:_build( parent: Instance, config: any )
    local theme = ThemeManager.get()

    local container = makeFrame( parent, {
        Name = "Section_" .. ( config.Name or "?" ),
        Size = UDim2.new( 1, 0, 0, 0 ),
        BackgroundTransparency = 1,
        LayoutOrder = config.Order or 0,
        AutomaticSize = Enum.AutomaticSize.Y,
    } )
    self._container = container
    self:_addInstance( container, "container" )

    -- Header ( collapsible toggle )
    local header = makeButton( container, {
        Name = "Header",
        Size = UDim2.new( 1, 0, 0, 32 ),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
    } )
    self:_addInstance( header, "header" )

    local chevron = makeLabel( header, {
        Name = "Chevron",
        Size = UDim2.new( 0, 14, 0, 14 ),
        Position = UDim2.new( 0, 0, 0.5, -7 ),
        Font = theme.Font_Main,
        TextColor3 = theme.Text_Tertiary,
        TextSize = 12,
        Text = getIcon( "chevron_down" ),
        Rotation = self._collapsed and -90 or 0,
        TextXAlignment = Enum.TextXAlignment.Center,
    } )
    self:_addInstance( chevron, "chevron" )

    local title = makeLabel( header, {
        Name = "Title",
        Size = UDim2.new( 1, -24, 1, 0 ),
        Position = UDim2.new( 0, 20, 0, 0 ),
        Font = theme.Font_Heading,
        TextColor3 = theme.Text_Primary,
        TextSize = theme.Size_H3,
        Text = self._name,
        TextXAlignment = Enum.TextXAlignment.Left,
    } )
    self:_addInstance( title, "title" )

    -- Body
    local body = makeFrame( container, {
        Name = "Body",
        Size = UDim2.new( 1, 0, 0, 0 ),
        Position = UDim2.new( 0, 0, 0, 32 ),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
        Visible = not self._collapsed,
    } )
    addList( body, Enum.FillDirection.Vertical, UDim.new( 0, 8 ),
             Enum.HorizontalAlignment.Stretch, Enum.VerticalAlignment.Top )
    self._body = body
    self:_addInstance( body, "body" )

    if self._collapsible then
        self:_addConnection( header.MouseButton1Click:Connect( function()
            self._collapsed = not self._collapsed
            self:_trackTween( Animate( chevron, {
                Rotation = self._collapsed and -90 or 0,
            }, theme.Anim_Normal, Enum.EasingStyle.Quad, Enum.EasingDirection.Out ) )
            if self._collapsed then
                self:_trackTween( Animate( body, {
                    BackgroundTransparency = 1,
                }, theme.Anim_Fast ) )
                task.delay( theme.Anim_Fast, function()
                    if self._collapsed and self._body then
                        self._body.Visible = false
                    end
                end )
            else
                self._body.Visible = true
                self:_trackTween( Animate( body, {
                    BackgroundTransparency = 1,
                }, theme.Anim_Fast ) )
            end
        end ) )
    end

    self:_addConnection( ThemeManager.changed():Connect( function( t )
        chevron.TextColor3 = t.Text_Tertiary
        title.TextColor3 = t.Text_Primary
    end ) )
end

-- Component factories
function Section:CreateToggle( config: any )
    local c = Toggle.new( self._body, config )
    table.insert( self._components, c )
    self:_addChild( c )
    if c._flag then Library._registerFlag( c._flag, c ) end
    return c
end

function Section:CreateSlider( config: any )
    local c = Slider.new( self._body, config )
    table.insert( self._components, c )
    self:_addChild( c )
    if c._flag then Library._registerFlag( c._flag, c ) end
    return c
end

function Section:CreateDropdown( config: any )
    local c = Dropdown.new( self._body, config )
    table.insert( self._components, c )
    self:_addChild( c )
    if c._flag then Library._registerFlag( c._flag, c ) end
    return c
end

function Section:CreateKeybind( config: any )
    local c = Keybind.new( self._body, config )
    table.insert( self._components, c )
    self:_addChild( c )
    if c._flag then Library._registerFlag( c._flag, c ) end
    return c
end

function Section:CreateColorPicker( config: any )
    local c = ColorPicker.new( self._body, config )
    table.insert( self._components, c )
    self:_addChild( c )
    if c._flag then Library._registerFlag( c._flag, c ) end
    return c
end

function Section:CreateInput( config: any )
    local c = Input.new( self._body, config )
    table.insert( self._components, c )
    self:_addChild( c )
    if c._flag then Library._registerFlag( c._flag, c ) end
    return c
end

function Section:CreateButton( config: any )
    local c = Button.new( self._body, config )
    table.insert( self._components, c )
    self:_addChild( c )
    return c
end

function Section:CreateLabel( config: any )
    local c = Label.new( self._body, config )
    table.insert( self._components, c )
    self:_addChild( c )
    return c
end

function Section:CreateDivider( config: any )
    local c = Divider.new( self._body, config )
    table.insert( self._components, c )
    self:_addChild( c )
    return c
end

--==============================================================
-- SECTION 20: SUBSECTION CONTAINER
--==============================================================

local Subsection = setmetatable( {}, Component )
Subsection.__index = Subsection
Subsection._type = "Subsection"

function Subsection.new( parent: Instance, config: any, tab: any )
    local self = setmetatable( Component.new(), Subsection )
    self._name = config.Name or "Subsection"
    self._tab = tab
    self._sections = {}
    self._button = nil
    self:_build( parent, config )
    return self
end

function Subsection:_build( parent: Instance, config: any )
    local theme = ThemeManager.get()
    -- Content container ( held inside Tab content area, shown/hidden on switch )
    local container = makeFrame( parent, {
        Name = "Subsection_" .. ( config.Name or "?" ),
        Size = UDim2.new( 1, 0, 1, 0 ),
        BackgroundTransparency = 1,
        Visible = false,
        LayoutOrder = config.Order or 0,
    } )
    addList( container, Enum.FillDirection.Vertical, UDim.new( 0, 16 ),
             Enum.HorizontalAlignment.Stretch, Enum.VerticalAlignment.Top )
    self._container = container
    self:_addInstance( container, "container" )

    -- Button in subsection nav ( created by Tab when wiring nav )
    self._navButton = nil

    self:_addConnection( ThemeManager.changed():Connect( function( t )
        -- nothing dynamic for now
    end ) )
end

function Subsection:CreateSection( config: any )
    local s = Section.new( self._container, config )
    table.insert( self._sections, s )
    self:_addChild( s )
    return s
end

function Subsection:Show()
    if self._container then
        self._container.Visible = true
        self:_trackTween( Animate( self._container, {
            BackgroundTransparency = 1,
        }, ThemeManager.get().Anim_Fast ) )
    end
    if self._navButton then
        self._navButton.TextColor3 = ThemeManager.get().Text_Primary
    end
end

function Subsection:Hide()
    if self._container then
        self:_trackTween( Animate( self._container, {
            BackgroundTransparency = 1,
        }, ThemeManager.get().Anim_Fast ) )
        task.delay( ThemeManager.get().Anim_Fast, function()
            if self._container then self._container.Visible = false end
        end )
    end
    if self._navButton then
        self._navButton.TextColor3 = ThemeManager.get().Text_Tertiary
    end
end

--==============================================================
-- SECTION 21: TAB CONTAINER
--==============================================================

local Tab = setmetatable( {}, Component )
Tab.__index = Tab
Tab._type = "Tab"

function Tab.new( parent: Instance, config: any, window: any )
    local self = setmetatable( Component.new(), Tab )
    self._name = config.Name or "Tab"
    self._icon = config.Icon
    self._window = window
    self._subsections = {}
    self._activeSubsection = nil
    self:_build( parent, config )
    return self
end

function Tab:_build( parent: Instance, config: any )
    local theme = ThemeManager.get()
    -- Content area inside Window's ScrollingFrame
    local container = makeFrame( parent, {
        Name = "Tab_" .. ( config.Name or "?" ),
        Size = UDim2.new( 1, 0, 1, 0 ),
        BackgroundTransparency = 1,
        Visible = false,
    } )
    self._container = container
    self:_addInstance( container, "container" )

    -- Subsection nav bar ( horizontal, top of tab content )
    local subNav = makeFrame( container, {
        Name = "SubsectionNav",
        Size = UDim2.new( 1, 0, 0, theme.Subsection_Height ),
        BackgroundTransparency = 1,
    } )
    addList( subNav, Enum.FillDirection.Horizontal, UDim.new( 0, 4 ),
             Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center )
    self._subNav = subNav
    self:_addInstance( subNav, "subNav" )

    -- Content area for subsections
    local contentArea = makeFrame( container, {
        Name = "SubsectionContent",
        Size = UDim2.new( 1, 0, 1, -theme.Subsection_Height ),
        Position = UDim2.new( 0, 0, 0, theme.Subsection_Height ),
        BackgroundTransparency = 1,
    } )
    self._contentArea = contentArea
    self:_addInstance( contentArea, "contentArea" )

    -- Sidebar item ( created by Window and stored here )
    self._sidebarItem = nil
    self._tabBarItem = nil
end

function Tab:CreateSubsection( config: any )
    local sub = Subsection.new( self._contentArea, config, self )
    table.insert( self._subsections, sub )
    self:_addChild( sub )

    -- Add nav button
    local theme = ThemeManager.get()
    local btn = makeButton( self._subNav, {
        Name = "SubsectionBtn_" .. ( config.Name or "?" ),
        Size = UDim2.new( 0, 80, 0, 24 ),
        BackgroundTransparency = 1,
        Text = config.Name or "Sub",
        Font = theme.Font_Body,
        TextColor3 = theme.Text_Tertiary,
        TextSize = theme.Size_BodySmall,
        AutoButtonColor = false,
        LayoutOrder = config.Order or #self._subsections,
    } )
    sub._navButton = btn
    self:_addInstance( btn, "subBtn_" .. ( config.Name or "?" ) )

    local indicator = makeFrame( btn, {
        Name = "Indicator",
        Size = UDim2.new( 0, 0, 0, 2 ),
        Position = UDim2.new( 0.5, 0, 1, -2 ),
        AnchorPoint = Vector2.new( 0.5, 0 ),
        BackgroundColor3 = theme.Accent_Primary,
        BackgroundTransparency = 0,
    } )
    self:_addInstance( indicator, "ind_" .. ( config.Name or "?" ) )

    local function activate()
        for _, s in ipairs( self._subsections ) do
            s:Hide()
        end
        sub:Show()
        -- Animate indicator
        for _, c in ipairs( self._subNav:GetChildren() ) do
            if c:IsA( "GuiButton" ) and c:FindFirstChild( "Indicator" ) then
                self:_trackTween( Animate( c.Indicator, {
                    Size = UDim2.new( 0, 0, 0, 2 ),
                }, theme.Anim_Fast ) )
            end
        end
        self:_trackTween( Animate( indicator, {
            Size = UDim2.new( 1, 0, 0, 2 ),
        }, theme.Anim_Normal, Enum.EasingStyle.Quart, Enum.EasingDirection.Out ) )
        self._activeSubsection = sub
    end

    self:_addConnection( btn.MouseButton1Click:Connect( activate ) )

    -- Auto-activate first subsection
    if #self._subsections == 1 then
        task.spawn( activate )
    end
    return sub
end

function Tab:Show()
    if self._container then
        self._container.Visible = true
    end
    if self._sidebarItem then
        local theme = ThemeManager.get()
        self:_trackTween( Animate( self._sidebarItem, {
            BackgroundColor3 = theme.Background_CardActive,
            BackgroundTransparency = 0,
        }, theme.Anim_Fast ) )
        if self._sidebarIndicator then
            self._sidebarIndicator.BackgroundTransparency = 0
        end
    end
    if self._tabBarItem then
        local theme = ThemeManager.get()
        self._tabBarItem.TextColor3 = theme.Text_Primary
        if self._tabBarIndicator then
            self._tabBarIndicator.BackgroundTransparency = 0
        end
    end
end

function Tab:Hide()
    if self._container then
        self._container.Visible = false
    end
    if self._sidebarItem then
        local theme = ThemeManager.get()
        self:_trackTween( Animate( self._sidebarItem, {
            BackgroundTransparency = 1,
        }, theme.Anim_Fast ) )
        if self._sidebarIndicator then
            self._sidebarIndicator.BackgroundTransparency = 1
        end
    end
    if self._tabBarItem then
        local theme = ThemeManager.get()
        self._tabBarItem.TextColor3 = theme.Text_Secondary
        if self._tabBarIndicator then
            self._tabBarIndicator.BackgroundTransparency = 1
        end
    end
end

--==============================================================
-- SECTION 22: WINDOW COMPONENT
--==============================================================

local Window = setmetatable( {}, Component )
Window.__index = Window
Window._type = "Window"

function Window.new( config: any )
    local self = setmetatable( Component.new(), Window )
    self._config = config
    self._tabs = {}
    self._activeTab = nil
    self._visible = true
    self._minimized = false
    self._dragging = false
    self._resizing = false
    self:_build( config )
    return self
end

function Window:_build( config: any )
    local theme = ThemeManager.get()

    -- Root ScreenGui ( parented to protected container )
    local rootGui = Instance.new( "ScreenGui" )
    rootGui.Name = "Ignite_Root_" .. Utils.uid()
    rootGui.DisplayOrder = 100
    rootGui.ResetOnSpawn = false
    rootGui.IgnoreGuiInset = true
    rootGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    Utils.protectGui( rootGui )
    rootGui.Parent = Utils.getGuiParent()
    self._rootGui = rootGui
    self:_addInstance( rootGui, "rootGui" )

    -- Window container frame
    local width = config.Size and config.Size.X.Offset or theme.Window_Width
    local height = config.Size and config.Size.Y.Offset or theme.Window_Height
    local container = makeFrame( rootGui, {
        Name = "Window_Container",
        Size = UDim2.fromOffset( width, height ),
        Position = config.Position or UDim2.fromScale( 0.5, 0.5 ),
        AnchorPoint = config.AnchorPoint or Vector2.new( 0.5, 0.5 ),
        BackgroundColor3 = theme.Background_Window,
        BackgroundTransparency = theme.Transparency_Window,
        ClipsDescendants = true,
    } )
    addCorner( container, theme.Corner_XL )
    addStroke( container, 1, theme.Border_Default, 0 )
    self._container = container
    self:_addInstance( container, "container" )

    -- Shadow / glow
    local glow = makeImage( rootGui, {
        Name = "WindowGlow",
        Size = UDim2.new( 1, 32, 1, 32 ),
        Position = UDim2.new( 0.5, 0, 0.5, 0 ),
        AnchorPoint = Vector2.new( 0.5, 0.5 ),
        BackgroundColor3 = theme.Accent_Glow,
        BackgroundTransparency = 0.8,
        Image = "",
        ZIndex = -1,
    } )
    self:_addInstance( glow, "glow" )

    -- Header
    local header = makeFrame( container, {
        Name = "Header",
        Size = UDim2.new( 1, 0, 0, theme.Header_Height ),
        BackgroundColor3 = theme.Background_Panel,
        BackgroundTransparency = theme.Transparency_Panel,
    } )
    addStroke( header, 1, theme.Border_Subtle, 0.5 )
    self._header = header
    self:_addInstance( header, "header" )

    -- Header left group ( logo + name + version )
    local logoSize = 24
    local logo
    if config.Logo then
        logo = makeImage( header, {
            Name = "Logo",
            Size = UDim2.fromOffset( logoSize, logoSize ),
            Position = UDim2.fromOffset( 16, ( theme.Header_Height - logoSize ) / 2 ),
            Image = config.Logo,
            BackgroundColor3 = config.LogoColor or theme.Accent_Primary,
            BackgroundTransparency = 0,
        } )
    else
        logo = makeLabel( header, {
            Name = "Logo",
            Size = UDim2.fromOffset( logoSize, logoSize ),
            Position = UDim2.fromOffset( 16, ( theme.Header_Height - logoSize ) / 2 ),
            Font = theme.Font_Main,
            TextColor3 = config.LogoColor or theme.Accent_Primary,
            TextSize = logoSize,
            Text = getIcon( "fire" ),
            TextXAlignment = Enum.TextXAlignment.Center,
            TextYAlignment = Enum.TextYAlignment.Center,
        } )
    end
    self:_addInstance( logo, "logo" )

    local name = makeLabel( header, {
        Name = "Name",
        Size = UDim2.fromOffset( 100, theme.Header_Height ),
        Position = UDim2.fromOffset( 16 + logoSize + 8, 0 ),
        Font = theme.Font_Heading,
        TextColor3 = theme.Text_Primary,
        TextSize = theme.Size_H2,
        Text = config.Name or "Ignite",
        TextXAlignment = Enum.TextXAlignment.Left,
    } )
    self:_addInstance( name, "name" )

    local version = makeLabel( header, {
        Name = "Version",
        Size = UDim2.fromOffset( 80, theme.Header_Height ),
        Position = UDim2.fromOffset( 16 + logoSize + 8 + 100, 0 ),
        Font = theme.Font_Body,
        TextColor3 = theme.Text_Tertiary,
        TextSize = theme.Size_Caption,
        Text = "v" .. ( config.Version or "1.0.0" ),
        TextXAlignment = Enum.TextXAlignment.Left,
    } )
    self:_addInstance( version, "version" )

    -- Header right group ( date + minimize + close )
    local dateText = config.Subtitle or os.date( "%b %d, %Y" )
    local dateLbl = makeLabel( header, {
        Name = "Date",
        Size = UDim2.fromOffset( 120, theme.Header_Height ),
        Position = UDim2.new( 1, -16 - 120 - 64 - 64, 0, 0 ),
        Font = theme.Font_Body,
        TextColor3 = theme.Text_Tertiary,
        TextSize = theme.Size_Caption,
        Text = dateText,
        TextXAlignment = Enum.TextXAlignment.Right,
    } )
    self:_addInstance( dateLbl, "date" )

    local minimizeBtn = makeButton( header, {
        Name = "Minimize",
        Size = UDim2.fromOffset( 32, 32 ),
        Position = UDim2.new( 1, -16 - 32 - 32 - 8, 0, ( theme.Header_Height - 32 ) / 2 ),
        BackgroundTransparency = 1,
        Text = "\u{2014}",
        Font = theme.Font_Main,
        TextColor3 = theme.Text_Tertiary,
        TextSize = 14,
        AutoButtonColor = false,
    } )
    addCorner( minimizeBtn, theme.Corner_Small )
    self:_addInstance( minimizeBtn, "minimize" )

    local closeBtn = makeButton( header, {
        Name = "Close",
        Size = UDim2.fromOffset( 32, 32 ),
        Position = UDim2.new( 1, -16 - 32, 0, ( theme.Header_Height - 32 ) / 2 ),
        BackgroundTransparency = 1,
        Text = getIcon( "close" ),
        Font = theme.Font_Main,
        TextColor3 = theme.Text_Tertiary,
        TextSize = 14,
        AutoButtonColor = false,
    } )
    addCorner( closeBtn, theme.Corner_Small )
    self:_addInstance( closeBtn, "close" )

    -- Sidebar ( left, below header )
    local sidebar = makeFrame( container, {
        Name = "Sidebar",
        Size = UDim2.fromOffset( theme.Sidebar_Width, height - theme.Header_Height ),
        Position = UDim2.fromOffset( 0, theme.Header_Height ),
        BackgroundColor3 = theme.Background_Panel,
        BackgroundTransparency = theme.Transparency_Panel,
    } )
    addStroke( sidebar, 1, theme.Border_Subtle, 0.7 )
    self._sidebar = sidebar
    self:_addInstance( sidebar, "sidebar" )

    local sidebarList = addList( sidebar, Enum.FillDirection.Vertical,
        UDim.new( 0, 4 ), Enum.HorizontalAlignment.Center,
        Enum.VerticalAlignment.Top )
    sidebarList.Padding = UDim.new( 0, 8 )
    local sidebarPad = Instance.new( "UIPadding" )
    sidebarPad.PaddingTop = UDim.new( 0, 8 )
    sidebarPad.PaddingBottom = UDim.new( 0, 8 )
    sidebarPad.PaddingLeft = UDim.new( 0, 4 )
    sidebarPad.PaddingRight = UDim.new( 0, 4 )
    sidebarPad.Parent = sidebar

    -- TabBar ( top, right of sidebar )
    local tabBar = makeFrame( container, {
        Name = "TabBar",
        Size = UDim2.new( 1, -theme.Sidebar_Width, 0, theme.TabBar_Height ),
        Position = UDim2.fromOffset( theme.Sidebar_Width, theme.Header_Height ),
        BackgroundColor3 = theme.Background_Panel,
        BackgroundTransparency = theme.Transparency_Panel,
    } )
    addStroke( tabBar, 1, theme.Border_Subtle, 0.7 )
    self._tabBar = tabBar
    self:_addInstance( tabBar, "tabBar" )

    local tabBarList = addList( tabBar, Enum.FillDirection.Horizontal,
        UDim.new( 0, 4 ), Enum.HorizontalAlignment.Left,
        Enum.VerticalAlignment.Center )
    local tabBarPad = Instance.new( "UIPadding" )
    tabBarPad.PaddingLeft = UDim.new( 0, 12 )
    tabBarPad.PaddingRight = UDim.new( 0, 12 )
    tabBarPad.Parent = tabBar

    -- Subsection nav (below tab bar) — actually empty; per-tab subnav lives inside tab content
    -- (per spec the subsection nav is inside the tab content area). We keep a placeholder here
    -- only for visual consistency; the actual nav is per-tab.

    -- Content area ( below tab bar, right of sidebar, scrollable )
    local content = makeScroll( container, {
        Name = "Content",
        Size = UDim2.new( 1, -theme.Sidebar_Width, 1, -theme.Header_Height - theme.TabBar_Height ),
        Position = UDim2.fromOffset( theme.Sidebar_Width, theme.Header_Height + theme.TabBar_Height ),
        BackgroundColor3 = theme.Background_Window,
        BackgroundTransparency = 1,
        ScrollBarThickness = 4,
        CanvasSize = UDim2.new( 0, 0, 0, 0 ),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    } )
    local contentPad = Instance.new( "UIPadding" )
    contentPad.PaddingTop = UDim.new( 0, 16 )
    contentPad.PaddingBottom = UDim.new( 0, 16 )
    contentPad.PaddingLeft = UDim.new( 0, 16 )
    contentPad.PaddingRight = UDim.new( 0, 16 )
    contentPad.Parent = content
    local contentList = addList( content, Enum.FillDirection.Vertical,
        UDim.new( 0, 0 ), Enum.HorizontalAlignment.Stretch,
        Enum.VerticalAlignment.Top )
    self._content = content
    self:_addInstance( content, "content" )

    -- Resize handle ( bottom-right )
    local resizeHandle = makeFrame( container, {
        Name = "ResizeHandle",
        Size = UDim2.fromOffset( 16, 16 ),
        Position = UDim2.new( 1, -16, 1, -16 ),
        BackgroundTransparency = 1,
    } )
    self:_addInstance( resizeHandle, "resizeHandle" )

    -- Drag logic
    local dragStartPos, dragStartMouse
    self:_addConnection( header.InputBegan:Connect( function( input )
        if input.UserInputType == Enum.UserInputType.MouseButton1
           or input.UserInputType == Enum.UserInputType.Touch then
            if not config.Draggable and config.Draggable == false then return end
            self._dragging = true
            dragStartPos = container.Position
            dragStartMouse = UserInputService:GetMouseLocation()
        end
    end ) )
    self:_addConnection( UserInputService.InputChanged:Connect( function( input )
        if self._dragging and ( input.UserInputType == Enum.UserInputType.MouseMovement
                              or input.UserInputType == Enum.UserInputType.Touch ) then
            local mp = UserInputService:GetMouseLocation()
            local inset = UserInputService:GetGuiInset()
            local dx = mp.X - dragStartMouse.X
            local dy = mp.Y - ( dragStartMouse.Y - inset.Y ) - ( dragStartPos.Y.Offset - ( dragStartPos.Y.Offset ) )
            local newX = dragStartPos.X.Offset + dx
            local newY = dragStartPos.Y.Offset + ( mp.Y - dragStartMouse.Y )
            local viewport = Workspace.CurrentCamera.ViewportSize
            newX = Utils.clamp( newX, 0, viewport.X - container.AbsoluteSize.X )
            newY = Utils.clamp( newY, 0, viewport.Y - container.AbsoluteSize.Y )
            container.Position = UDim2.fromOffset( newX, newY )
        end
    end ) )
    self:_addConnection( UserInputService.InputEnded:Connect( function( input )
        if input.UserInputType == Enum.UserInputType.MouseButton1
           or input.UserInputType == Enum.UserInputType.Touch then
            self._dragging = false
            self._resizing = false
        end
    end ) )

    -- Resize logic
    local resizeStartSize, resizeStartMouse2
    self:_addConnection( resizeHandle.InputBegan:Connect( function( input )
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            if config.Resizable == false then return end
            self._resizing = true
            resizeStartSize = container.Size
            resizeStartMouse2 = UserInputService:GetMouseLocation()
        end
    end ) )
    self:_addConnection( UserInputService.InputChanged:Connect( function( input )
        if self._resizing and input.UserInputType == Enum.UserInputType.MouseMovement then
            local mp = UserInputService:GetMouseLocation()
            local dx = mp.X - resizeStartMouse2.X
            local dy = mp.Y - resizeStartMouse2.Y
            local minSize = config.MinSize or UDim2.fromOffset( 600, 400 )
            local maxSize = config.MaxSize or UDim2.fromOffset( 1200, 800 )
            local newW = Utils.clamp( resizeStartSize.X.Offset + dx,
                                      minSize.X.Offset, maxSize.X.Offset )
            local newH = Utils.clamp( resizeStartSize.Y.Offset + dy,
                                      minSize.Y.Offset, maxSize.Y.Offset )
            container.Size = UDim2.fromOffset( newW, newH )
        end
    end ) )

    -- Minimize / Close
    self:_addConnection( minimizeBtn.MouseButton1Click:Connect( function()
        self:_minimize()
    end ) )
    self:_addConnection( closeBtn.MouseButton1Click:Connect( function()
        self:_close()
    end ) )

    -- Hover handlers for header buttons
    local function bindHeaderHover( btn, normalColor, hoverColor )
        self:_addConnection( btn.MouseEnter:Connect( function()
            self:_trackTween( Animate( btn, {
                BackgroundColor3 = hoverColor,
                BackgroundTransparency = 0,
            }, theme.Anim_Fast ) )
        end ) )
        self:_addConnection( btn.MouseLeave:Connect( function()
            self:_trackTween( Animate( btn, {
                BackgroundTransparency = 1,
            }, theme.Anim_Fast ) )
        end ) )
    end
    bindHeaderHover( minimizeBtn, theme.Background_CardHover, theme.Background_CardHover )
    bindHeaderHover( closeBtn, theme.State_Error_Primary, theme.State_Error_Primary )

    -- Keybind toggle ( hide/show )
    if config.KeybindToggle then
        self:_addConnection( UserInputService.InputBegan:Connect( function( input, gp )
            if gp then return end
            if input.KeyCode == config.KeybindToggle then
                self:Toggle()
            end
        end ) )
    end

    -- Theme change
    self:_addConnection( ThemeManager.changed():Connect( function( t )
        container.BackgroundColor3 = t.Background_Window
        header.BackgroundColor3 = t.Background_Panel
        sidebar.BackgroundColor3 = t.Background_Panel
        tabBar.BackgroundColor3 = t.Background_Panel
        name.TextColor3 = t.Text_Primary
        version.TextColor3 = t.Text_Tertiary
        dateLbl.TextColor3 = t.Text_Tertiary
    end ) )
end

function Window:_minimize()
    if self._minimized then
        -- Restore
        self._minimized = false
        self:_trackTween( Animate( self._content, {
            Position = UDim2.fromOffset( ThemeManager.get().Sidebar_Width,
                                         ThemeManager.get().Header_Height
                                         + ThemeManager.get().TabBar_Height ),
            BackgroundTransparency = 1,
        }, ThemeManager.get().Anim_Normal ) )
    else
        -- Minimize
        self._minimized = true
        self:_trackTween( Animate( self._content, {
            BackgroundTransparency = 1,
        }, ThemeManager.get().Anim_Fast ) )
    end
end

function Window:_close()
    local theme = ThemeManager.get()
    self:_trackTween( Animate( self._container, {
        Size = UDim2.fromOffset( self._container.AbsoluteSize.X * 0.9,
                                 self._container.AbsoluteSize.Y * 0.9 ),
        BackgroundTransparency = 1,
    }, theme.Anim_Normal, Enum.EasingStyle.Back, Enum.EasingDirection.In ) )
    task.delay( theme.Anim_Normal, function()
        if self._config and self._config.OnClose then
            pcall( self._config.OnClose )
        end
        self:Destroy()
    end )
end

function Window:Toggle()
    local theme = ThemeManager.get()
    if self._visible then
        -- Hide
        self:_trackTween( Animate( self._container, {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset( self._container.Position.X.Offset,
                                         self._container.Position.Y.Offset + 20 ),
        }, theme.Anim_Normal, Enum.EasingStyle.Back, Enum.EasingDirection.In ) )
        task.delay( theme.Anim_Normal, function()
            if self._container then self._container.Visible = false end
        end )
        self._visible = false
    else
        -- Show
        self._container.Visible = true
        self:_trackTween( Animate( self._container, {
            BackgroundTransparency = 0,
            Position = UDim2.fromOffset( self._container.Position.X.Offset,
                                         self._container.Position.Y.Offset - 20 ),
        }, theme.Anim_Normal, Enum.EasingStyle.Back, Enum.EasingDirection.Out ) )
        self._visible = true
    end
end

function Window:CreateTab( config: any )
    local tab = Tab.new( self._content, config, self )
    table.insert( self._tabs, tab )
    self:_addChild( tab )

    local theme = ThemeManager.get()

    -- Sidebar item
    local sidebarItem = makeButton( self._sidebar, {
        Name = "SidebarItem_" .. ( config.Name or "?" ),
        Size = UDim2.new( 1, -8, 0, 40 ),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = config.Order or #self._tabs,
    } )
    addCorner( sidebarItem, theme.Corner_Medium )
    self:_addInstance( sidebarItem, "sidebarItem_" .. ( config.Name or "?" ) )

    local sidebarIndicator = makeFrame( sidebarItem, {
        Name = "Indicator",
        Size = UDim2.fromOffset( 3, 32 ),
        Position = UDim2.fromOffset( 0, 4 ),
        BackgroundColor3 = theme.Accent_Primary,
        BackgroundTransparency = 1,
    } )
    addGradient( sidebarIndicator,
                 ColorSequence.new( theme.Accent_GradientStart,
                                    theme.Accent_GradientEnd ), 90 )
    self:_addInstance( sidebarIndicator, "sidebarInd_" .. ( config.Name or "?" ) )

    local iconSize = 24
    local sidebarIcon = makeLabel( sidebarItem, {
        Name = "Icon",
        Size = UDim2.fromOffset( iconSize, iconSize ),
        Position = UDim2.new( 0.5, 0, 0.5, 0 ),
        AnchorPoint = Vector2.new( 0.5, 0.5 ),
        Font = theme.Font_Main,
        TextColor3 = theme.Text_Tertiary,
        TextSize = iconSize,
        Text = getIcon( config.Icon or "gear" ),
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
    } )
    self:_addInstance( sidebarIcon, "sidebarIcn_" .. ( config.Name or "?" ) )

    tab._sidebarItem = sidebarItem
    tab._sidebarIndicator = sidebarIndicator
    tab._sidebarIcon = sidebarIcon

    -- TabBar item
    local tabItem = makeButton( self._tabBar, {
        Name = "TabItem_" .. ( config.Name or "?" ),
        Size = UDim2.new( 0, 100, 0, 28 ),
        BackgroundTransparency = 1,
        Text = config.Name or "Tab",
        Font = theme.Font_Main,
        TextColor3 = theme.Text_Secondary,
        TextSize = theme.Size_Body,
        AutoButtonColor = false,
        LayoutOrder = config.Order or #self._tabs,
    } )
    self:_addInstance( tabItem, "tabItem_" .. ( config.Name or "?" ) )

    local tabBarIndicator = makeFrame( tabItem, {
        Name = "Indicator",
        Size = UDim2.new( 0, 0, 0, 2 ),
        Position = UDim2.new( 0.5, 0, 1, 0 ),
        AnchorPoint = Vector2.new( 0.5, 0 ),
        BackgroundColor3 = theme.Accent_Primary,
        BackgroundTransparency = 1,
    } )
    self:_addInstance( tabBarIndicator, "tabBarInd_" .. ( config.Name or "?" ) )

    tab._tabBarItem = tabItem
    tab._tabBarIndicator = tabBarIndicator

    -- Hover
    self:_addConnection( sidebarItem.MouseEnter:Connect( function()
        if self._activeTab ~= tab then
            self:_trackTween( Animate( sidebarItem, {
                BackgroundColor3 = theme.Background_CardHover,
                BackgroundTransparency = 0,
            }, theme.Anim_Fast ) )
            self:_trackTween( Animate( sidebarIcon, {
                TextColor3 = theme.Text_Primary,
            }, theme.Anim_Fast ) )
        end
    end ) )
    self:_addConnection( sidebarItem.MouseLeave:Connect( function()
        if self._activeTab ~= tab then
            self:_trackTween( Animate( sidebarItem, {
                BackgroundTransparency = 1,
            }, theme.Anim_Fast ) )
            self:_trackTween( Animate( sidebarIcon, {
                TextColor3 = theme.Text_Tertiary,
            }, theme.Anim_Fast ) )
        end
    end ) )

    self:_addConnection( tabItem.MouseEnter:Connect( function()
        if self._activeTab ~= tab then
            self:_trackTween( Animate( tabItem, {
                TextColor3 = theme.Text_Primary,
            }, theme.Anim_Fast ) )
        end
    end ) )
    self:_addConnection( tabItem.MouseLeave:Connect( function()
        if self._activeTab ~= tab then
            self:_trackTween( Animate( tabItem, {
                TextColor3 = theme.Text_Secondary,
            }, theme.Anim_Fast ) )
        end
    end ) )

    -- Click handlers
    local function activate()
        for _, t in ipairs( self._tabs ) do
            t:Hide()
        end
        tab:Show()
        self._activeTab = tab
        -- Active styles
        self:_trackTween( Animate( sidebarIcon, {
            TextColor3 = theme.Accent_Primary,
        }, theme.Anim_Fast ) )
        self:_trackTween( Animate( tabItem, {
            TextColor3 = theme.Text_Primary,
        }, theme.Anim_Fast ) )
        self:_trackTween( Animate( tabBarIndicator, {
            Size = UDim2.new( 0.8, 0, 0, 2 ),
            BackgroundTransparency = 0,
        }, theme.Anim_Normal, Enum.EasingStyle.Quart, Enum.EasingDirection.Out ) )
    end

    self:_addConnection( sidebarItem.MouseButton1Click:Connect( activate ) )
    self:_addConnection( tabItem.MouseButton1Click:Connect( activate ) )

    -- Auto-activate first tab
    if #self._tabs == 1 then
        task.spawn( activate )
    end

    return tab
end

function Window:Destroy()
    Component.Destroy( self )
end

--==============================================================
-- SECTION 23: TOOLTIP MANAGER
--==============================================================

-- Singleton tooltip manager ( binds tooltips to GuiObjects on hover ).
local TooltipManager = {}
TooltipManager.__index = TooltipManager
TooltipManager._type = "TooltipManager"

function TooltipManager.new( rootGui: Instance )
    local self = setmetatable( {}, TooltipManager )
    self._rootGui = rootGui
    self._bindings = {} -- [ inst ] = text
    self._current = nil
    self._tooltip = nil
    self._hoverDelay = 0.4
    self:_build()
    return self
end

function TooltipManager:_build()
    local theme = ThemeManager.get()
    local tooltip = makeFrame( self._rootGui, {
        Name = "Tooltip",
        Size = UDim2.fromOffset( 100, 24 ),
        BackgroundColor3 = theme.Background_Window,
        BackgroundTransparency = 0,
        Visible = false,
        ZIndex = 100,
    } )
    addCorner( tooltip, theme.Corner_Small )
    addStroke( tooltip, 1, theme.Border_Default, 0 )
    local label = makeLabel( tooltip, {
        Size = UDim2.new( 1, -12, 1, 0 ),
        Position = UDim2.fromOffset( 6, 0 ),
        Font = theme.Font_Body,
        TextColor3 = theme.Text_Primary,
        TextSize = theme.Size_Caption,
        Text = "",
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
    } )
    self._tooltip = tooltip
    self._label = label

    self._maid = Maid.new()
end

function TooltipManager:Bind( inst: Instance, text: string )
    if not inst then return end
    self._bindings[ inst ] = text
    self._maid:GiveTask( inst.MouseEnter:Connect( function()
        self:_show( inst, text )
    end ) )
    self._maid:GiveTask( inst.MouseLeave:Connect( function()
        self:_hide()
    end ) )
end

function TooltipManager:_show( inst: Instance, text: string )
    self._current = inst
    task.delay( self._hoverDelay, function()
        if self._current ~= inst then return end
        if not self._tooltip then return end
        self._label.Text = text
        local textSize = TextService:GetTextSize( text, ThemeManager.get().Size_Caption,
            ThemeManager.get().Font_Body, Vector2.new( 300, 24 ) )
        self._tooltip.Size = UDim2.fromOffset( textSize.X + 16, 24 )
        local mp = UserInputService:GetMouseLocation()
        local inset = UserInputService:GetGuiInset()
        self._tooltip.Position = UDim2.fromOffset( mp.X + 14, mp.Y - inset.Y + 14 )
        self._tooltip.Visible = true
        self._tooltip.BackgroundTransparency = 1
        local theme = ThemeManager.get()
        Animate( self._tooltip, {
            BackgroundTransparency = 0.05,
        }, theme.Anim_Fast ):Play()
    end )
end

function TooltipManager:_hide()
    self._current = nil
    if self._tooltip then
        self._tooltip.Visible = false
    end
end

function TooltipManager:Destroy()
    self._maid:Clean()
    if self._tooltip then self._tooltip:Destroy() end
end

-- Global ref ( set by Library._init )
TooltipManagerGlobal = nil

--==============================================================
-- SECTION 24: NOTIFY MANAGER
--==============================================================

local NotifyManager = {}
NotifyManager.__index = NotifyManager
NotifyManager._type = "NotifyManager"

function NotifyManager.new( rootGui: Instance )
    local self = setmetatable( {}, NotifyManager )
    self._rootGui = rootGui
    self._zones = {
        TopRight = {}, TopLeft = {}, BottomRight = {}, BottomLeft = {},
        TopCenter = {}, BottomCenter = {},
    }
    self._maxPerZone = 5
    self._maid = Maid.new()
    return self
end

local function getZonePosition( zone: string, idx: number, notifHeight: number ): UDim2
    local yOff = 16 + ( idx - 1 ) * ( notifHeight + 8 )
    if zone == "TopRight" then
        return UDim2.new( 1, -320, 0, yOff )
    elseif zone == "TopLeft" then
        return UDim2.new( 0, 16, 0, yOff )
    elseif zone == "BottomRight" then
        return UDim2.new( 1, -320, 1, -yOff - notifHeight )
    elseif zone == "BottomLeft" then
        return UDim2.new( 0, 16, 1, -yOff - notifHeight )
    elseif zone == "TopCenter" then
        return UDim2.new( 0.5, -150, 0, yOff )
    elseif zone == "BottomCenter" then
        return UDim2.new( 0.5, -150, 1, -yOff - notifHeight )
    end
    return UDim2.new( 1, -320, 0, yOff )
end

function NotifyManager:Show( config: any )
    local theme = ThemeManager.get()
    local zone = config.Position or "TopRight"
    local zoneList = self._zones[ zone ]
    if not zoneList then
        zone = "TopRight"
        zoneList = self._zones[ zone ]
    end
    if #zoneList >= self._maxPerZone then
        -- Dismiss oldest
        local oldest = zoneList[ 1 ]
        if oldest and oldest._dismiss then
            oldest:_dismiss()
        end
    end

    local width = 304
    local height = 64
    local notif = makeFrame( self._rootGui, {
        Name = "Notify",
        Size = UDim2.fromOffset( width, height ),
        Position = getZonePosition( zone, #zoneList + 1, height ),
        BackgroundColor3 = theme.Background_Card,
        BackgroundTransparency = theme.Transparency_Notification,
        ZIndex = 80,
    } )
    addCorner( notif, theme.Corner_Medium )
    addStroke( notif, 1, theme.Border_Default, 0 )

    -- Type color
    local typeColor, typeIcon, typeBg
    local ntype = config.Type or "Info"
    if ntype == "Success" then
        typeColor = theme.State_Success_Primary
        typeBg = theme.State_Success_Background
        typeIcon = getIcon( "check_circle" )
    elseif ntype == "Warning" then
        typeColor = theme.State_Warning_Primary
        typeBg = theme.State_Warning_Background
        typeIcon = getIcon( "warning" )
    elseif ntype == "Error" then
        typeColor = theme.State_Error_Primary
        typeBg = theme.State_Error_Background
        typeIcon = getIcon( "error" )
    elseif ntype == "Info" then
        typeColor = theme.State_Info_Primary
        typeBg = theme.State_Info_Background
        typeIcon = getIcon( "info" )
    else
        -- Custom
        typeColor = theme.Accent_Primary
        typeBg = theme.Background_Card
        typeIcon = config.Icon and getIcon( config.Icon ) or getIcon( "info" )
    end

    -- Accent line ( left or top )
    local accent = makeFrame( notif, {
        Name = "Accent",
        Size = UDim2.new( 1, 0, 0, 2 ),
        BackgroundColor3 = typeColor,
        BackgroundTransparency = 0,
    } )
    addGradient( accent, ColorSequence.new( theme.Accent_Primary,
                                            theme.Accent_Hover ), 0 )

    -- Icon
    local icon = makeLabel( notif, {
        Name = "Icon",
        Size = UDim2.fromOffset( 24, 24 ),
        Position = UDim2.fromOffset( 12, 14 ),
        Font = theme.Font_Main,
        TextColor3 = typeColor,
        TextSize = 18,
        Text = typeIcon,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
    } )

    -- Title
    local title = makeLabel( notif, {
        Name = "Title",
        Size = UDim2.new( 1, -80, 0, 18 ),
        Position = UDim2.fromOffset( 44, 10 ),
        Font = theme.Font_Heading,
        TextColor3 = theme.Text_Primary,
        TextSize = theme.Size_Body,
        Text = config.Title or "",
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    } )

    -- Description
    local desc = makeLabel( notif, {
        Name = "Description",
        Size = UDim2.new( 1, -80, 0, 28 ),
        Position = UDim2.fromOffset( 44, 28 ),
        Font = theme.Font_Body,
        TextColor3 = theme.Text_Secondary,
        TextSize = theme.Size_Caption,
        Text = config.Description or "",
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
    } )

    -- Close button
    local closeBtn = makeButton( notif, {
        Name = "Close",
        Size = UDim2.fromOffset( 20, 20 ),
        Position = UDim2.new( 1, -28, 0, 8 ),
        BackgroundTransparency = 1,
        Text = getIcon( "close" ),
        Font = theme.Font_Main,
        TextColor3 = theme.Text_Tertiary,
        TextSize = 12,
        AutoButtonColor = false,
    } )

    -- Progress bar
    local progressBg = makeFrame( notif, {
        Name = "ProgressBg",
        Size = UDim2.new( 1, 0, 0, 2 ),
        Position = UDim2.fromOffset( 0, height - 2 ),
        BackgroundColor3 = theme.Border_Subtle,
        BackgroundTransparency = 0.3,
    } )
    local progress = makeFrame( progressBg, {
        Name = "Progress",
        Size = UDim2.new( 1, 0, 1, 0 ),
        BackgroundColor3 = typeColor,
        BackgroundTransparency = 0,
    } )
    addCorner( progress, UDim.new( 0, 0 ) )

    -- Wrap in a Lua table for tracking
    local entry = {
        _notif = notif,
        _dismiss = nil,
        _zone = zone,
    }
    table.insert( zoneList, entry )

    local duration = config.Duration or 4
    local function dismiss()
        if entry._dismissed then return end
        entry._dismissed = true
        local i = table.find( zoneList, entry )
        if i then table.remove( zoneList, i ) end
        Animate( notif, {
            BackgroundTransparency = 1,
            Position = UDim2.new( notif.Position.X.Scale,
                notif.Position.X.Offset + 20,
                notif.Position.Y.Scale, notif.Position.Y.Offset ),
        }, theme.Anim_Fast, Enum.EasingStyle.Quad, Enum.EasingDirection.In ):Play()
        task.delay( theme.Anim_Fast, function()
            notif:Destroy()
        end )
        -- Re-position remaining
        for i2, e in ipairs( zoneList ) do
            if e._notif and e._notif.Parent then
                Animate( e._notif, {
                    Position = getZonePosition( zone, i2, height ),
                }, theme.Anim_Fast, Enum.EasingStyle.Quad, Enum.EasingDirection.Out ):Play()
            end
        end
        if config.OnDismiss then pcall( config.OnDismiss ) end
    end
    entry._dismiss = dismiss

    closeBtn.MouseButton1Click:Connect( dismiss )
    notif.MouseEnter:Connect( function()
        -- Pause: cancel tween ( we don't actually pause; we just extend a tiny bit )
    end )
    notif.MouseLeave:Connect( function()
        -- Resume
    end )
    notif.MouseButton1Click:Connect( function()
        if config.OnClick then pcall( config.OnClick ) end
    end )

    -- Animate in
    notif.BackgroundTransparency = 1
    notif.Position = UDim2.new( notif.Position.X.Scale,
                                notif.Position.X.Offset + 40,
                                notif.Position.Y.Scale,
                                notif.Position.Y.Offset )
    Animate( notif, {
        BackgroundTransparency = theme.Transparency_Notification,
        Position = getZonePosition( zone, #zoneList, height ),
    }, theme.Anim_Normal, Enum.EasingStyle.Quart, Enum.EasingDirection.Out ):Play()

    -- Progress bar animation
    if duration > 0 then
        Animate( progress, {
            Size = UDim2.new( 0, 0, 1, 0 ),
        }, duration, Enum.EasingStyle.Linear, Enum.EasingDirection.In ):Play()
        task.delay( duration, function()
            dismiss()
        end )
    end

    if config.OnDismiss then pcall( config.OnDismiss ) end
end

function NotifyManager:Destroy()
    self._maid:Clean()
end

--==============================================================
-- SECTION 25: KEYBIND LIST MANAGER
--==============================================================

local KeybindListManager = {}
KeybindListManager.__index = KeybindListManager
KeybindListManager._type = "KeybindListManager"

function KeybindListManager.new( rootGui: Instance )
    local self = setmetatable( {}, KeybindListManager )
    self._rootGui = rootGui
    self._items = {}
    self._visible = true
    self._maid = Maid.new()
    self:_build()
    return self
end

function KeybindListManager:_build()
    local theme = ThemeManager.get()
    local container = makeFrame( self._rootGui, {
        Name = "KeybindList",
        Size = UDim2.fromOffset( 220, 0 ),
        Position = UDim2.new( 1, -236, 0, 16 ),
        BackgroundColor3 = theme.Background_Card,
        BackgroundTransparency = theme.Transparency_Popover,
        AutomaticSize = Enum.AutomaticSize.Y,
    } )
    addCorner( container, theme.Corner_Medium )
    addStroke( container, 1, theme.Border_Default, 0 )
    self._container = container

    local header = makeFrame( container, {
        Name = "Header",
        Size = UDim2.new( 1, 0, 0, 32 ),
        BackgroundTransparency = 1,
    } )
    local title = makeLabel( header, {
        Size = UDim2.new( 1, -32, 1, 0 ),
        Position = UDim2.fromOffset( 12, 0 ),
        Font = theme.Font_Heading,
        TextColor3 = theme.Text_Primary,
        TextSize = theme.Size_BodySmall,
        Text = "Keybind List (0)",
        TextXAlignment = Enum.TextXAlignment.Left,
    } )
    self._title = title
    local close = makeButton( header, {
        Name = "Close",
        Size = UDim2.fromOffset( 20, 20 ),
        Position = UDim2.new( 1, -26, 0, 6 ),
        BackgroundTransparency = 1,
        Text = getIcon( "close" ),
        Font = theme.Font_Main,
        TextColor3 = theme.Text_Tertiary,
        TextSize = 12,
        AutoButtonColor = false,
    } )
    self._close = close

    local list = makeFrame( container, {
        Name = "Items",
        Size = UDim2.new( 1, 0, 0, 0 ),
        Position = UDim2.fromOffset( 0, 32 ),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
    } )
    addList( list, Enum.FillDirection.Vertical, UDim.new( 0, 4 ),
             Enum.HorizontalAlignment.Stretch, Enum.VerticalAlignment.Top )
    local pad = Instance.new( "UIPadding" )
    pad.PaddingLeft = UDim.new( 0, 8 )
    pad.PaddingRight = UDim.new( 0, 8 )
    pad.PaddingBottom = UDim.new( 0, 8 )
    pad.Parent = list
    self._list = list

    self._close.MouseButton1Click:Connect( function()
        self:Hide()
    end )
end

function KeybindListManager:Register( keybindComp: any, name: string )
    local entry = { name = name, comp = keybindComp }
    table.insert( self._items, entry )
    self:_rebuild()
end

function KeybindListManager:Unregister( name: string )
    for i, e in ipairs( self._items ) do
        if e.name == name then
            table.remove( self._items, i )
            break
        end
    end
    self:_rebuild()
end

function KeybindListManager:_rebuild()
    -- Clear list
    for _, c in ipairs( self._list:GetChildren() ) do
        if c:IsA( "GuiObject" ) then c:Destroy() end
    end
    local theme = ThemeManager.get()
    for _, e in ipairs( self._items ) do
        local comp = e.comp
        local keyText = "None"
        if comp._key then
            keyText = comp:_formatKey( comp._key )
        end
        local item = makeFrame( self._list, {
            Size = UDim2.new( 1, 0, 0, 22 ),
            BackgroundTransparency = 1,
        } )
        local mode = makeLabel( item, {
            Size = UDim2.new( 0, 60, 1, 0 ),
            Font = theme.Font_Mono,
            TextColor3 = theme.Text_Tertiary,
            TextSize = theme.Size_Caption,
            Text = "[" .. ( comp._mode or "Toggle" ) .. "]",
            TextXAlignment = Enum.TextXAlignment.Left,
        } )
        local nameLbl = makeLabel( item, {
            Size = UDim2.new( 1, -130, 1, 0 ),
            Position = UDim2.fromOffset( 64, 0 ),
            Font = theme.Font_Body,
            TextColor3 = theme.Text_Secondary,
            TextSize = theme.Size_Caption,
            Text = e.name,
            TextXAlignment = Enum.TextXAlignment.Left,
        } )
        local keyLbl = makeLabel( item, {
            Size = UDim2.new( 0, 50, 1, 0 ),
            Position = UDim2.new( 1, -54, 0, 0 ),
            Font = theme.Font_Mono,
            TextColor3 = keyText == "None" and theme.Text_Quaternary or theme.Accent_Primary,
            TextSize = theme.Size_Caption,
            Text = keyText,
            TextXAlignment = Enum.TextXAlignment.Right,
        } )
    end
    self._title.Text = "Keybind List (" .. #self._items .. ")"
end

function KeybindListManager:Show()
    self._container.Visible = true
end

function KeybindListManager:Hide()
    self._container.Visible = false
end

function KeybindListManager:Toggle()
    self._container.Visible = not self._container.Visible
end

function KeybindListManager:Destroy()
    self._maid:Clean()
end

-- Global ref
KeybindListManagerGlobal = nil

--==============================================================
-- SECTION 26: MODAL MANAGER
--==============================================================

local ModalManager = {}
ModalManager.__index = ModalManager
ModalManager._type = "ModalManager"

function ModalManager.new( rootGui: Instance )
    local self = setmetatable( {}, ModalManager )
    self._rootGui = rootGui
    self._maid = Maid.new()
    self._current = nil
    return self
end

function ModalManager:Show( config: any )
    -- Dismiss any existing
    if self._current then
        self:_dismiss()
    end
    local theme = ThemeManager.get()

    local overlay = makeFrame( self._rootGui, {
        Name = "ModalOverlay",
        Size = UDim2.fromScale( 1, 1 ),
        BackgroundColor3 = theme.Background_Overlay,
        BackgroundTransparency = theme.Transparency_Overlay,
        ZIndex = 90,
    } )

    local dialog = makeFrame( overlay, {
        Name = "ModalDialog",
        Size = UDim2.fromOffset( 380, 160 ),
        Position = UDim2.fromScale( 0.5, 0.5 ),
        AnchorPoint = Vector2.new( 0.5, 0.5 ),
        BackgroundColor3 = theme.Background_Card,
        BackgroundTransparency = 0,
    } )
    addCorner( dialog, theme.Corner_Large )
    addStroke( dialog, 1, theme.Border_Default, 0 )

    local title = makeLabel( dialog, {
        Name = "Title",
        Size = UDim2.new( 1, -32, 0, 28 ),
        Position = UDim2.fromOffset( 16, 12 ),
        Font = theme.Font_Heading,
        TextColor3 = theme.Text_Primary,
        TextSize = theme.Size_H3,
        Text = config.Title or "",
        TextXAlignment = Enum.TextXAlignment.Left,
    } )

    local body = makeLabel( dialog, {
        Name = "Body",
        Size = UDim2.new( 1, -32, 0, 60 ),
        Position = UDim2.fromOffset( 16, 44 ),
        Font = theme.Font_Body,
        TextColor3 = theme.Text_Secondary,
        TextSize = theme.Size_Body,
        Text = config.Body or "",
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
    } )

    -- Buttons
    local btnsContainer = makeFrame( dialog, {
        Name = "Buttons",
        Size = UDim2.new( 1, -32, 0, 32 ),
        Position = UDim2.fromOffset( 16, 116 ),
        BackgroundTransparency = 1,
    } )
    addList( btnsContainer, Enum.FillDirection.Horizontal, UDim.new( 0, 8 ),
             Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center )

    self._overlay = overlay
    self._dialog = dialog
    self._dismissable = config.Dismissible ~= false

    local function dismiss()
        self:_dismiss()
    end

    for _, b in ipairs( config.Buttons or {} ) do
        local btn = makeButton( btnsContainer, {
            Size = UDim2.fromOffset( 90, 32 ),
            BackgroundColor3 = b.Style == "Danger"
                and theme.State_Error_Primary
                or b.Style == "Primary"
                and theme.Accent_Primary
                or theme.Background_Input,
            BackgroundTransparency = 0,
            Text = b.Text or "OK",
            Font = theme.Font_Heading,
            TextColor3 = ( b.Style == "Danger" or b.Style == "Primary" )
                and Color3.fromRGB( 255, 255, 255 )
                or theme.Text_Primary,
            TextSize = theme.Size_BodySmall,
            AutoButtonColor = false,
        } )
        addCorner( btn, theme.Corner_Small )
        btn.MouseButton1Click:Connect( function()
            if b.Callback then pcall( b.Callback ) end
            dismiss()
        end )
    end

    -- Click on overlay = dismiss
    if config.Dismissible ~= false then
        overlay.InputBegan:Connect( function( input )
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                local mp = UserInputService:GetMouseLocation()
                local inset = UserInputService:GetGuiInset()
                local dp = dialog.AbsolutePosition
                local ds = dialog.AbsoluteSize
                if mp.X - inset.X < dp.X or mp.X - inset.X > dp.X + ds.X
                   or mp.Y - inset.Y < dp.Y or mp.Y - inset.Y > dp.Y + ds.Y then
                    dismiss()
                end
            end
        end )
    end

    -- Animate in
    overlay.BackgroundTransparency = 1
    dialog.Size = UDim2.fromOffset( 380, 0 )
    Animate( overlay, {
        BackgroundTransparency = theme.Transparency_Overlay,
    }, theme.Anim_Normal ):Play()
    Animate( dialog, {
        Size = UDim2.fromOffset( 380, 160 ),
    }, theme.Anim_Normal, Enum.EasingStyle.Back, Enum.EasingDirection.Out ):Play()
end

function ModalManager:_dismiss()
    if not self._overlay then return end
    local theme = ThemeManager.get()
    Animate( self._overlay, {
        BackgroundTransparency = 1,
    }, theme.Anim_Fast ):Play()
    Animate( self._dialog, {
        Size = UDim2.fromOffset( 380, 0 ),
    }, theme.Anim_Fast, Enum.EasingStyle.Back, Enum.EasingDirection.In ):Play()
    task.delay( theme.Anim_Fast, function()
        if self._overlay then
            self._overlay:Destroy()
            self._overlay = nil
            self._dialog = nil
        end
    end )
end

function ModalManager:Destroy()
    self._maid:Clean()
end

--==============================================================
-- SECTION 27: STATUS BAR MANAGER
--==============================================================

local StatusBarManager = {}
StatusBarManager.__index = StatusBarManager
StatusBarManager._type = "StatusBarManager"

function StatusBarManager.new( rootGui: Instance )
    local self = setmetatable( {}, StatusBarManager )
    self._rootGui = rootGui
    self._items = {}
    self._maid = Maid.new()
    self._updateConn = nil
    self:_build()
    return self
end

function StatusBarManager:_build()
    -- Container created on demand in :Init( config )
    self._container = nil
end

function StatusBarManager:Init( config: any )
    local theme = ThemeManager.get()
    if self._container then
        self._container:Destroy()
    end
    local pos = config.Position or "Top"
    local container = makeFrame( self._rootGui, {
        Name = "StatusBar",
        Size = UDim2.new( 1, 0, 0, 28 ),
        Position = pos == "Top" and UDim2.fromOffset( 0, 0 )
                                   or UDim2.fromOffset( 0, -28 ),
        BackgroundColor3 = theme.Background_Panel,
        BackgroundTransparency = 0.7,
        ZIndex = 70,
    } )
    if pos == "Bottom" then
        container.Position = UDim2.new( 0, 0, 1, -28 )
    end
    addList( container, Enum.FillDirection.Horizontal, UDim.new( 0, 0 ),
             Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center )

    self._container = container
    self._items = {}
    self._itemLabels = {}

    for i, item in ipairs( config.Items or {} ) do
        local entry = makeFrame( container, {
            Name = "Item_" .. tostring( i ),
            Size = UDim2.fromOffset( 140, 24 ),
            BackgroundTransparency = 1,
            LayoutOrder = i,
        } )
        local pad = Instance.new( "UIPadding" )
        pad.PaddingLeft = UDim.new( 0, 8 )
        pad.PaddingRight = UDim.new( 0, 8 )
        pad.Parent = entry
        local icon = makeLabel( entry, {
            Size = UDim2.fromOffset( 16, 16 ),
            Position = UDim2.fromOffset( 6, 4 ),
            Font = theme.Font_Main,
            TextColor3 = item.Color or theme.Accent_Primary,
            TextSize = 12,
            Text = getIcon( item.Icon or "info" ),
            TextXAlignment = Enum.TextXAlignment.Center,
            TextYAlignment = Enum.TextYAlignment.Center,
        } )
        local lbl = makeLabel( entry, {
            Size = UDim2.new( 1, -24, 1, 0 ),
            Position = UDim2.fromOffset( 24, 0 ),
            Font = theme.Font_Body,
            TextColor3 = theme.Text_Secondary,
            TextSize = theme.Size_Caption,
            Text = item.Value or item.Label or "",
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Center,
        } )
        if i < #( config.Items or {} ) then
            local sep = makeFrame( container, {
                Size = UDim2.fromOffset( 1, 16 ),
                BackgroundColor3 = theme.Divider,
                BackgroundTransparency = theme.Transparency_Divider,
                LayoutOrder = i + 0.5,
            } )
        end
        self._itemLabels[ item.Label ] = lbl
        table.insert( self._items, item )
    end

    -- Dynamic update loop
    if self._updateConn then self._updateConn:Disconnect() end
    self._updateConn = RunService.Heartbeat:Connect( function()
        for _, item in ipairs( self._items ) do
            if item.Dynamic and item.UpdateFn then
                local v = item.UpdateFn()
                if self._itemLabels[ item.Label ] and v then
                    if self._itemLabels[ item.Label ].Text ~= v then
                        self._itemLabels[ item.Label ].Text = v
                    end
                end
            end
        end
    end )
    self._maid:GiveTask( self._updateConn )
end

function StatusBarManager:UpdateValue( label: string, value: string )
    if self._itemLabels[ label ] then
        self._itemLabels[ label ].Text = value
    end
end

function StatusBarManager:Destroy()
    self._maid:Clean()
    if self._container then self._container:Destroy() end
end

--==============================================================
-- SECTION 28: PERSISTENCE MANAGER
--==============================================================

local PersistenceManager = {}
PersistenceManager.__index = PersistenceManager
PersistenceManager._type = "PersistenceManager"

function PersistenceManager.new( key: string? )
    local self = setmetatable( {}, PersistenceManager )
    self._key = key or "Ignite_Save"
    self._flags = {}
    return self
end

function PersistenceManager:Register( flag: string, comp: any )
    self._flags[ flag ] = comp
end

function PersistenceManager:Serialize(): string
    local data = {}
    for flag, comp in pairs( self._flags ) do
        if not comp._destroyed then
            local v = comp:GetValue()
            if typeof( v ) == "Color3" then
                data[ flag ] = { __type = "Color3", hex = Utils.colorToHex( v ) }
            elseif typeof( v ) == "table" then
                data[ flag ] = { __type = "table", value = v }
            elseif typeof( v ) == "EnumItem" then
                data[ flag ] = { __type = "Enum", enum = tostring( v ) }
            else
                data[ flag ] = v
            end
        end
    end
    return HttpService:JSONEncode( data )
end

function PersistenceManager:Deserialize( json: string )
    local ok, data = pcall( function()
        return HttpService:JSONDecode( json )
    end )
    if not ok or typeof( data ) ~= "table" then return end
    for flag, v in pairs( data ) do
        local comp = self._flags[ flag ]
        if comp and not comp._destroyed then
            if typeof( v ) == "table" and v.__type then
                if v.__type == "Color3" then
                    pcall( function() comp:SetValue( Utils.hexToColor( v.hex ) ) end )
                elseif v.__type == "table" then
                    pcall( function() comp:SetValue( v.value ) end )
                elseif v.__type == "Enum" then
                    -- Parse "Enum.KeyCode.B" -> Enum.KeyCode.B
                    local enumType, enumVal = tostring( v.enum ):match( "Enum%.(.+)%.(.+)" )
                    if enumType and enumVal then
                        local ok2, enumItem = pcall( function()
                            return Enum[ enumType ][ enumVal ]
                        end )
                        if ok2 and enumItem then
                            pcall( function() comp:SetValue( enumItem ) end )
                        end
                    end
                end
            else
                pcall( function() comp:SetValue( v ) end )
            end
        end
    end
end

function PersistenceManager:Save( name: string? )
    local fname = self:_fileName( name )
    local json = self:Serialize()
    if type( writefile ) == "function" then
        pcall( writefile, fname, json )
    else
        -- Fallback: store in getgenv
        if type( getgenv ) == "function" then
            local g = getgenv()
            g[ fname ] = json
        end
    end
end

function PersistenceManager:Load( name: string? )
    local fname = self:_fileName( name )
    local content
    if type( readfile ) == "function" then
        local ok, c = pcall( readfile, fname )
        if ok then content = c end
    end
    if not content and type( getgenv ) == "function" then
        local g = getgenv()
        content = g[ fname ]
    end
    if content then
        self:Deserialize( content )
    end
end

function PersistenceManager:Delete( name: string? )
    local fname = self:_fileName( name )
    if type( delfile ) == "function" then
        pcall( delfile, fname )
    elseif type( getgenv ) == "function" then
        local g = getgenv()
        g[ fname ] = nil
    end
end

function PersistenceManager:List(): any
    if type( listfiles ) == "function" then
        local files = listfiles()
        local out = {}
        for _, f in ipairs( files ) do
            local base = f:match( "([^/\\]+)$" )
            if base and base:sub( 1, #self._key ) == self._key then
                table.insert( out, base:sub( #self._key + 2, -6 ) )
            end
        end
        return out
    end
    return {}
end

function PersistenceManager:_fileName( name: string? ): string
    return self._key .. "_" .. ( name or "default" ) .. ".json"
end

--==============================================================
-- SECTION 29: LIBRARY SINGLETON ( PUBLIC API )
--==============================================================

local Library = {}
Library.__index = Library
Library._type = "Library"
Library._initialized = false
Library._instances = {}
Library._flags = {}
Library._version = "1.0.0"

-- Expose themes & icons on Library for public access.
Library.Themes = {
    Dark   = DarkTheme,
    Light  = LightTheme,
    Amoled = AmoledTheme,
}
Library.Icons = Icons
Library.Easing = Easing

-- Component references ( populated below )
Library.Window       = Window
Library.Tab          = Tab
Library.Subsection   = Subsection
Library.Section      = Section
Library.Component    = Component
Library.Toggle       = Toggle
Library.Slider       = Slider
Library.Dropdown     = Dropdown
Library.Keybind      = Keybind
Library.ColorPicker  = ColorPicker
Library.Input        = Input
Library.Button       = Button
Library.Label        = Label
Library.Divider      = Divider
Library.Signal       = Signal
Library.Maid         = Maid
Library.Utils        = Utils

--==============================================================
-- Internal: singleton initialiser
--==============================================================

function Library._init()
    if Library._initialized then return end
    Library._initialized = true

    -- Root ScreenGui for the library ( holds overlays only; windows have their own ScreenGui )
    local overlayGui = Instance.new( "ScreenGui" )
    overlayGui.Name = "Ignite_Overlays_" .. Utils.uid()
    overlayGui.DisplayOrder = 200
    overlayGui.ResetOnSpawn = false
    overlayGui.IgnoreGuiInset = true
    overlayGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    Utils.protectGui( overlayGui )
    overlayGui.Parent = Utils.getGuiParent()
    Library._overlayGui = overlayGui

    -- Popover GUI ( for dropdown / colorpicker popovers )
    local popoverGui = Instance.new( "ScreenGui" )
    popoverGui.Name = "Ignite_Popovers_" .. Utils.uid()
    popoverGui.DisplayOrder = 250
    popoverGui.ResetOnSpawn = false
    popoverGui.IgnoreGuiInset = true
    popoverGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    Utils.protectGui( popoverGui )
    popoverGui.Parent = Utils.getGuiParent()
    Library._popoverGui = popoverGui

    -- Modal GUI ( highest display order after tooltips )
    local modalGui = Instance.new( "ScreenGui" )
    modalGui.Name = "Ignite_Modals_" .. Utils.uid()
    modalGui.DisplayOrder = 280
    modalGui.ResetOnSpawn = false
    modalGui.IgnoreGuiInset = true
    modalGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    Utils.protectGui( modalGui )
    modalGui.Parent = Utils.getGuiParent()
    Library._modalGui = modalGui

    -- Tooltip GUI ( highest display order, always on top )
    local tooltipGui = Instance.new( "ScreenGui" )
    tooltipGui.Name = "Ignite_Tooltips_" .. Utils.uid()
    tooltipGui.DisplayOrder = 300
    tooltipGui.ResetOnSpawn = false
    tooltipGui.IgnoreGuiInset = true
    tooltipGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    Utils.protectGui( tooltipGui )
    tooltipGui.Parent = Utils.getGuiParent()
    Library._tooltipGui = tooltipGui

    -- Persistence manager ( default key; can be overridden per-window )
    Library._persistence = PersistenceManager.new( "Ignite_Save" )

    -- Initialise overlay managers
    Library._notifyManager   = NotifyManager.new( overlayGui )
    Library._keybindListMgr  = KeybindListManager.new( overlayGui )
    Library._modalManager    = ModalManager.new( modalGui )
    Library._statusBarMgr    = StatusBarManager.new( overlayGui )
    TooltipManagerGlobal     = TooltipManager.new( tooltipGui )
    KeybindListManagerGlobal = Library._keybindListMgr
    Library._tooltipManager  = TooltipManagerGlobal
end

--==============================================================
-- Internal: flag registration ( called by Section:Create* )
--==============================================================

function Library._registerFlag( flag: string, comp: any )
    Library._flags[ flag ] = comp
    if Library._persistence then
        Library._persistence:Register( flag, comp )
    end
end

--==============================================================
-- Public API
--==============================================================

-- Create a new top-level Window.
function Library:CreateWindow( config: any )
    if not Library._initialized then Library._init() end

    -- Apply theme override if provided.
    if config.Theme then
        ThemeManager.set( config.Theme )
    end
    if config.AccentOverride then
        ThemeManager.override( {
            Accent_Primary        = config.AccentOverride,
            Accent_Hover          = config.AccentOverride,
            Accent_GradientStart  = config.AccentOverride,
            Border_Active         = config.AccentOverride,
        } )
    end

    -- Persistent key for save/load ( if provided )
    if config.PersistentKey then
        Library._persistence._key = config.PersistentKey
    end

    local win = Window.new( config )
    table.insert( Library._instances, win )
    return win
end

-- Get current theme ( mutable; mutate then call :SetTheme to apply ).
function Library:GetTheme()
    return ThemeManager.get()
end

-- Set theme ( replaces current theme entirely ).
function Library:SetTheme( theme )
    ThemeManager.set( theme )
end

-- Override specific keys in current theme.
function Library:OverrideTheme( partial )
    ThemeManager.override( partial )
end

-- Deep-copy a theme ( useful for creating a custom variant ).
function Library:CopyTheme( theme )
    return Utils.deepCopy( theme or ThemeManager.get() )
end

-- Get the icon glyph for a known icon name.
function Library:GetIcon( name: string ): string
    return getIcon( name )
end

--==============================================================
-- Notify API
--==============================================================

function Library:Notify( config: any )
    if not Library._initialized then Library._init() end
    Library._notifyManager:Show( config )
end

function Library:NotifySuccess( title: string, desc: string, duration: number? )
    Library:Notify( {
        Title = title,
        Description = desc,
        Type = "Success",
        Duration = duration or 4,
    } )
end

function Library:NotifyWarning( title: string, desc: string, duration: number? )
    Library:Notify( {
        Title = title,
        Description = desc,
        Type = "Warning",
        Duration = duration or 4,
    } )
end

function Library:NotifyError( title: string, desc: string, duration: number? )
    Library:Notify( {
        Title = title,
        Description = desc,
        Type = "Error",
        Duration = duration or 5,
    } )
end

function Library:NotifyInfo( title: string, desc: string, duration: number? )
    Library:Notify( {
        Title = title,
        Description = desc,
        Type = "Info",
        Duration = duration or 4,
    } )
end

--==============================================================
-- Keybind list API
--==============================================================

function Library:ShowKeybindList()
    if not Library._keybindListMgr then return end
    Library._keybindListMgr:Show()
end

function Library:HideKeybindList()
    if not Library._keybindListMgr then return end
    Library._keybindListMgr:Hide()
end

function Library:ToggleKeybindList()
    if not Library._keybindListMgr then return end
    Library._keybindListMgr:Toggle()
end

function Library:AddKeybindToList( config: any )
    if not Library._keybindListMgr then return end
    -- Create an "ad-hoc" keybind component-like table that the manager can render.
    local fake = {
        _key  = config.Key,
        _mode = config.Mode or "Always",
        _formatKey = function( _, k )
            if not k then return "None" end
            return tostring( k ):gsub( "Enum.KeyCode.", "" )
        end,
    }
    Library._keybindListMgr:Register( fake, config.Name or "Keybind" )
end

function Library:RemoveKeybindFromList( name: string )
    if not Library._keybindListMgr then return end
    Library._keybindListMgr:Unregister( name )
end

--==============================================================
-- Modal API
--==============================================================

function Library:ShowModal( config: any )
    if not Library._modalManager then return end
    Library._modalManager:Show( config )
end

function Library:DismissModal()
    if not Library._modalManager then return end
    Library._modalManager:_dismiss()
end

--==============================================================
-- Status bar API
--==============================================================

function Library:CreateStatusBar( config: any )
    if not Library._statusBarMgr then return end
    Library._statusBarMgr:Init( config )
    return {
        UpdateValue = function( _, label, value )
            Library._statusBarMgr:UpdateValue( label, value )
        end,
        Destroy = function()
            Library._statusBarMgr:Destroy()
        end,
    }
end

--==============================================================
-- Persistence API
--==============================================================

function Library:SaveConfig( name: string? )
    if not Library._persistence then return end
    Library._persistence:Save( name )
end

function Library:LoadConfig( name: string? )
    if not Library._persistence then return end
    Library._persistence:Load( name )
end

function Library:DeleteConfig( name: string? )
    if not Library._persistence then return end
    Library._persistence:Delete( name )
end

function Library:ListConfigs()
    if not Library._persistence then return {} end
    return Library._persistence:List()
end

function Library:CreateConfigButton( section: any, config: any )
    if not section then return end
    local nameBox
    local nameInput = section:CreateInput( {
        Name = "Config Name",
        Default = config.ConfigName or "default",
        Placeholder = "Enter config name...",
        Flag = "Config_Name",
    } )
    section:CreateButton( {
        Name = "Save Config",
        Style = "Primary",
        Callback = function()
            Library:SaveConfig( nameInput:GetValue() )
            Library:NotifySuccess( "Saved", "Config '" .. nameInput:GetValue() .. "' saved" )
        end,
    } )
    section:CreateButton( {
        Name = "Load Config",
        Callback = function()
            Library:LoadConfig( nameInput:GetValue() )
            Library:NotifySuccess( "Loaded", "Config '" .. nameInput:GetValue() .. "' loaded" )
        end,
    } )
    section:CreateButton( {
        Name = "Delete Config",
        Style = "Danger",
        Callback = function()
            Library:DeleteConfig( nameInput:GetValue() )
            Library:NotifyWarning( "Deleted", "Config '" .. nameInput:GetValue() .. "' deleted" )
        end,
    } )
    return nameInput
end

--==============================================================
-- Misc utilities
--==============================================================

-- Get a component by its flag ( useful for callbacks that need to
-- reach into another component without holding a direct reference ).
function Library:GetByFlag( flag: string )
    return Library._flags[ flag ]
end

-- Destroy all windows / clean up everything.
function Library:DestroyAll()
    for _, win in ipairs( Library._instances ) do
        if not win._destroyed then pcall( win.Destroy, win ) end
    end
    Library._instances = {}
    Library._flags = {}
    if Library._notifyManager then pcall( Library._notifyManager.Destroy, Library._notifyManager ) end
    if Library._keybindListMgr then pcall( Library._keybindListMgr.Destroy, Library._keybindListMgr ) end
    if Library._modalManager then pcall( Library._modalManager.Destroy, Library._modalManager ) end
    if Library._statusBarMgr then pcall( Library._statusBarMgr.Destroy, Library._statusBarMgr ) end
    if Library._tooltipManager then pcall( Library._tooltipManager.Destroy, Library._tooltipManager ) end
    if Library._overlayGui then pcall( function() Library._overlayGui:Destroy() end ) end
    if Library._popoverGui then pcall( function() Library._popoverGui:Destroy() end ) end
    if Library._modalGui then pcall( function() Library._modalGui:Destroy() end ) end
    if Library._tooltipGui then pcall( function() Library._tooltipGui:Destroy() end ) end
    Library._initialized = false
end

--==============================================================
-- Anti-detect: optional GUI renaming ( randomises instance names
-- to make pattern-based detection harder ).
--==============================================================

function Library:RandomiseNames()
    local function walk( inst )
        if inst:IsA( "Instance" ) then
            inst.Name = Utils.uid( "Ign" )
        end
        for _, c in ipairs( inst:GetChildren() ) do
            walk( c )
        end
    end
    for _, win in ipairs( Library._instances ) do
        if win._rootGui then walk( win._rootGui ) end
    end
    if Library._overlayGui then walk( Library._overlayGui ) end
    if Library._popoverGui then walk( Library._popoverGui ) end
end

--==============================================================
-- Convenience: build an executor-info string for the header.
--==============================================================

function Library:GetExecutorInfo(): string
    return Utils.getExecutorName()
end

--==============================================================
-- Initialisation on first require
--==============================================================

Library._init()

--==============================================================
-- SECTION 30: RETURN PUBLIC API
--==============================================================

return Library
