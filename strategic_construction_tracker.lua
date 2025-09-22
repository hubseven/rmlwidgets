function widget:GetInfo()
    return {
        name      = "Strategic Construction Tracker",
        desc      = "Tracks important building construction (LRPC, Nukes, etc)",
        author    = "H7",
        date      = "2025",
        license   = "MIT",
        layer     = 5,
        enabled   = true,
    }
end

-- Configuration
local PANEL_WIDTH = 280
local PANEL_MIN_HEIGHT = 45
local ENTRY_HEIGHT = 22
local TEAM_HEADER_HEIGHT = 22
local PLAYER_HEADER_HEIGHT = 18
local TITLE_BAR_HEIGHT = 25
local SPACING_UNIT = 4
local UPDATE_FREQUENCY = 30
local PANEL_PADDING = 8

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

local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitTeam = Spring.GetUnitTeam
local spGetUnitPosition = Spring.GetUnitPosition
local spIsUnitAllied = Spring.IsUnitAllied
local spGetSpectatingState = Spring.GetSpectatingState
local spGetMyTeamID = Spring.GetMyTeamID
local spGetPlayerInfo = Spring.GetPlayerInfo
local spSetCameraTarget = Spring.SetCameraTarget
local spGetAllUnits = Spring.GetAllUnits

local glColor = gl.Color
local glRect = gl.Rect
local glText = gl.Text
local glLineWidth = gl.LineWidth
local glBlending = gl.Blending
local glTexture = gl.Texture

local GL_SRC_ALPHA = GL.SRC_ALPHA
local GL_ONE_MINUS_SRC_ALPHA = GL.ONE_MINUS_SRC_ALPHA

local isSpectator = false
local fullView = false
local myTeamID = 0
local frameCounter = 0
local trackedConstructions = {}
local nextEntryID = 1

local mouseX, mouseY = 0, 0
local panelVisible = true
local panelX, panelY = 50, 50
local collapsed = false

local isDragging = false
local dragOffsetX, dragOffsetY = 0, 0
local clickedConstructionID = nil

function widget:Initialize()
    myTeamID = spGetMyTeamID()
    local spec, fullV = spGetSpectatingState()
    isSpectator = spec
    fullView = fullV
    
    local vsx, vsy = gl.GetViewSizes()
    if not panelX then panelX = 20 end
    if not panelY then panelY = 20 end
    
    local mx, my = Spring.GetMouseState()
    if mx and my then
        mouseX, mouseY = mx, my
    end
    
    Scan()
end

local function GetUnitDisplayName(unitDefID)
    local unitDef = UnitDefs[unitDefID]
    if not TRACKED_BUILDINGS[unitDef.name] then
        return nil
    end

    return Spring.I18N('units.names.' .. unitDef.name)
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

function widget:PlayerChanged(playerID)
    local spec, fullV = spGetSpectatingState()
    isSpectator = spec
    fullView = fullV
    myTeamID = spGetMyTeamID()
    
    trackedConstructions = {}
    Scan()
end

function widget:UnitCreated(unitID, unitDefID, unitTeam, builderID)
    local unitDef = UnitDefs[unitDefID]
    if not unitDef or not GetUnitDisplayName(unitDefID) or not ShouldTrackUnit(unitID, unitTeam) then
        return
    end
    AddConstructionToTracker(unitID, unitDefID, unitTeam, builderID)
end

function widget:UnitFinished(unitID, unitDefID, unitTeam)
    trackedConstructions[unitID] = nil
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
    trackedConstructions[unitID] = nil
end

// @todo limit frame rate
function widget:GameFrame()
    frameCounter = frameCounter + 1
    if frameCounter >= UPDATE_FREQUENCY then
        frameCounter = 0
        UpdateConstructionProgress()
    end
end

function UpdateConstructionProgress()
    for unitID, data in pairs(trackedConstructions) do
        local health, maxHealth, _, _, buildProgress = spGetUnitHealth(unitID)
        if buildProgress then
            if buildProgress >= 1.0 then
                trackedConstructions[unitID] = nil
            else
                data.lastProgress = buildProgress
            end
        else
            trackedConstructions[unitID] = nil
        end
    end
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

function widget:DrawScreen()
    if not panelVisible then return end
    
    local entryCount = 0
    for _ in pairs(trackedConstructions) do
        entryCount = entryCount + 1
    end
    
    DrawBARStylePanel(entryCount)
end

