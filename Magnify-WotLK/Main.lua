local ADDON_NAME, Magnify = ...

-- Constants
Magnify.MIN_ZOOM = 1.0

Magnify.MINIMODE_MIN_ZOOM = 1.0
Magnify.MINIMODE_MAX_ZOOM = 3.0
Magnify.MINIMODE_ZOOM_STEP = 0.1

Magnify.MAXZOOM_DEFAULT = 4
Magnify.ZOOMSTEP_DEFAULT = 0.1
Magnify.ENABLEPERSISTZOOM_DEFAULT = false
Magnify.ENABLEOLDPARTYICONS_DEFAULT = false

Magnify.WORLDMAP_POI_MIN_X = 12
Magnify.WORLDMAP_POI_MIN_Y = -12
Magnify.worldmapPoiMaxX = nil -- changes based on current scale, see SetPOIMaxBounds
Magnify.worldmapPoiMaxY = nil -- changes based on current scale, see SetPOIMaxBounds

Magnify.PLAYER_ARROW_SIZE = 36

-- If you open the map and the zone was the same, we want to remember the previous state
Magnify.PreviousState = {
	panX = 0,
	panY = 0,
	scale = 1,
	zone = 0
}

MagnifyOptions = {
	enablePersistZoom = false,
	enableOldPartyIcons = false,
	maxZoom = Magnify.MAXZOOM_DEFAULT,
	zoomStep = Magnify.ZOOMSTEP_DEFAULT
}

local function updatePointRelativeTo(frame, newRelativeFrame)
	local currentPoint, _currentRelativeFrame, currentRelativePoint, currentOffsetX, currentOffsetY = frame:GetPoint()
	frame:ClearAllPoints()
	frame:SetPoint(currentPoint, newRelativeFrame, currentRelativePoint, currentOffsetX, currentOffsetY)
end

local function resizePOI(poiButton)
	if (poiButton) then
		local _, _, _, x, y = poiButton:GetPoint()
		local mapster, mapsterPoiScale = Magnify.GetMapster("poiScale")
		local _, mapsterQuestObjectives = Magnify.GetMapster("questObjectives")
		if (mapster) then
			-- Sorry mapster I need to take the wheel
			mapster.WorldMapFrame_DisplayQuestPOI = function() end
		end

		local effectivePoiScale = (mapsterPoiScale or 1)
		local posX, posY

		-- Determine position based on mode
		if mapsterQuestObjectives and mapsterQuestObjectives == 1 then
			-- Mode 1 (Only WorldMap Blobs): Try to get position from normalized coordinates
			local questId = poiButton.questId
			if questId then
				local _, normalizedX, normalizedY = QuestPOIGetIconInfo(questId)
				if normalizedX and normalizedY then
					-- Calculate pixel position from normalized coords
					posX = normalizedX * WorldMapDetailFrame:GetWidth() * WORLDMAP_SETTINGS.size
					posY = -normalizedY * WorldMapDetailFrame:GetHeight() * WORLDMAP_SETTINGS.size
				end
			end
			-- Fallback to existing position if normalized coords not available
			if not posX and x ~= nil and y ~= nil then
				posX = x
				posY = y
			end
		elseif x ~= nil and y ~= nil then
			-- Modes 0 and 2: Use existing position
			posX = x
			posY = y
		end

		-- Apply scale and position transformation
		if posX and posY then
			local s = WORLDMAP_SETTINGS.size / WorldMapDetailFrame:GetEffectiveScale() * effectivePoiScale
			posX = posX / s
			posY = posY / s
			poiButton:SetScale(s)
			poiButton:SetPoint("CENTER", poiButton:GetParent(), "TOPLEFT", posX, posY)

			-- Extra safeguard: Ensure bounds are set before clamping
			if Magnify.worldmapPoiMaxX == nil or Magnify.worldmapPoiMaxY == nil then Magnify.SetPOIMaxBounds() end

			if (posY > Magnify.WORLDMAP_POI_MIN_Y) then
				posY = Magnify.WORLDMAP_POI_MIN_Y
			elseif (posY < Magnify.worldmapPoiMaxY) then
				posY = Magnify.worldmapPoiMaxY
			end
			if (posX < Magnify.WORLDMAP_POI_MIN_X) then
				posX = Magnify.WORLDMAP_POI_MIN_X
			elseif (posX > Magnify.worldmapPoiMaxX) then
				posX = Magnify.worldmapPoiMaxX
			end
		end
	end
