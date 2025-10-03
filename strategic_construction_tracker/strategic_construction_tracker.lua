if not RmlUi then
    return
end

local widget = widget ---@type Widget
local WIDGET_NAME = "Strategic Construction Tracker"
local MODEL_NAME = "strategic_construction_tracker"
local RML_PATH = "luaui/rmlwidgets/strategic_construction_tracker/strategic_construction_tracker.rml"
local UPDATE_FREQUENCY = 30

function widget:GetInfo()
    return {
        name      = WIDGET_NAME,
        desc      = "Tracks important building construction",
        author    = "H7",
        date      = "2025",
        license   = "GNU GPL, v2 or later",
        layer     = 5,
        enabled   = true,
        handler   = true,
        api       = true,
    }
end



-- Important buildings/units to track
local TRACKED_BUILDINGS_LIST = {
    -- === COMMANDERS ===
    "armcom", "corcom", "legcom",
    "armdecom", "cordecom", "legdecom",

    -- === FUSION PLANTS ===
    "armfus", "corfus", "legfus",
    "armafus", "corafus", "legafus",

    -- === T2 LABORATORIES ===
    "armalab", "coralab", "legalab",
    "armavp", "coravp", "legavp",
    "armaap", "coraap", "legaap",
    "armasy", "corasy", "legasy",
    "armhalab", "corhalab", "leghalab",
    "armsalab", "corsalab", "legsalab",

    -- === LONG RANGE PLASMA CANNONS ===
    "armlrpc", "corlrpc", "leglrpc",

    -- === NUCLEAR MISSILE SILOS ===
    "armsilo", "corsilo", "legsilo",

    -- === EXPERIMENTAL GANTRIES ===
    "armshltx", "corshltx", "legshltx",
    "armshltxuw", "corshltxuw", "legshltxuw",

    -- === HEAVY ARTILLERY ===
    "armbrtha", "corint", "legbrtha",
    "armvulc", "corbuzz", "legvulc",

    -- === STRATEGIC DEFENSE ===
    "armamd", "corfmd", "legamd",
    "armanni", "cordoom", "leganni",

    -- === EXPERIMENTAL UNITS ===
    "armthor", "corkrog", "legthor",
    "armstar", "corshw", "legstar",

    -- === TACTICAL MISSILE LAUNCHERS ===
    "armemp", "cortron", "legemp",

    -- === RADAR JAMMERS & STEALTH ===
    "armjamt", "corjamt", "legjamt",

    -- === ADVANCED ENERGY CONVERSION ===
    "armmmkr", "cormmkr", "legmmkr",

    -- === FORTIFICATIONS ===
    "armfort", "corfort", "legfort",

    -- === SEAPLANE PLATFORMS ===
    "armplat", "corplat", "legplat",

    -- === AMPHIBIOUS COMPLEXES ===
    "armasp", "corasp", "legasp",

    -- === SPECIAL LEGION UNITS ===
    "leghive", "legaegis", "leganomaly",

    -- === OTHER STRATEGIC BUILDINGS ===
    "armgate", "corgate", "leggate",

    -- === ADDITIONAL STRATEGIC UNITS ===
    "armclaw", "cormaw", "armbanth", "corkarg", "armraz", "corsb",
}

local TRACKED_BUILDINGS = {}
for _, unitName in ipairs(TRACKED_BUILDINGS_LIST) do
    TRACKED_BUILDINGS[unitName] = true
end

-- Spring API shortcuts
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitTeam = Spring.GetUnitTeam
local spGetUnitPosition = Spring.GetUnitPosition
local spIsUnitAllied = Spring.IsUnitAllied
local spGetSpectatingState = Spring.GetSpectatingState
local spGetMyTeamID = Spring.GetMyTeamID
local spGetPlayerInfo = Spring.GetPlayerInfo
local spGetAllUnits = Spring.GetAllUnits

-- Load iconTypes
local iconTypes = VFS.Include("gamedata/icontypes.lua")

-- Widget state
local isSpectator = false
local fullView = false
local myTeamID = 0
local frameCounter = 0
local trackedConstructions = {}
local nextEntryID = 1