function DrawBARStylePanel(entryCount)
    local teamGroups = {}
    local teamCount = 0

    for unitID, data in pairs(trackedConstructions) do
        data.unitID = unitID
        if not teamGroups[data.team] then
            teamGroups[data.team] = {}
            teamCount = teamCount + 1
        end
        table.insert(teamGroups[data.team], data)
    end
    
    local actualHeight
    if collapsed then
        actualHeight = 30
    else
        local baseHeight = PANEL_MIN_HEIGHT + (entryCount * ENTRY_HEIGHT) + PANEL_PADDING
        local teamHeaderHeight = teamCount * (TEAM_HEADER_HEIGHT + SPACING_UNIT)
        local teamSeparatorHeight = math.max(0, teamCount * SPACING_UNIT)
        actualHeight = TITLE_BAR_HEIGHT + teamHeaderHeight + (entryCount * ENTRY_HEIGHT) + teamSeparatorHeight + PANEL_PADDING
    end
    
    glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
    
    glColor(0.05, 0.05, 0.05, 0.92)
    glRect(panelX, panelY, panelX + PANEL_WIDTH, panelY + actualHeight)
    
    glColor(0.2, 0.25, 0.3, 0.6)
    glRect(panelX, panelY + actualHeight - 2, panelX + PANEL_WIDTH, panelY + actualHeight)
    
    glColor(0.15, 0.2, 0.25, 0.8)
    glRect(panelX, panelY, panelX + 1, panelY + actualHeight)
    
    glColor(0.0, 0.0, 0.0, 0.6)
    glRect(panelX, panelY, panelX + PANEL_WIDTH, panelY + 1)
    
    if isDragging then
        glColor(0.12, 0.15, 0.18, 0.9)
    else
        glColor(0.1, 0.12, 0.15, 0.8)
    end
    glRect(panelX, panelY + actualHeight - TITLE_BAR_HEIGHT, panelX + PANEL_WIDTH, panelY + actualHeight)
    
    glColor(0.8, 0.9, 1.0, 1.0)
    glText("● Strategic Construction", panelX + PANEL_PADDING, panelY + actualHeight - 18, 14, "o")
    
    glColor(0.5, 0.6, 0.7, 0.8)
    local toggleX = panelX + PANEL_WIDTH - 18
    local toggleY = panelY + actualHeight - 22
    glText(collapsed and "+" or "−", toggleX, toggleY, 14, "o")
    
    if collapsed then return end
    
    if entryCount == 0 then
        local contentTop = panelY + actualHeight - TITLE_BAR_HEIGHT
        local emptyStatePadding = 20
        glColor(0.02, 0.02, 0.02, 0.85)
        glRect(panelX, panelY, panelX + PANEL_WIDTH, contentTop - emptyStatePadding)

        glColor(0.6, 0.6, 0.6, 1.0)
        glText("No strategic constructions", panelX + PANEL_PADDING, panelY + (contentTop - panelY - emptyStatePadding) / 2, 12, "o")
        return
    end
    
    for teamID, constructions in pairs(teamGroups) do
        table.sort(constructions, function(a, b)
            return a.lastProgress < b.lastProgress
        end)
    end

    local sortedTeamIDs = {}
    for teamID in pairs(teamGroups) do
        table.insert(sortedTeamIDs, teamID)
    end
    table.sort(sortedTeamIDs)
    
    local currentY = panelY + actualHeight - TITLE_BAR_HEIGHT - SPACING_UNIT

    for teamIndex, teamID in ipairs(sortedTeamIDs) do
        local constructions = teamGroups[teamID]
        local teamColor = constructions[1] and constructions[1].teamColor

        if teamColor and currentY >= panelY + TEAM_HEADER_HEIGHT + SPACING_UNIT then
            currentY = currentY - TEAM_HEADER_HEIGHT

            glColor(teamColor[1] * 0.2, teamColor[2] * 0.2, teamColor[3] * 0.2, 0.8)
            glRect(panelX, currentY, panelX + PANEL_WIDTH, currentY + TEAM_HEADER_HEIGHT)

            glColor(teamColor[1], teamColor[2], teamColor[3], 0.9)
            glRect(panelX, currentY, panelX + 3, currentY + TEAM_HEADER_HEIGHT)

            glColor(teamColor[1], teamColor[2], teamColor[3], 0.9)
            glRect(panelX, currentY + TEAM_HEADER_HEIGHT - 2, panelX + PANEL_WIDTH, currentY + TEAM_HEADER_HEIGHT)

            glColor(0.9, 0.9, 0.9, 1.0)
            local teamName = constructions[1].teamName
            glText(teamName, panelX + 8, currentY + (TEAM_HEADER_HEIGHT / 2) - 1, 11, "o")
        end

        for _, data in ipairs(constructions) do
            if currentY >= panelY + ENTRY_HEIGHT + SPACING_UNIT then
                currentY = currentY - ENTRY_HEIGHT
                DrawBARStyleEntry(data, panelX, currentY, PANEL_WIDTH)  -- Full width, no indent
            else
                break
            end
        end

        if teamIndex < #sortedTeamIDs then
            currentY = currentY - SPACING_UNIT
        end
    end