end

function Magnify.PersistMapScrollAndPan()
	Magnify.PreviousState.panX = WorldMapScrollFrame:GetHorizontalScroll()
	Magnify.PreviousState.panY = WorldMapScrollFrame:GetVerticalScroll()
	Magnify.PreviousState.scale = WorldMapDetailFrame:GetScale()
	Magnify.PreviousState.zone = GetCurrentMapZone()
end

function Magnify.AfterScrollOrPan()
	Magnify.PersistMapScrollAndPan()
	if (WORLDMAP_SETTINGS.selectedQuest) then
		WorldMapBlobFrame:DrawQuestBlob(WORLDMAP_SETTINGS.selectedQuestId, false);
		WorldMapBlobFrame:DrawQuestBlob(WORLDMAP_SETTINGS.selectedQuestId, true);
	end
end

function Magnify.ResizeQuestPOIs()
	-- Safeguard: Ensure POI max bounds are set before resizing (prevents nil comparisons)
	if Magnify.worldmapPoiMaxX == nil or Magnify.worldmapPoiMaxY == nil then Magnify.SetPOIMaxBounds() end

	local QUEST_POI_MAX_TYPES = 4;
	local POI_TYPE_MAX_BUTTONS = 25;

	for i = 1, QUEST_POI_MAX_TYPES do
		for j = 1, POI_TYPE_MAX_BUTTONS do
			local buttonName = "poiWorldMapPOIFrame" .. i .. "_" .. j;
			resizePOI(_G[buttonName])
		end
	end

	resizePOI(QUEST_POI_SWAP_BUTTONS["WorldMapPOIFrame"])
end

function Magnify.SetPOIMaxBounds()
	-- Safeguard: Use defaults if settings/frame are not yet available (private server compatibility)
	local mapSize = WORLDMAP_SETTINGS.size or 1
	local detailHeight = WorldMapDetailFrame:GetHeight() or 1000
	local detailWidth = WorldMapDetailFrame:GetWidth() or 1000
	Magnify.worldmapPoiMaxY = detailHeight * -mapSize + 12;
	Magnify.worldmapPoiMaxX = detailWidth * mapSize + 12;
end

function Magnify.SetDetailFrameScale(num)
	WorldMapDetailFrame:SetScale(num)
	Magnify.SetPOIMaxBounds() -- Calling Magnify method

	-- Adjust frames to inversely scale with the detail frame so they maintain relative screen size
	WorldMapPOIFrame:SetScale(1 / WORLDMAP_SETTINGS.size)
	WorldMapBlobFrame:SetScale(num)

	WorldMapPlayer:SetScale(1 / WorldMapDetailFrame:GetScale())
	WorldMapDeathRelease:SetScale(1 / WorldMapDetailFrame:GetScale())
	if PlayerArrowFrame then PlayerArrowFrame:SetScale(1 / WorldMapDetailFrame:GetScale()) end
	if PlayerArrowEffectFrame then PlayerArrowEffectFrame:SetScale(1 / WorldMapDetailFrame:GetScale()) end
	WorldMapCorpse:SetScale(1 / WorldMapDetailFrame:GetScale())
	local numFlags = GetNumBattlefieldFlagPositions()
	for i = 1, numFlags do
		local flagFrameName = "WorldMapFlag" .. i;
		if (_G[flagFrameName]) then _G[flagFrameName]:SetScale(1 / WorldMapDetailFrame:GetScale()) end
	end

	for i = 1, MAX_PARTY_MEMBERS do if (_G["WorldMapParty" .. i]) then _G["WorldMapParty" .. i]:SetScale(1 / WorldMapDetailFrame:GetScale()) end end

	for i = 1, MAX_RAID_MEMBERS do if (_G["WorldMapRaid" .. i]) then _G["WorldMapRaid" .. i]:SetScale(1 / WorldMapDetailFrame:GetScale()) end end

	for i = 1, #MAP_VEHICLES do if (MAP_VEHICLES[i]) then MAP_VEHICLES[i]:SetScale(1 / WorldMapDetailFrame:GetScale()) end end

	WorldMapFrame_OnEvent(WorldMapFrame, "DISPLAY_SIZE_CHANGED")
	if (WorldMapFrame_UpdateQuests() > 0) then
		Magnify.RedrawSelectedQuest() -- Calling Magnify method
	end