-- Position state
local widgetPosX = 50
local widgetPosY = 100

-- RMLui variables
local document
local dm_handle
local panelVisible = true
local collapsed = false


-- Widget state for drag operations
local widgetState = {
    isDragging = false,
    dragOffsetX = 0,
    dragOffsetY = 0
}

-- Position management functions
local function LoadPosition()
    local configString = Spring.GetConfigString("StrategicConstructionTracker_Position", "")
    if configString and configString ~= "" then
        local x, y = configString:match("^(%d+),(%d+)$")
        if x and y then
            widgetPosX = tonumber(x)
            widgetPosY = tonumber(y)
        end
    end
end

local function SavePosition()
    local configString = widgetPosX .. "," .. widgetPosY
    Spring.SetConfigString("StrategicConstructionTracker_Position", configString)
end

local function LoadCollapsedState()
    local configString = Spring.GetConfigString("StrategicConstructionTracker_Collapsed", "false")
    collapsed = (configString == "true")
end

local function SaveCollapsedState()
    Spring.SetConfigString("StrategicConstructionTracker_Collapsed", tostring(collapsed))
end

local function UpdateDocumentPosition()
    if document then
        local body = document:GetElementById("strategic-construction-tracker-widget")
        if body then
            body.style.left = widgetPosX .. "px"
            body.style.top = widgetPosY .. "px"
        end
    end
end


function widget:Initialize()
    Spring.Echo(WIDGET_NAME .. ": Initializing widget...")
    LoadPosition()
    LoadCollapsedState()

    myTeamID = Spring.GetMyTeamID()
    local spec, fullV = Spring.GetSpectatingState()
    isSpectator = spec
    fullView = fullV

    widget.forceGameFrame = true

    widget.rmlContext = RmlUi.GetContext("shared")
    if not widget.rmlContext then
        Spring.Echo(WIDGET_NAME .. ": ERROR - Failed to get RML context")
        return false
    end

    local initialModel = {
        collapsed = collapsed,
        collapse_symbol = collapsed and "+" or "−",
        teams = {},
        constructions = {size = 0}
    }

    dm_handle = widget.rmlContext:OpenDataModel(MODEL_NAME, initialModel)
    if not dm_handle then
        Spring.Echo(WIDGET_NAME .. ": ERROR - Failed to create data model '" .. MODEL_NAME .. "'")
        return false
    end

    Spring.Echo(WIDGET_NAME .. ": Data model created successfully")

    document = widget.rmlContext:LoadDocument(RML_PATH, widget)
    if not document then
        Spring.Echo(WIDGET_NAME .. ": ERROR - Failed to load document: " .. RML_PATH)
        widget:Shutdown()
        return false
    end

    document:ReloadStyleSheet()
    document:Show()

    UpdateDocumentPosition()

    Spring.Echo(WIDGET_NAME .. ": Widget initialized successfully")

    Scan()
    UpdateRMLuiData()

    return true
end

function widget:StartDrag(event)
    local mx, my = Spring.GetMouseState()
    local vsx, vsy = Spring.GetViewGeometry()

    widgetState.isDragging = true

    -- Calculate offset from widget position to mouse position
    -- Widget position is in CSS coordinates (top-down), but Spring mouse is bottom-up
    -- Convert widget CSS Y to Spring Y for proper offset calculation
    local springWidgetY = vsy - widgetPosY
    widgetState.dragOffsetX = mx - widgetPosX
    widgetState.dragOffsetY = my - springWidgetY

    return true
end

function widget:EndDrag(event)
    if widgetState.isDragging then
        widgetState.isDragging = false
        SavePosition()
    end
    return true
end

function widget:ToggleCollapsed(event)
    collapsed = not collapsed
    if dm_handle then
        dm_handle.collapsed = collapsed
        dm_handle.collapse_symbol = collapsed and "+" or "−"
    end
    SaveCollapsedState()
    return true
end