end

function DrawBARStyleEntry(data, x, y, width)
    local isHovered = IsMouseOverEntry(x, y, width, ENTRY_HEIGHT)
    
    if isHovered then
        glColor(0.15, 0.18, 0.22, 0.9)
        glRect(x, y, x + width, y + ENTRY_HEIGHT)
        glColor(0.3, 0.35, 0.4, 0.3)
        glRect(x + 1, y + 1, x + width - 1, y + ENTRY_HEIGHT - 1)
    else
        glColor(0.08, 0.10, 0.12, 0.8)
        glRect(x, y, x + width, y + ENTRY_HEIGHT)
    end
    
    glColor(data.teamColor[1], data.teamColor[2], data.teamColor[3], 0.9)
    glRect(x, y, x + 3, y + ENTRY_HEIGHT)
    
    local progressBarX = x + width - 70
    local progressBarWidth = 60
    local progressBarY = y + 4
    local progressBarHeight = ENTRY_HEIGHT - 8
    
    glColor(0.05, 0.05, 0.05, 0.9)
    glRect(progressBarX, progressBarY, progressBarX + progressBarWidth, progressBarY + progressBarHeight)
    
    local fillWidth = progressBarWidth * data.lastProgress
    glColor(data.teamColor[1] * 0.8, data.teamColor[2] * 0.8, data.teamColor[3] * 0.8, 0.8)
    glRect(progressBarX + 1, progressBarY + 1, progressBarX + fillWidth - 1, progressBarY + progressBarHeight - 1)
    
    glColor(data.teamColor[1], data.teamColor[2], data.teamColor[3], 0.6)
    glRect(progressBarX + 1, progressBarY + progressBarHeight - 2, progressBarX + fillWidth - 1, progressBarY + progressBarHeight - 1)
    
    glColor(0.9, 0.95, 1.0, 1.0)
    glText(data.unitName, x + 8, y + 9, 12, "o")

    glColor(0.85, 0.9, 0.95, 1.0)
    local progressText = string.format("%d%%", data.lastProgress * 100)
    glText(progressText, progressBarX + progressBarWidth/2, y + progressBarHeight/2 + 1, 11, "co")
end

function IsMouseOverEntry(x, y, width, height)
    return mouseX >= x and mouseX <= x + width and mouseY >= y and mouseY <= y + height
end

function IsMouseOverCollapseButton()
    local entryCount = 0
    local teamCount = 0
    local teamGroups = {}

    for unitID, data in pairs(trackedConstructions) do
        entryCount = entryCount + 1
        if not teamGroups[data.team] then
            teamGroups[data.team] = true
            teamCount = teamCount + 1
        end
    end

    local actualHeight
    if collapsed then
        actualHeight = TITLE_BAR_HEIGHT + SPACING_UNIT
    else
        local teamHeaderHeight = teamCount * (TEAM_HEADER_HEIGHT + SPACING_UNIT)
        local teamSeparatorHeight = math.max(0, teamCount * SPACING_UNIT)
        actualHeight = TITLE_BAR_HEIGHT + teamHeaderHeight + (entryCount * ENTRY_HEIGHT) + teamSeparatorHeight + PANEL_PADDING
    end
    
    local toggleX = panelX + PANEL_WIDTH - 20
    local toggleY = panelY + actualHeight - TITLE_BAR_HEIGHT
    
    return mouseX >= toggleX and mouseX <= toggleX + 15 and mouseY >= toggleY and mouseY <= toggleY + 20
end