end

function Magnify.GetElvUI()
	if ElvUI and ElvUI[1] then return ElvUI[1] end
	return nil
end

--- Get Mapster object, and configuration value for given key provided (or nil)
---@param configName string
function Magnify.GetMapster(configName)
	if (LibStub and LibStub:GetLibrary("AceAddon-3.0", true)) then
		local mapster = LibStub:GetLibrary("AceAddon-3.0"):GetAddon("Mapster", true)
		if (not mapster) then return mapster, nil end
		if (mapster.db and mapster.db.profile) then return mapster, mapster.db.profile[configName] end
	end
	return nil, nil
end

function Magnify.ElvUI_SetupWorldMapFrame()
	local worldMap = Magnify.GetElvUI():GetModule("WorldMap")
	if not worldMap then return end

	if (worldMap.coordsHolder and worldMap.coordsHolder.playerCoords) then updatePointRelativeTo(worldMap.coordsHolder.playerCoords, WorldMapScrollFrame) end

	if (WorldMapDetailFrame.backdrop) then
		WorldMapDetailFrame.backdrop:Hide()

		local _, worldMapRelativeFrame = WorldMapFrame.backdrop
		if (worldMapRelativeFrame == WorldMapDetailFrame) then updatePointRelativeTo(WorldMapFrame.backdrop, WorldMapScrollFrame) end
	end

	if (WorldMapFrame.backdrop) then
		-- We will take over the SetPoint behavior ElvUI, I'm sorry
		WorldMapFrame.backdrop.Point = function() return; end

		WorldMapFrame.backdrop:ClearAllPoints()
		if (WorldMapZoneMinimapDropDown:IsVisible()) then
			WorldMapFrame.backdrop:SetPoint("TOPLEFT", WorldMapZoneMinimapDropDown, "TOPLEFT", -20, 40)
		else
			WorldMapFrame.backdrop:SetPoint("TOPLEFT", WorldMapTitleButton, "TOPLEFT", 0, 0)
		end
		WorldMapFrame.backdrop:SetPoint("BOTTOM", WorldMapQuestShowObjectives, "BOTTOM", 0, 0)
		WorldMapFrame.backdrop:SetPoint("RIGHT", WorldMapFrameCloseButton, "RIGHT", 0, 0)
	end
end