function widget:SelectConstruction(event)
    local element = event.current_element
    if not element then
        return false
    end

    -- Find the hidden unit-id span
    local unitIdSpan = element:GetElementsByTagName("span")[1]
    if not unitIdSpan then
        return false
    end

    local unitID = tonumber(unitIdSpan.inner_rml)
    if not unitID then
        return false
    end

    -- Direct lookup and camera movement
    local constructionData = trackedConstructions[unitID]
    if not constructionData or not constructionData.position then
        return false
    end

    local x, y, z = constructionData.position.x, constructionData.position.y, constructionData.position.z

    Spring.SetCameraTarget(x, y, z, 0.8)
    Spring.SelectUnitArray({unitID})

    return true
end

local function GetUnitDisplayName(unitDefID)
    local unitDef = UnitDefs[unitDefID]
    if not TRACKED_BUILDINGS[unitDef.name] then
        return nil
    end

    local displayName = Spring.I18N('units.names.' .. unitDef.name)
    if not displayName or displayName == "" or displayName == ('units.names.' .. unitDef.name) then
        displayName = unitDef.humanName or unitDef.name or "Unknown"
    end

    return displayName
end

function Scan()
    local allUnits = spGetAllUnits()
    for _, unitID in ipairs(allUnits) do
        local unitDefID = spGetUnitDefID(unitID)
        local unitDef = UnitDefs[unitDefID]
        local unitTeam = spGetUnitTeam(unitID)

        if unitDef and GetUnitDisplayName(unitDefID) and ShouldTrackUnit(unitID, unitTeam) then
            local _, _, _, _, buildProgress = spGetUnitHealth(unitID)
            if buildProgress and buildProgress < 1.0 then
                AddConstructionToTracker(unitID, unitDefID, unitTeam, nil)
            end
        end
    end
end

function AddConstructionToTracker(unitID, unitDefID, unitTeam, builderID)
    local unitDef = UnitDefs[unitDefID]
    if not unitDef then return end

    local unitName = GetUnitDisplayName(unitDefID)
    if not unitName then return end

    local _, _, _, _, buildProgress = spGetUnitHealth(unitID)
    if not buildProgress then return end

    local x, y, z = spGetUnitPosition(unitID)
    local teamColor = {Spring.GetTeamColor(unitTeam)}
    local teamName = GetTeamDisplayName(unitTeam)

    trackedConstructions[unitID] = {
        id = nextEntryID,
        unitDefID = unitDefID,
        unitName = unitName,
        team = unitTeam,
        teamName = teamName,
        teamColor = teamColor,
        position = {x = x, y = y, z = z},
        startTime = Spring.GetGameSeconds(),
        lastProgress = buildProgress,
        builderID = builderID
    }
    nextEntryID = nextEntryID + 1
end

function ShouldTrackUnit(unitID, unitTeam)
    if isSpectator and fullView then
        return true
    else
        return spIsUnitAllied(unitID)
    end
end

function GetTeamDisplayName(teamID)
    local playerList = Spring.GetPlayerList()
    for _, playerID in ipairs(playerList) do
        local playerName, _, isSpec, playerTeam = spGetPlayerInfo(playerID)
        if playerTeam == teamID and playerName and not isSpec then
            return playerName
        end
    end
    return "Team " .. teamID
end

