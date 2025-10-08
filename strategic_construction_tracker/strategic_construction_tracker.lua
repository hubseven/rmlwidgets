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

-- Build categories
local BUILDCAT_ECONOMY = Spring.I18N and Spring.I18N("ui.buildMenu.category_econ") or "Economy"
local BUILDCAT_COMBAT = Spring.I18N and Spring.I18N("ui.buildMenu.category_combat") or "Combat"
local BUILDCAT_UTILITY = Spring.I18N and Spring.I18N("ui.buildMenu.category_utility") or "Utility"
local BUILDCAT_PRODUCTION = Spring.I18N and Spring.I18N("ui.buildMenu.category_production") or "Build"

-- Category icons
local CATEGORY_ICONS = {
	economy = "LuaUI/Images/groupicons/energy.png",
	combat = "LuaUI/Images/groupicons/weapon.png",
	utility = "LuaUI/Images/groupicons/util.png",
	build = "LuaUI/Images/groupicons/builder.png",
}

-- Important buildings/units to track
local TRACKED_BUILDINGS_LIST = {
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
local completedConstructions = {}
local nextEntryID = 1
local gameStarted = false
local lastUIHiddenState = false


-- Position state
local widgetPosX = 50
local widgetPosY = 100

-- RMLui variables
local document
local dm_handle
local panelVisible = true
local collapsed = false
local dataDirty = false

-- Category filter state
local activeCategories = {
	economy = true,
	combat = true,
	utility = true,
	build = true,
}

-- Selection visualization state
local selectedUnitsToHighlight = {}
local selectionCenter = nil

-- Animation state for wall stripes
local animationTime = 0

-- Hover menu interaction tracking
local isHoverMenuOpen = false
local hoverMenuScrollPositions = {}

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
        {id = "economy", name = BUILDCAT_ECONOMY, icon = CATEGORY_ICONS.economy, active = activeCategories.economy, count = 0, progress = 0},
        {id = "combat", name = BUILDCAT_COMBAT, icon = CATEGORY_ICONS.combat, active = activeCategories.combat, count = 0, progress = 0},
        {id = "utility", name = BUILDCAT_UTILITY, icon = CATEGORY_ICONS.utility, active = activeCategories.utility, count = 0, progress = 0},
        {id = "build", name = BUILDCAT_PRODUCTION, icon = CATEGORY_ICONS.build, active = activeCategories.build, count = 0, progress = 0},
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

    local gameFrame = Spring.GetGameFrame()
    if gameFrame and gameFrame > 0 then
        gameStarted = true
        if not Spring.IsGUIHidden() then
            document:Show()
            Spring.Echo(WIDGET_NAME .. ": Widget loaded mid-game, showing UI")
        end
    else
        Spring.Echo(WIDGET_NAME .. ": Widget loaded in lobby, waiting for game start")
    end

    UpdateDocumentPosition()

    Spring.Echo(WIDGET_NAME .. ": Widget initialized successfully")

    Scan()
    UpdateRMLuiData()

    return true
end

function widget:GameStart()
    gameStarted = true
    if document and not Spring.IsGUIHidden() then
        document:Show()
        Spring.Echo(WIDGET_NAME .. ": Game started, showing UI")
    end
end

function widget:Update()
    if not document or not gameStarted then
        return
    end

    local isHidden = Spring.IsGUIHidden()
    local isInMenu = false
    if WG then
        isInMenu = (WG.PauseScreen and WG.PauseScreen.IsActive and WG.PauseScreen.IsActive())
            or (WG.Chili and WG.Chili.Screen0 and WG.Chili.Screen0.focusedControl)
    end

    local shouldHide = isHidden or isInMenu

    if shouldHide ~= lastUIHiddenState then
        lastUIHiddenState = shouldHide
        if shouldHide then
            document:Hide()
        else
            document:Show()
        end
    end
end

function widget:StartDrag(event)
    local mx, my = Spring.GetMouseState()
    local vsx, vsy = Spring.GetViewGeometry()

    widgetState.isDragging = true
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

    local unitID = tonumber(element:GetAttribute("data-unit-id"))
    local isCompleted = element:GetAttribute("data-is-completed") == "true"

    if isCompleted and not unitID then
        local unitDefID = tonumber(element:GetAttribute("data-unit-def-id"))
        local teamID = tonumber(element:GetAttribute("data-team-id"))

        if unitDefID and teamID then
            local validUnitIDs = {}
            local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
            local unitName = ""
            local positionsFound = 0

            for _, completed in ipairs(completedConstructions) do
                if completed.unitDefID == unitDefID and completed.team == teamID then
                    if Spring.ValidUnitID(completed.unitID) then
                        table.insert(validUnitIDs, completed.unitID)
                        unitName = completed.unitName

                        local x, y, z = Spring.GetUnitPosition(completed.unitID)
                        if x then
                            minX = math.min(minX, x)
                            maxX = math.max(maxX, x)
                            minZ = math.min(minZ, z)
                            maxZ = math.max(maxZ, z)
                            positionsFound = positionsFound + 1
                        end
                    end
                end
            end

            if #validUnitIDs > 0 then
                selectedUnitsToHighlight = {}
                local sumX, sumY, sumZ = 0, 0, 0
                local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
                local teamColor = nil
                for _, completed in ipairs(completedConstructions) do
                    if completed.unitDefID == unitDefID and completed.team == teamID then
                        teamColor = completed.teamColor
                        break
                    end
                end

                for _, completed in ipairs(completedConstructions) do
                    if completed.unitDefID == unitDefID and completed.team == teamID then
                        if Spring.ValidUnitID(completed.unitID) then
                            local x, y, z = Spring.GetUnitPosition(completed.unitID)
                            if x then
                                local unitDef = UnitDefs[unitDefID]
                                local radius = unitDef and unitDef.radius or 50

                                selectedUnitsToHighlight[completed.unitID] = {
                                    x = x,
                                    y = y,
                                    z = z,
                                    radius = radius,
                                    teamColor = teamColor or {1, 1, 1},
                                    unitName = unitName
                                }
                                sumX = sumX + x
                                sumY = sumY + y
                                sumZ = sumZ + z
                                minX = math.min(minX, x)
                                maxX = math.max(maxX, x)
                                minZ = math.min(minZ, z)
                                maxZ = math.max(maxZ, z)
                            end
                        end
                    end
                end

                local count = 0
                for _ in pairs(selectedUnitsToHighlight) do count = count + 1 end

                if count > 0 then
                    selectionCenter = {
                        x = sumX / count,
                        y = sumY / count,
                        z = sumZ / count
                    }

                    Spring.Echo(string.format("[SCT] Selected %d x %s", count, unitName))

                    Spring.SelectUnitArray(validUnitIDs)
                    Spring.SendCommands("viewselection")
                end

                return true
            end
        end
    elseif unitID then
        if Spring.ValidUnitID(unitID) then
            Spring.SelectUnitArray({unitID})
            Spring.SendCommands("viewselection")
            return true
        end
    end

    return false
end

function widget:SelectCompletedGroup(event)
    local element = event.current_element
    if not element then
        return false
    end

    local teamID = tonumber(element:GetAttribute("data-team-id"))
    if not teamID then
        return false
    end

    local validUnitIDs = {}
    for _, completedData in ipairs(completedConstructions) do
        if completedData.team == teamID then
            if Spring.ValidUnitID(completedData.unitID) then
                table.insert(validUnitIDs, completedData.unitID)
            end
        end
    end

    if #validUnitIDs > 0 then
        Spring.SelectUnitArray(validUnitIDs)
        Spring.SendCommands("viewselection")
        return true
    end

    return false
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
                if not trackedConstructions[unitID] then
                    AddConstructionToTracker(unitID, unitDefID, unitTeam, nil)
                end
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

local function SaveHoverMenuScrollPositions()
    if not document then return end

    for teamID, _ in pairs(trackedConstructions) do
        local hoverMenu = document:GetElementById("hover-menu-" .. teamID)
        if hoverMenu then
            hoverMenuScrollPositions[teamID] = hoverMenu.scroll_top
        end
    end
end

local function RestoreHoverMenuScrollPositions()
    if not document then return end

    for teamID, scrollTop in pairs(hoverMenuScrollPositions) do
        local hoverMenu = document:GetElementById("hover-menu-" .. teamID)
        if hoverMenu then
            hoverMenu.scroll_top = scrollTop
        end
    end
end

function UpdateRMLuiData()
    if not dm_handle then return end

    SaveHoverMenuScrollPositions()

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

            local constructionData = {
                unit_id = unitID or 0,
                unit_name = data.unitName or "Unknown",
                unit_def_id = data.unitDefID or 0,
                is_completed = false
            }

            local unitDef = UnitDefs[data.unitDefID]
            constructionData.unit_internal_name = unitDef and unitDef.name or ""
            constructionData.build_pic = unitDef and unitDef.buildPic or ""
            constructionData.build_pic_lower = constructionData.build_pic:lower()

            -- Get icon path from iconTypes table
            local iconTypeName = unitDef and unitDef.iconType or ""
            local iconData = iconTypes and iconTypes[iconTypeName]
            constructionData.icon_path = iconData and iconData.bitmap or ""

            constructionData.progress_percent = math.floor((data.lastProgress or 0) * 100)

            constructionData.progress_squares = {}
            local filledSquares = math.floor(constructionData.progress_percent / 10)
            for i = 1, filledSquares do
                table.insert(constructionData.progress_squares, {is_filled = true})
            end

            local teamColor = data.teamColor or {1, 1, 1}
            local r = math.floor(teamColor[1] * 255)
            local g = math.floor(teamColor[2] * 255)
            local b = math.floor(teamColor[3] * 255)
            constructionData.team_color = string.format("rgb(%d,%d,%d)", r, g, b)

            if not teamGroups[data.team] then
                teamGroups[data.team] = {
                    id = data.team,
                    name = data.teamName,
                    color = constructionData.team_color,
                    border_color = constructionData.team_color,
                    accent_color = constructionData.team_color,
                    active_constructions = {},
                    completed_constructions = {},
                    total_count = 0,
                    avg_progress = 0,
                    total_progress = 0
                }
            end

            table.insert(teamGroups[data.team].active_constructions, constructionData)
            teamGroups[data.team].total_progress = teamGroups[data.team].total_progress + data.lastProgress
        end
    end

    for _, completedData in ipairs(completedConstructions) do
        if not teamGroups[completedData.team] then
            local r = math.floor(completedData.teamColor[1] * 255)
            local g = math.floor(completedData.teamColor[2] * 255)
            local b = math.floor(completedData.teamColor[3] * 255)
            local teamColor = string.format("rgb(%d,%d,%d)", r, g, b)

            teamGroups[completedData.team] = {
                id = completedData.team,
                name = completedData.teamName,
                color = teamColor,
                border_color = teamColor,
                accent_color = teamColor,
                active_constructions = {},
                completed_constructions = {},
                total_count = 0,
                avg_progress = 0,
                total_progress = 0
            }
        end

        local unitDef = UnitDefs[completedData.unitDefID]
        local iconTypeName = unitDef and unitDef.iconType or ""
        local iconData = iconTypes and iconTypes[iconTypeName]

        local completedTeamColor = completedData.teamColor or {1, 1, 1}
        local r = math.floor(completedTeamColor[1] * 255)
        local g = math.floor(completedTeamColor[2] * 255)
        local b = math.floor(completedTeamColor[3] * 255)

        table.insert(teamGroups[completedData.team].completed_constructions, {
            unit_id = completedData.unitID or 0,
            unit_name = completedData.unitName or "Unknown",
            unit_def_id = completedData.unitDefID or 0,
            unit_internal_name = unitDef and unitDef.name or "",
            build_pic = unitDef and unitDef.buildPic or "",
            icon_path = iconData and iconData.bitmap or "",
            team_color = string.format("rgb(%d,%d,%d)", r, g, b),
            completion_time = completedData.completionTime or 0,
            is_completed = true,
            progress_percent = 100,
            progress_squares = {
                {is_filled = true}, {is_filled = true}, {is_filled = true}, {is_filled = true}, {is_filled = true},
                {is_filled = true}, {is_filled = true}, {is_filled = true}, {is_filled = true}, {is_filled = true}
            },
            position = completedData.position or {x = 0, y = 0, z = 0}
        })
    end

    for teamID, teamData in pairs(teamGroups) do
        local activeCount = #teamData.active_constructions
        local completedCount = #teamData.completed_constructions

        teamData.total_count = activeCount
        teamData.completed_count = completedCount
        teamData.has_active = activeCount > 0
        teamData.has_completed = completedCount > 0

        if activeCount > 0 then
            teamData.avg_progress = teamData.total_progress / activeCount
            teamData.avg_progress_percent = math.floor(teamData.avg_progress * 100)
        else
            teamData.avg_progress = 0
            teamData.avg_progress_percent = 0
        end

        teamData.avg_progress_squares = {}
        local filledSquares = math.floor(teamData.avg_progress_percent / 10)
        for i = 1, filledSquares do
            table.insert(teamData.avg_progress_squares, {is_filled = true})
        end

        local iconMap = {}
        for _, construction in ipairs(teamData.active_constructions) do
            local key = construction.unit_def_id or 0
            if key ~= 0 and not iconMap[key] then
                iconMap[key] = {
                    unit_def_id = construction.unit_def_id or 0,
                    icon_path = construction.icon_path or "",
                    count = 0
                }
            end
            if key ~= 0 then
                iconMap[key].count = iconMap[key].count + 1
            end
        end

        teamData.aggregated_icons = {}
        for _, iconData in pairs(iconMap) do
            table.insert(teamData.aggregated_icons, iconData)
        end
        table.sort(teamData.aggregated_icons, function(a, b)
            if a.count == b.count then
                return a.unit_def_id < b.unit_def_id
            end
            return a.count > b.count
        end)

        table.sort(teamData.active_constructions, function(a, b)
            return a.progress_percent < b.progress_percent
        end)

        table.sort(teamData.completed_constructions, function(a, b)
            return a.completion_time > b.completion_time
        end)

        local uniqueCompletedMap = {}
        for _, completed in ipairs(teamData.completed_constructions) do
            local key = completed.unit_def_id or 0
            if key ~= 0 and not uniqueCompletedMap[key] then
                uniqueCompletedMap[key] = {
                    unit_def_id = completed.unit_def_id or 0,
                    unit_name = completed.unit_name or "Unknown",
                    count = 0,
                    latest_position = completed.position or {x = 0, y = 0, z = 0}
                }
            end
            if key ~= 0 then
                uniqueCompletedMap[key].count = uniqueCompletedMap[key].count + 1
                uniqueCompletedMap[key].latest_position = completed.position or {x = 0, y = 0, z = 0}
            end
        end

        teamData.unique_completed = {}
        for _, uniqueCompleted in pairs(uniqueCompletedMap) do
            table.insert(teamData.unique_completed, uniqueCompleted)
        end
        table.sort(teamData.unique_completed, function(a, b)
            return a.unit_name < b.unit_name
        end)
    end

    local teamsArray = {}
    for teamID, teamData in pairs(teamGroups) do
        if teamData.has_active or teamData.has_completed then
            table.insert(teamsArray, teamData)
        end
    end

    table.sort(teamsArray, function(a, b)
        return a.id < b.id
    end)

    dm_handle.teams = teamsArray
    dm_handle.constructions = {size = totalConstructions}

    RestoreHoverMenuScrollPositions()
end

function widget:PlayerChanged(playerID)
    local spec, fullV = spGetSpectatingState()
    isSpectator = spec
    fullView = fullV
    myTeamID = spGetMyTeamID()

    trackedConstructions = {}
    worldLabels = {}
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
        local data = trackedConstructions[unitID]
        local completedData = {
            unitID = unitID,
            unitDefID = data.unitDefID,
            unitName = data.unitName,
            team = data.team,
            teamName = data.teamName,
            teamColor = data.teamColor,
            position = data.position,
            completionTime = Spring.GetGameSeconds(),
            startTime = data.startTime,
            isDead = false
        }
        table.insert(completedConstructions, completedData)

        trackedConstructions[unitID] = nil
        UpdateRMLuiData()
    end
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
    if trackedConstructions[unitID] then
        trackedConstructions[unitID] = nil
        UpdateRMLuiData()
    end

    if selectedUnitsToHighlight[unitID] then
        selectedUnitsToHighlight[unitID] = nil
    end
end

function widget:GameFrame()
    if dataDirty then
        UpdateRMLuiData()
        dataDirty = false
    end

    if next(selectedUnitsToHighlight) ~= nil then
        local currentSelection = Spring.GetSelectedUnits()
        local selectionSet = {}
        for _, unitID in ipairs(currentSelection) do
            selectionSet[unitID] = true
        end

        local stillSelected = false
        for unitID in pairs(selectedUnitsToHighlight) do
            if selectionSet[unitID] then
                stillSelected = true
                break
            end
        end

        if not stillSelected then
            selectedUnitsToHighlight = {}
            selectionCenter = nil
            Spring.Echo("[SCT] Cleared selection highlights")
        end
    end

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

        newX = math.max(0, math.min(newX, vsx - 150))
        cssY = math.max(0, math.min(cssY, vsy - 45))

        if math.abs(newX - widgetPosX) > 1 or math.abs(cssY - widgetPosY) > 1 then
            widgetPosX = newX
            widgetPosY = cssY
            UpdateDocumentPosition()
        end
    end
end

function UpdateConstructionProgress()
    local hasChanges = false
    for unitID, data in pairs(trackedConstructions) do
        local health, maxHealth, _, _, buildProgress = spGetUnitHealth(unitID)
        if buildProgress then
            if buildProgress >= 1.0 then
                trackedConstructions[unitID] = nil
                hasChanges = true
            else
                if math.abs(data.lastProgress - buildProgress) > 0.05 then
                    data.lastProgress = buildProgress
                    hasChanges = true
                end
            end
        else
            trackedConstructions[unitID] = nil
            hasChanges = true
        end
    end

    local i = 1
    while i <= #completedConstructions do
        local completed = completedConstructions[i]
        if not Spring.ValidUnitID(completed.unitID) then
            table.remove(completedConstructions, i)
            hasChanges = true
        else
            i = i + 1
        end
    end

    if hasChanges then
        dataDirty = true
    end
end

function widget:DrawScreen()
    if Spring.IsGUIHidden() or next(selectedUnitsToHighlight) == nil then
        return
    end

    animationTime = animationTime + 0.02

    local teamColor = nil
    local unitName = ""
    local unitCount = 0
    local units = {}
    local screenPositions = {}

    for unitID, highlight in pairs(selectedUnitsToHighlight) do
        if Spring.ValidUnitID(unitID) then
            local x, y, z = Spring.GetUnitPosition(unitID)
            if x then
                teamColor = highlight.teamColor
                unitName = highlight.unitName
                unitCount = unitCount + 1

                local sx, sy, sz = Spring.WorldToScreenCoords(x, y, z)
                if sz and sz < 1 then  -- Only if in front of camera
                    table.insert(units, {x = x, y = y, z = z, sx = sx, sy = sy})
                    table.insert(screenPositions, {sx = sx, sy = sy})
                end
            end
        end
    end

    if teamColor and unitCount > 0 and #screenPositions > 0 then
        local avgSx, avgSy = 0, 0
        for _, pos in ipairs(screenPositions) do
            avgSx = avgSx + pos.sx
            avgSy = avgSy + pos.sy
        end
        avgSx = avgSx / #screenPositions
        avgSy = avgSy / #screenPositions

        local billboardOffsetY = 200
        avgSy = avgSy + billboardOffsetY

        gl.LineWidth(2)
        gl.Color(teamColor[1], teamColor[2], teamColor[3], 0.5)
        for _, unit in ipairs(units) do
            gl.BeginEnd(GL.LINES, function()
                gl.Vertex(avgSx, avgSy)
                gl.Vertex(unit.sx, unit.sy)
            end)
        end

        gl.LineWidth(2)
        gl.Color(teamColor[1], teamColor[2], teamColor[3], 0.8)
        for _, unit in ipairs(units) do
            local radius = 8
            gl.BeginEnd(GL.LINE_LOOP, function()
                for i = 0, 15 do
                    local angle = (i / 16) * math.pi * 2
                    gl.Vertex(unit.sx + math.cos(angle) * radius, unit.sy + math.sin(angle) * radius)
                end
            end)
        end

        local fontSize = 18
        local quantityText = tostring(unitCount)
        local padding = 30

        local nameWidth = #unitName * fontSize * 0.6
        local qtyWidth = #quantityText * (fontSize + 4) * 0.6
        local panelWidth = math.max(nameWidth, qtyWidth) + padding * 2
        panelWidth = math.max(panelWidth, 180)
        local panelHeight = 95

        local px = avgSx - panelWidth/2
        local py = avgSy - panelHeight/2

        gl.Color(0.0, 0.0, 0.0, 0.9)
        gl.Rect(px, py, px + panelWidth, py + panelHeight)

        local borderWidth = 4
        gl.Color(teamColor[1], teamColor[2], teamColor[3], 0.95)
        gl.Rect(px, py, px + borderWidth, py + panelHeight)

        gl.Color(1, 1, 1, 1)
        gl.Text(unitName, avgSx, avgSy + 18, fontSize, "cvO")

        local qtySize = fontSize + 6
        gl.Color(teamColor[1] * 1.2, teamColor[2] * 1.2, teamColor[3] * 1.2, 1.0)
        gl.Text(quantityText, avgSx, avgSy - 20, qtySize, "cvO")

        gl.LineWidth(1)
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
    worldLabels = {}

    Spring.Echo(WIDGET_NAME .. ": Shutdown complete")
end