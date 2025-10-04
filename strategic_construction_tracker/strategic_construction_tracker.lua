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



-- Build categories (matching BAR's gridmenu system)
local BUILDCAT_ECONOMY = Spring.I18N and Spring.I18N("ui.buildMenu.category_econ") or "Economy"
local BUILDCAT_COMBAT = Spring.I18N and Spring.I18N("ui.buildMenu.category_combat") or "Combat"
local BUILDCAT_UTILITY = Spring.I18N and Spring.I18N("ui.buildMenu.category_utility") or "Utility"
local BUILDCAT_PRODUCTION = Spring.I18N and Spring.I18N("ui.buildMenu.category_production") or "Build"

-- Category icons (matching BAR's gridmenu system)
local CATEGORY_ICONS = {
	economy = "LuaUI/Images/groupicons/energy.png",
	combat = "LuaUI/Images/groupicons/weapon.png",
	utility = "LuaUI/Images/groupicons/util.png",
	build = "LuaUI/Images/groupicons/builder.png",
}

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

-- Dynamically build unitgroup to category mapping from UnitDefs
local UNITGROUP_TO_CATEGORY = {}
local function BuildCategoryMappings()
	UNITGROUP_TO_CATEGORY = {}

	for unitDefID, unitDef in pairs(UnitDefs) do
		if unitDef.customParams and unitDef.customParams.unitgroup then
			local unitgroup = unitDef.customParams.unitgroup

			-- Skip if already categorized
			if not UNITGROUP_TO_CATEGORY[unitgroup] then
				-- Determine category based on unit characteristics
				local category = nil

				-- Economy: energy production, metal extraction, converters
				if unitDef.energyMake and unitDef.energyMake > 0 then
					category = "economy"
				elseif unitDef.extractsMetal and unitDef.extractsMetal > 0 then
					category = "economy"
				elseif unitgroup:match("energy") or unitgroup:match("metal") or unitgroup:match("converter") then
					category = "economy"

				-- Combat: weapons, defense
				elseif #unitDef.weapons > 0 or unitgroup:match("weapon") or unitgroup:match("defense") or unitgroup:match("nuke") or unitgroup:match("aa") then
					category = "combat"

				-- Build: factories, builders
				elseif unitDef.isBuilder or unitgroup:match("builder") or unitgroup:match("factory") then
					category = "build"

				-- Utility: everything else (radar, jammers, etc)
				else
					category = "utility"
				end

				if category then
					UNITGROUP_TO_CATEGORY[unitgroup] = category
				end
			end
		end
	end
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

-- Category filter state
local activeCategories = {
	economy = true,
	combat = true,
	utility = true,
	build = true,
}


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

local function LoadCategoryFilters()
    local configString = Spring.GetConfigString("StrategicConstructionTracker_Filters", "economy,combat,utility,build")
    activeCategories = {economy = false, combat = false, utility = false, build = false}
    for category in configString:gmatch("[^,]+") do
        activeCategories[category] = true
    end
end

local function SaveCategoryFilters()
    local filters = {}
    for category, active in pairs(activeCategories) do
        if active then
            table.insert(filters, category)
        end
    end
    Spring.SetConfigString("StrategicConstructionTracker_Filters", table.concat(filters, ","))
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

local function BuildCategoriesArray(includeProgress)
    local categories = {
        {id = "economy", name = BUILDCAT_ECONOMY, icon = CATEGORY_ICONS.economy, active = activeCategories.economy},
        {id = "combat", name = BUILDCAT_COMBAT, icon = CATEGORY_ICONS.combat, active = activeCategories.combat},
        {id = "utility", name = BUILDCAT_UTILITY, icon = CATEGORY_ICONS.utility, active = activeCategories.utility},
        {id = "build", name = BUILDCAT_PRODUCTION, icon = CATEGORY_ICONS.build, active = activeCategories.build},
    }

    -- Add progress values if provided
    if includeProgress then
        for i, cat in ipairs(categories) do
            cat.count = includeProgress[cat.id].count or 0
            cat.progress = includeProgress[cat.id].progress or 0
        end
    end

    return categories
end


function widget:Initialize()
    Spring.Echo(WIDGET_NAME .. ": Initializing widget...")

    -- Build category mappings dynamically from UnitDefs
    BuildCategoryMappings()
    local count = 0
    for _ in pairs(UNITGROUP_TO_CATEGORY) do count = count + 1 end
    Spring.Echo(WIDGET_NAME .. ": Mapped " .. count .. " unitgroups to categories")

    LoadPosition()
    LoadCollapsedState()
    LoadCategoryFilters()

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
        constructions = {size = 0},
        categories = BuildCategoriesArray()
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

function widget:ToggleCategoryFilter(event)
    local element = event.current_element
    if not element then
        return false
    end

    local categoryId = element:GetAttribute("data-category")
    if not categoryId then
        return false
    end

    activeCategories[categoryId] = not activeCategories[categoryId]

    SaveCategoryFilters()
    UpdateRMLuiData()
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

local function GetUnitCategory(unitDefID)
    local unitDef = UnitDefs[unitDefID]
    if not unitDef or not unitDef.customParams then
        return nil
    end

    local unitgroup = unitDef.customParams.unitgroup
    if not unitgroup then
        return nil
    end

    return UNITGROUP_TO_CATEGORY[unitgroup]
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

    -- Count constructions per category and calculate average progress
    local categoryCounts = {
        economy = 0,
        combat = 0,
        utility = 0,
        build = 0,
    }

    local categoryProgress = {
        economy = {total = 0, count = 0},
        combat = {total = 0, count = 0},
        utility = {total = 0, count = 0},
        build = {total = 0, count = 0},
    }

    for unitID, data in pairs(trackedConstructions) do
        local unitCategory = GetUnitCategory(data.unitDefID)
        if unitCategory and categoryCounts[unitCategory] then
            categoryCounts[unitCategory] = categoryCounts[unitCategory] + 1
            categoryProgress[unitCategory].total = categoryProgress[unitCategory].total + (data.lastProgress or 0)
            categoryProgress[unitCategory].count = categoryProgress[unitCategory].count + 1
        end
    end

    -- Calculate average progress per category and prepare data for BuildCategoriesArray
    local categoryData = {}
    for category, stats in pairs(categoryProgress) do
        categoryData[category] = {
            count = categoryCounts[category],
            progress = stats.count > 0 and (stats.total / stats.count) or 0
        }
    end

    -- Update category filter states with counts and progress
    dm_handle.categories = BuildCategoriesArray(categoryData)

    local teamGroups = {}
    local totalConstructions = 0

    for unitID, data in pairs(trackedConstructions) do
        -- Check category filter
        local unitCategory = GetUnitCategory(data.unitDefID)
        if not unitCategory or activeCategories[unitCategory] then
            totalConstructions = totalConstructions + 1
            data.unit_id = unitID
            data.unit_name = data.unitName
            data.unit_def_id = data.unitDefID
            local unitDef = UnitDefs[data.unitDefID]
            data.unit_internal_name = unitDef and unitDef.name or ""
            -- Try to get buildPic path if it exists
            data.build_pic = unitDef and unitDef.buildPic or ""
            data.build_pic_lower = data.build_pic:lower()

            -- Get icon path from iconTypes table
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