function Magnify.SetupWorldMapFrame()
	WorldMapScrollFrameScrollBar:Hide()
	WorldMapFrame:EnableMouse(true)
	WorldMapScrollFrame:EnableMouse(true)
	WorldMapScrollFrame.panning = false
	WorldMapScrollFrame.moved = false

	if (WORLDMAP_SETTINGS.size == WORLDMAP_QUESTLIST_SIZE) then
		WorldMapScrollFrame:SetPoint("TOPLEFT", WorldMapPositioningGuide, "TOP", -726, -99);
		WorldMapTrackQuest:SetPoint("BOTTOMLEFT", WorldMapPositioningGuide, "BOTTOMLEFT", 8, 4);
	elseif (WORLDMAP_SETTINGS.size == WORLDMAP_WINDOWED_SIZE) then
		WorldMapTrackQuest:SetPoint("BOTTOMLEFT", WorldMapPositioningGuide, "BOTTOMLEFT", 16, -9);

		WorldMapFrame:SetPoint("TOPLEFT", WorldMapScreenAnchor, 0, 0);
		WorldMapFrame:SetScale(WorldMapScreenAnchor.preferredMinimodeScale);
		WorldMapFrame:SetMovable("true");
		WorldMapTitleButton:Show()
		WorldMapTitleButton:ClearAllPoints()
		WorldMapFrameTitle:Show()
		WorldMapFrameTitle:ClearAllPoints();
		WorldMapFrameTitle:SetPoint("CENTER", WorldMapTitleButton, "CENTER", 32, 0)

		if (WORLDMAP_SETTINGS.advanced) then
			WorldMapScrollFrame:SetPoint("TOPLEFT", 19, -42);
			WorldMapTitleButton:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", 13, 0)
		else
			WorldMapScrollFrame:SetPoint("TOPLEFT", 37, -66);
			WorldMapTitleButton:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", 13, -14)
		end

	else
		WorldMapScrollFrame:SetPoint("TOPLEFT", WorldMapPositioningGuide, "TOPLEFT", 11, -70.5);
		WorldMapTrackQuest:SetPoint("BOTTOMLEFT", WorldMapPositioningGuide, "BOTTOMLEFT", 16, -9);
	end

	WorldMapScrollFrame:SetScale(WORLDMAP_SETTINGS.size);

	Magnify.SetDetailFrameScale(1)
	WorldMapDetailFrame:SetAllPoints(WorldMapScrollFrame)
	WorldMapScrollFrame:SetHorizontalScroll(0)
	WorldMapScrollFrame:SetVerticalScroll(0)

	if (MagnifyOptions.enablePersistZoom and GetCurrentMapZone() == Magnify.PreviousState.zone) then
		Magnify.SetDetailFrameScale(Magnify.PreviousState.scale)
		WorldMapScrollFrame:SetHorizontalScroll(Magnify.PreviousState.panX)
		WorldMapScrollFrame:SetVerticalScroll(Magnify.PreviousState.panY)
	end

	WorldMapButton:SetScale(1)
	WorldMapButton:SetAllPoints(WorldMapDetailFrame)
	WorldMapButton:SetParent(WorldMapDetailFrame)

	-- Secure frame modifications: Only perform if not in combat to avoid taint
	if not InCombatLockdown() then
		if WorldMapPOIFrame:GetParent() ~= WorldMapDetailFrame then WorldMapPOIFrame:SetParent(WorldMapDetailFrame) end
		if WorldMapBlobFrame:GetParent() ~= WorldMapDetailFrame then
			WorldMapBlobFrame:SetParent(WorldMapDetailFrame)
			WorldMapBlobFrame:ClearAllPoints()
			WorldMapBlobFrame:SetAllPoints(WorldMapDetailFrame)
		end
		if WorldMapPlayer:GetParent() ~= WorldMapDetailFrame then WorldMapPlayer:SetParent(WorldMapDetailFrame) end
		if PlayerArrowFrame and PlayerArrowFrame:GetParent() ~= WorldMapDetailFrame then 
			PlayerArrowFrame:SetParent(WorldMapDetailFrame) 
		end
		if PlayerArrowEffectFrame and PlayerArrowEffectFrame:GetParent() ~= WorldMapDetailFrame then 
			PlayerArrowEffectFrame:SetParent(WorldMapDetailFrame) 
		end

		-- Parent party and raid icons to detail frame for correct relative positioning
		for i = 1, MAX_PARTY_MEMBERS do
			local partyFrame = _G["WorldMapParty" .. i]
			if partyFrame and partyFrame:GetParent() ~= WorldMapDetailFrame then
				partyFrame:SetParent(WorldMapDetailFrame)
			end
		end
		for i = 1, MAX_RAID_MEMBERS do
			local raidFrame = _G["WorldMapRaid" .. i]
			if raidFrame and raidFrame:GetParent() ~= WorldMapDetailFrame then
				raidFrame:SetParent(WorldMapDetailFrame)
			end
		end
	end

	updatePointRelativeTo(WorldMapQuestScrollFrame, WorldMapScrollFrame);
	updatePointRelativeTo(WorldMapQuestDetailScrollFrame, WorldMapScrollFrame);

	if (Magnify.GetElvUI()) then -- Calling Magnify method
		Magnify.ElvUI_SetupWorldMapFrame() -- Calling Magnify method
	end
end