function IsMouseOverTitleBar()
    local entryCount = 0
    local teamCount = 0
    local teamGroups = {}

    for unitID, data in pairs(trackedConstructions) do
        entryCount = entryCount + 1
        if not teamGroups[data.team] then
            teamGroups[data.team] = true
            teamCount = teamCount + 1
        end
    end

    local actualHeight
    if collapsed then
        actualHeight = TITLE_BAR_HEIGHT + SPACING_UNIT
    else
        local teamHeaderHeight = teamCount * (TEAM_HEADER_HEIGHT + SPACING_UNIT)
        local teamSeparatorHeight = math.max(0, teamCount * SPACING_UNIT)
        actualHeight = TITLE_BAR_HEIGHT + teamHeaderHeight + (entryCount * ENTRY_HEIGHT) + teamSeparatorHeight + PANEL_PADDING
    end

    local titleBarY = panelY + actualHeight - TITLE_BAR_HEIGHT

    return mouseX >= panelX and mouseX <= panelX + PANEL_WIDTH - 20 and
           mouseY >= titleBarY and mouseY <= panelY + actualHeight
end

function IsMouseOverPanel()
    local entryCount = 0
    local teamCount = 0
    local teamGroups = {}

    for unitID, data in pairs(trackedConstructions) do
        entryCount = entryCount + 1
        if not teamGroups[data.team] then
            teamGroups[data.team] = true
            teamCount = teamCount + 1
        end
    end

    local actualHeight
    if collapsed then
        actualHeight = TITLE_BAR_HEIGHT + SPACING_UNIT
    else
        local teamHeaderHeight = teamCount * (TEAM_HEADER_HEIGHT + SPACING_UNIT)
        local teamSeparatorHeight = math.max(0, teamCount * SPACING_UNIT)
        actualHeight = TITLE_BAR_HEIGHT + teamHeaderHeight + (entryCount * ENTRY_HEIGHT) + teamSeparatorHeight + PANEL_PADDING
    end
    
    return mouseX >= panelX and mouseX <= panelX + PANEL_WIDTH and 
           mouseY >= panelY and mouseY <= panelY + actualHeight
end

function widget:MouseMove(x, y)
    mouseX, mouseY = x, y
    
    if isDragging then
        local newX = x - dragOffsetX
        local newY = y - dragOffsetY
        
        local vsx, vsy = gl.GetViewSizes()
        panelX = math.max(0, math.min(newX, vsx - PANEL_WIDTH))
        panelY = math.max(0, math.min(newY, vsy - 100))
        
        return true
    end
    
    return false
end

function widget:MousePress(x, y, button)
    mouseX, mouseY = x, y
    
    if button == 1 and panelVisible then
        if IsMouseOverCollapseButton() then
            collapsed = not collapsed
            return true
        end
        
        if not collapsed then
            local clickedConstruction = GetConstructionAtMouse(x, y)
            if clickedConstruction then
                clickedConstructionID = clickedConstruction.unitID
                return true
            end
        end
        
        if IsMouseOverPanel() then
            isDragging = true
            dragOffsetX = x - panelX
            dragOffsetY = y - panelY
            return true
        end
    end
    return false
end

function widget:MouseRelease(x, y, button)
    if button == 1 then
        if clickedConstructionID and trackedConstructions[clickedConstructionID] then
            local data = trackedConstructions[clickedConstructionID]
            spSetCameraTarget(data.position.x, data.position.y, data.position.z)
            Spring.Echo("Viewing " .. data.unitName .. " (" .. data.teamName .. ")")
            clickedConstructionID = nil
            return true
        end
        
        if isDragging then
            isDragging = false
            return true
        end
        
        clickedConstructionID = nil
    end
    return false
end