function UpdateRMLuiData()
    if not dm_handle then return end

    dm_handle.collapsed = collapsed
    dm_handle.collapse_symbol = collapsed and "+" or "−"

    local teamGroups = {}
    local totalConstructions = 0

    for unitID, data in pairs(trackedConstructions) do
        totalConstructions = totalConstructions + 1
        data.unit_id = unitID
        data.unit_name = data.unitName
        data.unit_def_id = data.unitDefID
        local unitDef = UnitDefs[data.unitDefID]
        data.unit_internal_name = unitDef and unitDef.name or ""
        data.build_pic = unitDef and unitDef.buildPic or ""
        local iconTypeName = unitDef and unitDef.iconType or ""
        local iconData = iconTypes and iconTypes[iconTypeName]
        data.icon_path = iconData and iconData.bitmap or ""
        data.progress_percent = math.floor(data.lastProgress * 100)

        data.progress_squares = {}
        local filledSquares = math.floor(data.progress_percent / 10)
        for i = 1, 10 do
            if i <= filledSquares then
                data.progress_squares[i] = {is_filled = true}
            else
                data.progress_squares[i] = {is_filled = false}
            end
        end

        local r = math.floor(data.teamColor[1] * 255)
        local g = math.floor(data.teamColor[2] * 255)
        local b = math.floor(data.teamColor[3] * 255)

        data.team_color = string.format("rgb(%d,%d,%d)", r, g, b)

        if not teamGroups[data.team] then
            teamGroups[data.team] = {
                id = data.team,
                name = data.teamName,
                color = data.team_color,
                border_color = data.team_color,
                accent_color = data.team_color,
                constructions = {}
            }
        end

        table.insert(teamGroups[data.team].constructions, data)
    end

    -- Sort constructions within each team by progress
    for teamID, teamData in pairs(teamGroups) do
        table.sort(teamData.constructions, function(a, b)
            return a.lastProgress < b.lastProgress
        end)
    end

    local teamsArray = {}
    for teamID, teamData in pairs(teamGroups) do
        table.insert(teamsArray, teamData)
    end

    table.sort(teamsArray, function(a, b)
        return a.id < b.id
    end)

    dm_handle.teams = teamsArray
    dm_handle.constructions = {size = totalConstructions}

end

function widget:PlayerChanged(playerID)
    local spec, fullV = spGetSpectatingState()
    isSpectator = spec
    fullView = fullV
    myTeamID = spGetMyTeamID()

    trackedConstructions = {}
    Scan()
    UpdateRMLuiData()
end

function widget:UnitCreated(unitID, unitDefID, unitTeam, builderID)
    local unitDef = UnitDefs[unitDefID]
    if not unitDef or not GetUnitDisplayName(unitDefID) or not ShouldTrackUnit(unitID, unitTeam) then
        return
    end
    AddConstructionToTracker(unitID, unitDefID, unitTeam, builderID)
    UpdateRMLuiData()
end

function widget:UnitFinished(unitID, unitDefID, unitTeam)
    if trackedConstructions[unitID] then
        trackedConstructions[unitID] = nil
        UpdateRMLuiData()
    end
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
    if trackedConstructions[unitID] then
        trackedConstructions[unitID] = nil
        UpdateRMLuiData()
    end
end

function widget:GameFrame()
    frameCounter = frameCounter + 1
    if frameCounter >= UPDATE_FREQUENCY then
        frameCounter = 0
        UpdateConstructionProgress()
    end

    if widgetState.isDragging then
        local mx, my = Spring.GetMouseState()
        local newX = mx - widgetState.dragOffsetX
        local newY = my - widgetState.dragOffsetY
        local vsx, vsy = Spring.GetViewGeometry()
        local cssY = vsy - newY

        newX = math.max(0, math.min(newX, vsx - 130))
        cssY = math.max(0, math.min(cssY, vsy - 45))

        if math.abs(newX - widgetPosX) > 1 or math.abs(cssY - widgetPosY) > 1 then
            widgetPosX = newX
            widgetPosY = cssY
            UpdateDocumentPosition()
        end
    end
end

function UpdateConstructionProgress()
    local updated = false
    for unitID, data in pairs(trackedConstructions) do
        local health, maxHealth, _, _, buildProgress = spGetUnitHealth(unitID)
        if buildProgress then
            if buildProgress >= 1.0 then
                trackedConstructions[unitID] = nil
                updated = true
            else
                if math.abs(data.lastProgress - buildProgress) > 0.01 then
                    data.lastProgress = buildProgress
                    updated = true
                end
            end
        else
            trackedConstructions[unitID] = nil
            updated = true
        end
    end

    if updated then
        UpdateRMLuiData()
    end
end

function widget:Shutdown()
    Spring.Echo(WIDGET_NAME .. ": Shutting down widget...")


    -- Clean up data model
    if widget.rmlContext and dm_handle then
        widget.rmlContext:RemoveDataModel(MODEL_NAME)
        dm_handle = nil
    end

    -- Close document
    if document then
        document:Close()
        document = nil
    end

    widget.rmlContext = nil
    trackedConstructions = {}

    Spring.Echo(WIDGET_NAME .. ": Shutdown complete")
end