function Magnify.WorldMapScrollFrame_OnPan(cursorX, cursorY)
	local dX = WorldMapScrollFrame.cursorX - cursorX
	local dY = cursorY - WorldMapScrollFrame.cursorY
	dX = dX / this:GetEffectiveScale()
	dY = dY / this:GetEffectiveScale()
	if abs(dX) >= 1 or abs(dY) >= 1 then
		WorldMapScrollFrame.moved = true

		local x
		x = max(0, dX + WorldMapScrollFrame.x)
		x = min(x, WorldMapScrollFrame.maxX)
		WorldMapScrollFrame:SetHorizontalScroll(x)

		local y
		y = max(0, dY + WorldMapScrollFrame.y)
		y = min(y, WorldMapScrollFrame.maxY)
		WorldMapScrollFrame:SetVerticalScroll(y)
		Magnify.AfterScrollOrPan()
	end
end

function Magnify.ColorWorldMapPartyMemberFrame(partyMemberFrame, unit)
	local classColor = RAID_CLASS_COLORS[select(2, UnitClass(unit))];
	if (classColor and not MagnifyOptions.enableOldPartyIcons) then
		partyMemberFrame.colorIcon:Show();
		partyMemberFrame.icon:Hide();
		partyMemberFrame.colorIcon:SetVertexColor(classColor.r, classColor.g, classColor.b, 1);
	else
		partyMemberFrame.colorIcon:Hide();
		partyMemberFrame.icon:Show();
	end
end

function Magnify.WorldMapButton_OnUpdate(self, elapsed)
	-- Only handle addon-specific functionality, let original function handle standard map updates

	-- Handle panning if in progress
	if WorldMapScrollFrame.panning then Magnify.WorldMapScrollFrame_OnPan(GetCursorPosition()) end

	-- Update player arrow with higher definition version
	local playerX, playerY = GetPlayerMapPosition("player");
	if not (playerX == 0 and playerY == 0) then
		local _, mapsterArrowScale = Magnify.GetMapster('arrowScale')
		if WorldMapPlayer.Icon then
			WorldMapPlayer.Icon:SetRotation(PlayerArrowFrame:GetFacing())
			WorldMapPlayer.Icon:SetSize(Magnify.PLAYER_ARROW_SIZE * (mapsterArrowScale or 1), Magnify.PLAYER_ARROW_SIZE * (mapsterArrowScale or 1))
		end
		-- Position the player arrow correctly relative to the scaled map
		local detailWidth = WorldMapDetailFrame:GetWidth()
		local detailHeight = WorldMapDetailFrame:GetHeight()
		local scale = WorldMapDetailFrame:GetScale()
		WorldMapPlayer:ClearAllPoints()
		WorldMapPlayer:SetPoint("CENTER", WorldMapDetailFrame, "TOPLEFT", playerX * detailWidth * scale, -playerY * detailHeight * scale)
		-- Position PlayerArrowFrame to match WorldMapPlayer
		if PlayerArrowFrame then
			PlayerArrowFrame:ClearAllPoints()
			PlayerArrowFrame:SetPoint("CENTER", WorldMapDetailFrame, "TOPLEFT", playerX * detailWidth * scale, -playerY * detailHeight * scale)
		end
		-- Position PlayerArrowEffectFrame to match WorldMapPlayer
		if PlayerArrowEffectFrame then
			PlayerArrowEffectFrame:ClearAllPoints()
			PlayerArrowEffectFrame:SetPoint("CENTER", WorldMapDetailFrame, "TOPLEFT", playerX * detailWidth * scale, -playerY * detailHeight * scale)
		end

		-- Hide default player texture every frame to ensure no duplicate
		if WorldMapPlayer.Player then WorldMapPlayer.Player:Hide() end
		if WorldMapPlayer.texture then WorldMapPlayer.texture:Hide() end
	end

	-- Update party and raid icon positions to prevent shifting on zoom
	local detailWidth = WorldMapDetailFrame:GetWidth()
	local detailHeight = WorldMapDetailFrame:GetHeight()
	local scale = WorldMapDetailFrame:GetScale()

	if WorldMapScrollFrame.zoomedIn then
		if GetNumRaidMembers() == 0 then
			-- Party mode
			for i = 1, MAX_PARTY_MEMBERS do
				local unit = "party" .. i
				if UnitExists(unit) then
					local icon = _G["WorldMapParty" .. i]
					if icon then
						local x, y = GetPlayerMapPosition(unit)
						if x > 0 and y > 0 then
							icon:ClearAllPoints()
							icon:SetPoint("CENTER", WorldMapDetailFrame, "TOPLEFT", x * detailWidth * scale, -y * detailHeight * scale)
						end
					end
				end
			end
		else
			-- Raid mode
			for i = 1, MAX_RAID_MEMBERS do
				local unit = "raid" .. i
				if UnitExists(unit) then
					local icon = _G["WorldMapRaid" .. i]
					if icon then
						local x, y = GetPlayerMapPosition(unit)
						if x > 0 and y > 0 then
							icon:ClearAllPoints()
							icon:SetPoint("CENTER", WorldMapDetailFrame, "TOPLEFT", x * detailWidth * scale, -y * detailHeight * scale)
						end
					end
				end
			end
		end
	end

	-- Apply class coloring to party/raid members if option is enabled
	if not MagnifyOptions.enableOldPartyIcons then
		-- Handle party members
		if GetNumRaidMembers() == 0 then
			for i = 1, MAX_PARTY_MEMBERS do
				local partyMemberFrame = _G["WorldMapParty" .. i];
				if partyMemberFrame and partyMemberFrame:IsVisible() then Magnify.ColorWorldMapPartyMemberFrame(partyMemberFrame, "party" .. i); end
			end
		else
			-- Handle raid members
			for i = 1, MAX_RAID_MEMBERS do
				local partyMemberFrame = _G["WorldMapRaid" .. i];
				if partyMemberFrame and partyMemberFrame:IsVisible() and partyMemberFrame.unit then Magnify.ColorWorldMapPartyMemberFrame(partyMemberFrame, partyMemberFrame.unit); end
			end
		end
	end