function GetConstructionAtMouse(x, y)
    local teamGroups = {}
    local teamCount = 0
    local entryCount = 0

    for unitID, data in pairs(trackedConstructions) do
        entryCount = entryCount + 1
        data.unitID = unitID
        if not teamGroups[data.team] then
            teamGroups[data.team] = {}
            teamCount = teamCount + 1
        end
        table.insert(teamGroups[data.team], data)
    end
    
    local teamHeaderHeight = teamCount * (TEAM_HEADER_HEIGHT + SPACING_UNIT)
    local teamSeparatorHeight = math.max(0, teamCount * SPACING_UNIT)
    local actualHeight = TITLE_BAR_HEIGHT + teamHeaderHeight + (entryCount * ENTRY_HEIGHT) + teamSeparatorHeight + PANEL_PADDING
    
    for teamID, constructions in pairs(teamGroups) do
        table.sort(constructions, function(a, b)
            return a.lastProgress < b.lastProgress
        end)
    end
    
    local sortedTeamIDs = {}
    for teamID in pairs(teamGroups) do
        table.insert(sortedTeamIDs, teamID)
    end
    table.sort(sortedTeamIDs)
    
    local currentY = panelY + actualHeight - TITLE_BAR_HEIGHT - SPACING_UNIT

    for teamIndex, teamID in ipairs(sortedTeamIDs) do
        local constructions = teamGroups[teamID]

        currentY = currentY - TEAM_HEADER_HEIGHT

        for _, data in ipairs(constructions) do
            if currentY >= panelY + ENTRY_HEIGHT + SPACING_UNIT then
                currentY = currentY - ENTRY_HEIGHT

                local entryX = panelX
                local entryY = currentY
                local entryWidth = PANEL_WIDTH
                local entryHeight = ENTRY_HEIGHT

                if x >= entryX and x <= entryX + entryWidth and
                   y >= entryY and y <= entryY + entryHeight then
                    return data
                end
            else
                break
            end
        end

        if teamIndex < #sortedTeamIDs then
            currentY = currentY - SPACING_UNIT
        end
    end
    
    return nil
end

function widget:KeyPress(key, mods, isRepeat)
    if key == 116 then  -- 't' key
        if mods.ctrl then
            -- Ctrl+T = Debug missing units
            Spring.Echo("=== Strategic Construction Debug ===")
            local allUnits = spGetAllUnits()
            local missedUnits = {}
            
            for _, unitID in ipairs(allUnits) do
                local unitDefID = spGetUnitDefID(unitID)
                local unitDef = UnitDefs[unitDefID]
                local unitTeam = spGetUnitTeam(unitID)
                
                if unitDef and ShouldTrackUnit(unitID, unitTeam) then
                    local _, _, _, _, buildProgress = spGetUnitHealth(unitID)
                    if buildProgress and buildProgress < 1.0 then
                        if not GetUnitDisplayName(unitDefID) then
                            local key = unitDef.name .. " = \"" .. (unitDef.humanName or unitDef.name) .. "\""
                            if not missedUnits[key] then
                                missedUnits[key] = true
                                Spring.Echo("Missing: " .. key)
                            end
                        end
                    end
                end
            end
            Spring.Echo("=== End Debug ===")
        else
            panelVisible = not panelVisible
        end
        return true
    end
    return false
end

function widget:TextCommand(command)
    if command == "strategic" or command == "strat" then
        panelVisible = not panelVisible
        return true
    elseif command == "strategic debug" or command == "strat debug" then
        -- Debug missing units via chat command
        Spring.Echo("=== Strategic Construction Debug ===")
        local allUnits = spGetAllUnits()
        local missedUnits = {}
        
        for _, unitID in ipairs(allUnits) do
            local unitDefID = spGetUnitDefID(unitID)
            local unitDef = UnitDefs[unitDefID]
            local unitTeam = spGetUnitTeam(unitID)
            
            if unitDef and ShouldTrackUnit(unitID, unitTeam) then
                local _, _, _, _, buildProgress = spGetUnitHealth(unitID)
                if buildProgress and buildProgress < 1.0 then
                    if not TRACKED_BUILDINGS[unitDef.name] then
                        local key = unitDef.name .. " = \"" .. (unitDef.humanName or unitDef.name) .. "\""
                        if not missedUnits[key] then
                            missedUnits[key] = true
                            Spring.Echo("Missing: " .. key)
                        end
                    end
                end
            end
        end
        Spring.Echo("=== End Debug ===")
        return true
    end
    return false
end

function widget:ViewResize()
    local vsx, vsy = gl.GetViewSizes()
    panelX = math.max(0, math.min(panelX, vsx - PANEL_WIDTH))
    panelY = math.max(0, math.min(panelY, vsy - 100))
end

function widget:GetConfigData()
    return {
        panelX = panelX,
        panelY = panelY,
        panelVisible = panelVisible,
        collapsed = collapsed
    }
end

function widget:SetConfigData(data)
    if data then
        panelX = data.panelX or panelX
        panelY = data.panelY or panelY
        panelVisible = data.panelVisible ~= false
        collapsed = data.collapsed or false
    end
end

function widget:Shutdown()
    trackedConstructions = {}
    isDragging = false
    clickedConstructionID = nil
end