end

function Magnify.WorldMapScrollFrame_OnMouseWheel()
	if (IsControlKeyDown() and WORLDMAP_SETTINGS.size == WORLDMAP_WINDOWED_SIZE) then
		local oldScale = WorldMapFrame:GetScale()
		local newScale = oldScale + arg1 * Magnify.MINIMODE_ZOOM_STEP
		newScale = max(Magnify.MINIMODE_MIN_ZOOM, newScale)
		newScale = min(Magnify.MINIMODE_MAX_ZOOM, newScale)

		WorldMapFrame:SetScale(newScale)
		WorldMapScreenAnchor.preferredMinimodeScale = newScale
		return
	end

	local oldScrollH = this:GetHorizontalScroll()
	local oldScrollV = this:GetVerticalScroll()

	local cursorX, cursorY = GetCursorPosition()
	cursorX = cursorX / this:GetEffectiveScale()
	cursorY = cursorY / this:GetEffectiveScale()

	local frameX = cursorX - this:GetLeft()
	local frameY = this:GetTop() - cursorY

	local oldScale = WorldMapDetailFrame:GetScale()
	local newScale
	newScale = oldScale * (1.0 + arg1 * MagnifyOptions.zoomStep)
	newScale = max(Magnify.MIN_ZOOM, newScale)
	newScale = min(MagnifyOptions.maxZoom, newScale)

	Magnify.SetDetailFrameScale(newScale)

	this.maxX = ((WorldMapDetailFrame:GetWidth() * newScale) - this:GetWidth()) / newScale
	this.maxY = ((WorldMapDetailFrame:GetHeight() * newScale) - this:GetHeight()) / newScale
	this.zoomedIn = WorldMapDetailFrame:GetScale() > Magnify.MIN_ZOOM

	local centerX = oldScrollH + frameX / oldScale
	local centerY = oldScrollV + frameY / oldScale
	local newScrollH = centerX - frameX / newScale
	local newScrollV = centerY - frameY / newScale

	newScrollH = min(newScrollH, this.maxX)
	newScrollH = max(0, newScrollH)
	newScrollV = min(newScrollV, this.maxY)
	newScrollV = max(0, newScrollV)

	this:SetHorizontalScroll(newScrollH)
	this:SetVerticalScroll(newScrollV)
	Magnify.AfterScrollOrPan()
end

function Magnify.WorldMapButton_OnMouseDown()
	if arg1 == 'LeftButton' and WorldMapScrollFrame.zoomedIn then
		WorldMapScrollFrame.panning = true

		local x, y = GetCursorPosition()

		WorldMapScrollFrame.cursorX = x
		WorldMapScrollFrame.cursorY = y
		WorldMapScrollFrame.x = WorldMapScrollFrame:GetHorizontalScroll()
		WorldMapScrollFrame.y = WorldMapScrollFrame:GetVerticalScroll()
		WorldMapScrollFrame.moved = false
	end
end

function Magnify.WorldMapButton_OnMouseUp()
	WorldMapScrollFrame.panning = false

	if not WorldMapScrollFrame.moved then
		WorldMapButton_OnClick(WorldMapButton, arg1)

		Magnify.SetDetailFrameScale(Magnify.MIN_ZOOM)

		WorldMapScrollFrame:SetHorizontalScroll(0)
		WorldMapScrollFrame:SetVerticalScroll(0)
		Magnify.AfterScrollOrPan()

		WorldMapScrollFrame.zoomedIn = false
	end

	WorldMapScrollFrame.moved = false
end

function Magnify.RedrawSelectedQuest()
	if (WORLDMAP_SETTINGS.selectedQuestId) then
		-- try to select previously selected quest
		WorldMapFrame_SelectQuestById(WORLDMAP_SETTINGS.selectedQuestId);
	else
		-- select the first quest
		WorldMapFrame_SelectQuestFrame(_G["WorldMapQuestFrame1"]);
	end
end

function Magnify.CreateClassColorIcon(partyMemberFrame)
	if (partyMemberFrame) then
		partyMemberFrame.colorIcon = partyMemberFrame:CreateTexture(nil, "ARTWORK");
		partyMemberFrame.colorIcon:SetAllPoints(partyMemberFrame);
		partyMemberFrame.colorIcon:SetTexture('Interface\\AddOns\\' .. ADDON_NAME .. '\\assets\\WorldMapPlayer');
		partyMemberFrame.icon:Hide();
	end
end

function Magnify.OnFirstLoad()
	-- Make sure all settings got initalized
	MagnifyOptions.enablePersistZoom = MagnifyOptions.enablePersistZoom or Magnify.ENABLEPERSISTZOOM_DEFAULT
	MagnifyOptions.enableOldPartyIcons = MagnifyOptions.enableOldPartyIcons or Magnify.ENABLEOLDPARTYICONS_DEFAULT
	MagnifyOptions.maxZoom = MagnifyOptions.maxZoom or Magnify.MAXZOOM_DEFAULT
	MagnifyOptions.zoomStep = MagnifyOptions.zoomStep or Magnify.ZOOMSTEP_DEFAULT

	WorldMapScrollFrame:SetScrollChild(WorldMapDetailFrame)
	WorldMapScrollFrame:SetScript("OnMouseWheel", Magnify.WorldMapScrollFrame_OnMouseWheel)
	WorldMapButton:SetScript("OnMouseDown", Magnify.WorldMapButton_OnMouseDown)
	WorldMapButton:SetScript("OnMouseUp", Magnify.WorldMapButton_OnMouseUp)
	WorldMapDetailFrame:SetParent(WorldMapScrollFrame)

	WorldMapFrameAreaFrame:SetParent(WorldMapFrame)
	WorldMapFrameAreaFrame:SetFrameLevel(WORLDMAP_POI_FRAMELEVEL)
	WorldMapFrameAreaFrame:SetPoint("TOP", WorldMapScrollFrame, "TOP", 0, -10)

	-- Not worth getting this ugly ping working
	WorldMapPing.Show = function() return end
	WorldMapPing:SetModelScale(0)

	-- Add higher definition arrow that will get masked correctly on pan
	-- (Default player arrow stays visible even if you pan it to be off the map)
	WorldMapPlayer.Icon = WorldMapPlayer:CreateTexture(nil, 'ARTWORK')
	WorldMapPlayer.Icon:SetSize(Magnify.PLAYER_ARROW_SIZE, Magnify.PLAYER_ARROW_SIZE)
	WorldMapPlayer.Icon:SetPoint("CENTER", 0, 0)
	WorldMapPlayer.Icon:SetTexture('Interface\\AddOns\\' .. ADDON_NAME .. '\\assets\\WorldMapArrow')

	-- Hide default player texture to avoid duplicate
	if WorldMapPlayer.Player then
		WorldMapPlayer.Player:Hide()
	end
	if WorldMapPlayer.texture then
		WorldMapPlayer.texture:Hide()
	end

	hooksecurefunc("WorldMapFrame_SetFullMapView", Magnify.SetupWorldMapFrame);
	hooksecurefunc("WorldMapFrame_SetQuestMapView", Magnify.SetupWorldMapFrame);
	hooksecurefunc("WorldMap_ToggleSizeDown", Magnify.SetupWorldMapFrame);
	hooksecurefunc("WorldMap_ToggleSizeUp", Magnify.SetupWorldMapFrame);
	hooksecurefunc("WorldMapFrame_UpdateQuests", Magnify.ResizeQuestPOIs);
	-- Removed invalid hook for WotLK: hooksecurefunc("WorldMapFrame_SetPOIMaxBounds", Magnify.SetPOIMaxBounds); -- This function doesn't exist in 3.3.5

	hooksecurefunc("WorldMapQuestShowObjectives_AdjustPosition", function()
		if (WORLDMAP_SETTINGS.size == WORLDMAP_WINDOWED_SIZE) then
			WorldMapQuestShowObjectives:SetPoint("BOTTOMRIGHT", WorldMapPositioningGuide, "BOTTOMRIGHT", -30 - WorldMapQuestShowObjectivesText:GetWidth(), -9);
		else
			WorldMapQuestShowObjectives:SetPoint("BOTTOMRIGHT", WorldMapPositioningGuide, "BOTTOMRIGHT", -15 - WorldMapQuestShowObjectivesText:GetWidth(), 4);
		end
	end);

	WorldMapScreenAnchor:StartMoving();
	WorldMapScreenAnchor:SetPoint("TOPLEFT", 10, -118);
	WorldMapScreenAnchor:StopMovingOrSizing();

	-- Magic good default scale ratio based on screen height
	WorldMapScreenAnchor.preferredMinimodeScale = 1 + (0.4 * WorldMapFrame:GetHeight() / WorldFrame:GetHeight())

	WorldMapTitleButton:SetScript("OnDragStart", function()
		WorldMapScreenAnchor:ClearAllPoints();
		WorldMapFrame:ClearAllPoints();
		WorldMapFrame:StartMoving();
	end)

	WorldMapTitleButton:SetScript("OnDragStop", function()
		WorldMapFrame:StopMovingOrSizing();

		-- move the anchor
		WorldMapScreenAnchor:StartMoving();
		WorldMapScreenAnchor:SetPoint("TOPLEFT", WorldMapFrame);
		WorldMapScreenAnchor:StopMovingOrSizing();
	end)

	-- Store the original OnUpdate function BEFORE setting our custom one
	local original_WorldMapButton_OnUpdate = WorldMapButton:GetScript("OnUpdate")
	WorldMapButton:SetScript("OnUpdate", function(self, elapsed)
		-- Call original function first to preserve default behavior (including area labels)
		if original_WorldMapButton_OnUpdate then original_WorldMapButton_OnUpdate(self, elapsed) end
		-- Then call our custom update function for zoom/pan functionality
		Magnify.WorldMapButton_OnUpdate(self, elapsed)
	end)

	-- Store the original OnShow function and hook into it
	local original_WorldMapFrame_OnShow = WorldMapFrame:GetScript("OnShow")
	WorldMapFrame:SetScript("OnShow", function(self)
		original_WorldMapFrame_OnShow(self)
		Magnify.SetupWorldMapFrame()
	end)

	-- Create class color textures for party and raid frames
	for i = 1, MAX_RAID_MEMBERS do
		Magnify.CreateClassColorIcon(_G["WorldMapParty" .. i]);
		Magnify.CreateClassColorIcon(_G["WorldMapRaid" .. i]);
	end
end

function Magnify.OnEvent(self, event, addonName)
	if event == "ADDON_LOADED" and addonName == ADDON_NAME then
		Magnify.OnFirstLoad()
		Magnify.InitOptions()
	end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", Magnify.OnEvent)
