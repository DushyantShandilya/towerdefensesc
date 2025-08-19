# towerdefensesc
-- Script made by Swifttle basically this is a placement script for a td game with range visuals 
-- SERVICES & DEPENDENCIES
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- CORE REFERENCES

local Camera = workspace.CurrentCamera
local Player = Players.LocalPlayer
local Mouse = Player:GetMouse()
local PlayerGui = Player:WaitForChild("PlayerGui")

-- GUI References
local UpgradeGui = PlayerGui:WaitForChild("TowerUpgradeGui")
local ControlsRoot = script.Parent
local Slot1Button = ControlsRoot.BOTTOMPART.Towers:WaitForChild("1")
local Slot2Button = ControlsRoot.BOTTOMPART.Towers:WaitForChild("2")

-- Remote Events
local EventsFolder = ReplicatedStorage:WaitForChild("Events")
local PlaceTowerRemote = EventsFolder:WaitForChild("PlaceTowerRequest")
local TowerPlacedEvent = EventsFolder:FindFirstChild("TowerPlaced") -- Optional

-- Tower Templates
local TowersFolder = ReplicatedStorage:WaitForChild("Towers")
local StrikerTowers = TowersFolder:WaitForChild("Striker")
local SoldierTowers = TowersFolder:WaitForChild("Soldier")

-- ══════════════════════════════════════════════════════════════════════════════════════
-- WORKSPACE SETUP
-- ══════════════════════════════════════════════════════════════════════════════════════

-- Create preview folder for tower previews (prevents them from being counted as placed towers)
local PreviewFolder = workspace:FindFirstChild("_TowerPreview")
if not PreviewFolder then
	PreviewFolder = Instance.new("Folder")
	PreviewFolder.Name = "_TowerPreview"
	PreviewFolder.Parent = workspace
end

-- ══════════════════════════════════════════════════════════════════════════════════════
-- CONFIGURATION & CONSTANTS
-- ══════════════════════════════════════════════════════════════════════════════════════

-- Visual Settings
local VALID_COLOR = Color3.fromRGB(172, 172, 172)          -- Color when tower can be placed
local INVALID_COLOR = Color3.fromRGB(255, 0, 0)            -- Color when tower cannot be placed
local HOVER_TRANSPARENCY = 0.3                              -- Transparency of preview tower
local PLACEMENT_RING_COLOR = Color3.new(1, 1, 1)          -- White color for placement rings
local ATTACK_RING_COLOR = Color3.fromRGB(100, 200, 255)   -- Blue color for attack range rings

-- Placement Settings
local MIN_TOWER_DISTANCE = 3.8                             -- Minimum distance between towers
local TOWER_MOVE_SMOOTHING = 0.2                           -- How smooth tower movement is (0-1)
local ROTATION_INCREMENT = 45                               -- Degrees to rotate per R key press
local RING_HEIGHT_OFFSET = 0.25                            -- How high above ground rings appear

-- Visual Quality Settings
local PLACEMENT_RING_SEGMENTS = 64                         -- Number of segments in placement rings
local ATTACK_RING_SEGMENTS = 120                           -- Number of segments in attack rings
local RING_BEAM_WIDTH = 0.24                               -- Width of ring beams

-- Animation Settings
local GUI_SCALE_DURATION = 0.18                            -- Duration of GUI scale animations
local GUI_FADE_DURATION = 0.14                             -- Duration of GUI fade animations

-- ══════════════════════════════════════════════════════════════════════════════════════
-- STATE VARIABLES
-- ══════════════════════════════════════════════════════════════════════════════════════

-- Placement State
local CurrentTowerPreview = nil                             -- Currently spawned preview tower
local IsCurrentlyPlacing = false                           -- Whether we're in placement mode
local CurrentRotationAngle = 0                             -- Current rotation angle in degrees
local CurrentTargetCFrame = nil                            -- Target CFrame for smooth movement
local CurrentTowerSource = nil                             -- Source folder for current tower type

-- Visual State
local PlacementRings = {}                                  -- Storage for all placement range rings
local SelectedTower = nil                                  -- Currently selected tower for attack range
local AttackRangeVisual = nil                              -- Current attack range visualization

-- ══════════════════════════════════════════════════════════════════════════════════════
-- UTILITY FUNCTIONS
-- ══════════════════════════════════════════════════════════════════════════════════════

--[[
	Safely finds the Configuration folder in a model
	
	@param model: Model - The model to search in
	@return Folder|nil - The Configuration folder or nil if not found
--]]
local function GetTowerConfiguration(model)
	if not model or not model:IsA("Model") then
		return nil
	end
	return model:FindFirstChild("Configuration")
end

--[[
	Gets the world position of a model, preferring PrimaryPart
	
	@param model: Model - The model to get position from
	@return Vector3 - The world position of the model
--]]
local function GetModelWorldPosition(model)
	if not model then 
		return Vector3.new(0, 0, 0) 
	end

	-- Prefer PrimaryPart if available
	if model.PrimaryPart then 
		return model.PrimaryPart.Position 
	end

	-- Fallback to first BasePart found
	local firstPart = model:FindFirstChildWhichIsA("BasePart", true)
	return firstPart and firstPart.Position or Vector3.new(0, 0, 0)
end

--[[
	Performs a raycast from the mouse position to the world
	
	@param ignoreList: table - List of instances to ignore in raycast
	@return RaycastResult|nil - The raycast result or nil if no hit
--]]
local function CastRayFromMouse(ignoreList)
	-- Get mouse position in screen space
	local mouseLocation = UserInputService:GetMouseLocation()

	-- Convert to world ray
	local cameraRay = Camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)

	-- Set up raycast parameters
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = ignoreList or {}

	-- Perform raycast with reasonable distance
	return workspace:Raycast(cameraRay.Origin, cameraRay.Direction * 1000, raycastParams)
end

--[[
	Prepares a model for use as a preview by setting visual properties
	
	@param model: Model - The model to prepare
--]]
local function SetupPreviewModelVisuals(model)
	if not model then 
		return 
	end

	-- Process all descendants to set up preview visuals
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			-- Hide utility parts
			if descendant.Name == "Range" or descendant.Name == "HitboxPart" then
				descendant.Transparency = 1
				descendant.CanTouch = false
				descendant.CanQuery = false
			else
				-- Style visible parts
				descendant.Color = VALID_COLOR
				descendant.Transparency = HOVER_TRANSPARENCY
			end
		end
	end
end

--[[
	Calculates the Y offset for proper tower placement on ground
	
	@param tower: Model - The tower model to calculate offset for
	@return number - The Y offset to use for placement
--]]
local function CalculateTowerHeightOffset(tower)
	if not tower then 
		return 1 
	end

	-- Check for Humanoid-based tower
	local humanoid = tower:FindFirstChild("Humanoid")
	if humanoid and tower.PrimaryPart then
		return humanoid.HipHeight + (tower.PrimaryPart.Size.Y / 2)
	end

	-- Fallback to PrimaryPart
	if tower.PrimaryPart then
		return tower.PrimaryPart.Size.Y / 2
	end

	-- Default fallback
	return 1
end

-- ══════════════════════════════════════════════════════════════════════════════════════
-- COLLISION & VALIDATION FUNCTIONS
-- ══════════════════════════════════════════════════════════════════════════════════════

--[[
	Checks if a position is too close to existing placed towers
	
	@param position: Vector3 - The position to check
	@return boolean - True if too close to existing towers
--]]
local function IsPositionTooCloseToExistingTowers(position)
	local placedTowersFolder = workspace:FindFirstChild("PlacedTowers")
	if not placedTowersFolder then 
		return false 
	end

	-- Check distance to all placed towers
	for _, placedTower in ipairs(placedTowersFolder:GetChildren()) do
		if placedTower:IsA("Model") then
			local towerPosition = GetModelWorldPosition(placedTower)
			local distance = (towerPosition - position).Magnitude

			if distance < MIN_TOWER_DISTANCE then
				return true
			end
		end
	end

	return false
end

--[[
	Checks if placement ranges would overlap at a given position
	
	@param centerPosition: Vector3 - The center position to check
	@param radius: number - The radius of the placement range
	@param ignoreModel: Model - Model to ignore in overlap check (usually the preview)
	@return boolean - True if ranges would overlap
--]]
local function WouldPlacementRangesOverlap(centerPosition, radius, ignoreModel)
	if radius <= 0 then 
		return false 
	end

	-- Check against placed towers
	local placedTowersFolder = workspace:FindFirstChild("PlacedTowers")
	if placedTowersFolder then
		for _, tower in ipairs(placedTowersFolder:GetChildren()) do
			if tower ~= ignoreModel and tower:IsA("Model") then
				local config = GetTowerConfiguration(tower)
				local placementRangeValue = config and config:FindFirstChild("PlacementRange")
				local otherRadius = placementRangeValue and placementRangeValue.Value or 0

				if otherRadius > 0 then
					local otherPosition = GetModelWorldPosition(tower)
					local distance = (otherPosition - centerPosition).Magnitude

					-- Check if circles overlap
					if distance < (otherRadius + radius) then
						return true
					end
				end
			end
		end
	end

	-- Check against preview towers
	for _, previewTower in ipairs(PreviewFolder:GetChildren()) do
		if previewTower ~= ignoreModel and previewTower:IsA("Model") then
			local config = GetTowerConfiguration(previewTower)
			local placementRangeValue = config and config:FindFirstChild("PlacementRange")
			local otherRadius = placementRangeValue and placementRangeValue.Value or 0

			if otherRadius > 0 then
				local otherPosition = GetModelWorldPosition(previewTower)
				local distance = (otherPosition - centerPosition).Magnitude

				if distance < (otherRadius + radius) then
					return true
				end
			end
		end
	end

	return false
end

--[[
	Validates if a tower can be placed at the given position
	
	@param position: Vector3 - The position to validate
	@param tower: Model - The tower model being placed
	@param raycastResult: RaycastResult - The raycast result for ground check
	@return boolean - True if position is valid for placement
--]]
local function IsValidPlacementPosition(position, tower, raycastResult)
	-- Check if we hit valid ground
	local validGround = raycastResult and CollectionService:HasTag(raycastResult.Instance, "Placeable")
	if not validGround then
		return false
	end

	-- Check distance to other towers
	if IsPositionTooCloseToExistingTowers(position) then
		return false
	end

	-- Check placement range overlaps
	local config = GetTowerConfiguration(tower)
	local placementRangeValue = config and config:FindFirstChild("PlacementRange")
	local placementRadius = placementRangeValue and placementRangeValue.Value or 0

	if placementRadius > 0 and WouldPlacementRangesOverlap(position, placementRadius, tower) then
		return false
	end

	return true
end

-- ══════════════════════════════════════════════════════════════════════════════════════
-- VISUAL RING SYSTEM
-- ══════════════════════════════════════════════════════════════════════════════════════

--[[
	Creates a visual ring around a tower to show range
	
	@param tower: Model - The tower to create ring around
	@param radius: number - Radius of the ring
	@param segments: number - Number of segments in the ring
	@param color: Color3 - Color of the ring
	@param ringName: string - Name for the ring folder
	@return Folder|nil - The created ring folder or nil if failed
--]]
local function CreateVisualRing(tower, radius, segments, color, ringName)
	if not tower or radius <= 0 then 
		return nil 
	end

	-- Find the origin part (prefer HitboxPart, fallback to any BasePart)
	local originPart = tower:FindFirstChild("HitboxPart") or tower:FindFirstChildWhichIsA("BasePart")
	if not originPart then 
		warn("CreateVisualRing: No suitable origin part found in tower:", tower.Name)
		return nil 
	end

	-- Remove any existing ring with the same name
	local existingRing = tower:FindFirstChild(ringName)
	if existingRing then
		existingRing:Destroy()
	end

	-- Create new ring folder
	local ringFolder = Instance.new("Folder")
	ringFolder.Name = ringName
	ringFolder.Parent = tower

	-- Calculate ring center position (slightly above ground to avoid Z-fighting)
	local centerPosition = originPart.Position + Vector3.new(0, RING_HEIGHT_OFFSET, 0)

	-- Create ring segments
	for segmentIndex = 1, segments do
		-- Calculate angles for current segment
		local currentAngle = (segmentIndex / segments) * math.pi * 2
		local nextAngle = ((segmentIndex % segments + 1) / segments) * math.pi * 2

		-- Calculate positions for beam endpoints
		local position1 = centerPosition + Vector3.new(
			math.cos(currentAngle) * radius,
			0,
			math.sin(currentAngle) * radius
		)
		local position2 = centerPosition + Vector3.new(
			math.cos(nextAngle) * radius,
			0,
			math.sin(nextAngle) * radius
		)

		-- Create invisible parts to hold attachments
		local part1 = Instance.new("Part")
		part1.Name = "RingAnchor1_" .. segmentIndex
		part1.Anchored = true
		part1.CanCollide = false
		part1.CanQuery = false
		part1.CanTouch = false
		part1.Transparency = 1
		part1.Size = Vector3.new(0.1, 0.1, 0.1)
		part1.Position = position1
		part1.Parent = ringFolder

		local part2 = Instance.new("Part")
		part2.Name = "RingAnchor2_" .. segmentIndex
		part2.Anchored = true
		part2.CanCollide = false
		part2.CanQuery = false
		part2.CanTouch = false
		part2.Transparency = 1
		part2.Size = Vector3.new(0.1, 0.1, 0.1)
		part2.Position = position2
		part2.Parent = ringFolder

		-- Create attachments for beam
		local attachment1 = Instance.new("Attachment")
		attachment1.Name = "BeamAttachment"
		attachment1.Parent = part1

		local attachment2 = Instance.new("Attachment")
		attachment2.Name = "BeamAttachment"
		attachment2.Parent = part2

		-- Create the visual beam
		local beam = Instance.new("Beam")
		beam.Name = "RingSegment"
		beam.Attachment0 = attachment1
		beam.Attachment1 = attachment2
		beam.Color = ColorSequence.new(color)
		beam.Width0 = RING_BEAM_WIDTH
		beam.Width1 = RING_BEAM_WIDTH
		beam.FaceCamera = false
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Transparency = NumberSequence.new(0.18)
		beam.Parent = part1
	end

	return ringFolder
end

--[[
	Updates the position of a ring to follow its tower
	FIXED: Now correctly positions rings relative to tower's current position
	
	@param ringFolder: Folder - The ring folder to update
	@param tower: Model - The tower the ring belongs to
	@param radius: number - The radius of the ring
--]]
local function UpdateRingPosition(ringFolder, tower, radius)
	if not ringFolder or not ringFolder.Parent or not tower then
		return
	end

	-- Find origin part
	local originPart = tower:FindFirstChild("HitboxPart") or tower:FindFirstChildWhichIsA("BasePart")
	if not originPart then
		return
	end

	-- Calculate new center position
	local newCenterPosition = originPart.Position + Vector3.new(0, RING_HEIGHT_OFFSET, 0)

	-- Update all ring anchor parts
	local segmentIndex = 1
	for _, child in ipairs(ringFolder:GetChildren()) do
		if child:IsA("Part") and child.Name:match("RingAnchor1_") then
			-- Extract segment number from part name
			local segmentNumber = tonumber(child.Name:match("RingAnchor1_(%d+)"))
			if segmentNumber then
				-- Calculate angles for this segment
				local segments = PLACEMENT_RING_SEGMENTS
				local currentAngle = (segmentNumber / segments) * math.pi * 2
				local nextAngle = ((segmentNumber % segments + 1) / segments) * math.pi * 2

				-- Update positions
				local position1 = newCenterPosition + Vector3.new(
					math.cos(currentAngle) * radius,
					0,
					math.sin(currentAngle) * radius
				)
				local position2 = newCenterPosition + Vector3.new(
					math.cos(nextAngle) * radius,
					0,
					math.sin(nextAngle) * radius
				)

				-- Find corresponding parts and update positions
				child.Position = position1

				local part2 = ringFolder:FindFirstChild("RingAnchor2_" .. segmentNumber)
				if part2 then
					part2.Position = position2
				end
			end
		end
	end
end

--[[
	Shows or updates the placement range ring for a tower
	
	@param tower: Model - The tower to show placement range for
--]]
local function ShowPlacementRangeRing(tower)
	if not tower then 
		return 
	end

	-- Get placement range from configuration
	local config = GetTowerConfiguration(tower)
	local placementRangeValue = config and config:FindFirstChild("PlacementRange")

	if not (placementRangeValue and placementRangeValue.Value > 0) then
		return
	end

	-- Create or update the ring
	local ringFolder = CreateVisualRing(
		tower,
		placementRangeValue.Value,
		PLACEMENT_RING_SEGMENTS,
		PLACEMENT_RING_COLOR,
		"PlacementRangeRing"
	)

	if ringFolder then
		PlacementRings[tower] = {
			folder = ringFolder,
			radius = placementRangeValue.Value
		}
	end
end

--[[
	Hides the placement range ring for a tower
	
	@param tower: Model - The tower to hide placement range for
--]]
local function HidePlacementRangeRing(tower)
	if not tower then 
		return 
	end

	-- Remove from tracking
	local ringData = PlacementRings[tower]
	if ringData and ringData.folder then
		ringData.folder:Destroy()
	end
	PlacementRings[tower] = nil
end

--[[
	Shows the attack range preview for a selected tower
	
	@param tower: Model - The tower to show attack range for
--]]
local function ShowAttackRangePreview(tower)
	if not tower then 
		return 
	end

	-- Hide previous attack range if different tower
	if SelectedTower and SelectedTower ~= tower then
		local oldAttackRange = SelectedTower:FindFirstChild("AttackRangeRing")
		if oldAttackRange then
			oldAttackRange:Destroy()
		end
	end

	SelectedTower = tower

	-- Get attack range from configuration
	local config = GetTowerConfiguration(tower)
	local attackRangeValue = config and config:FindFirstChild("Range")

	if not (attackRangeValue and attackRangeValue.Value > 0) then
		return
	end

	-- Create the attack range ring
	AttackRangeVisual = CreateVisualRing(
		tower,
		attackRangeValue.Value,
		ATTACK_RING_SEGMENTS,
		ATTACK_RING_COLOR,
		"AttackRangeRing"
	)
end

--[[
	Hides the attack range preview
--]]
local function HideAttackRangePreview()
	if SelectedTower then
		local attackRange = SelectedTower:FindFirstChild("AttackRangeRing")
		if attackRange then
			attackRange:Destroy()
		end
		SelectedTower = nil
		AttackRangeVisual = nil
	end
end

-- ══════════════════════════════════════════════════════════════════════════════════════
-- GUI ANIMATION SYSTEM
-- ══════════════════════════════════════════════════════════════════════════════════════

--[[
	Animates the upgrade GUI into view with professional scaling effect
--]]
local function AnimateGuiIn()
	if not UpgradeGui or not UpgradeGui:FindFirstChild("Main") then 
		return 
	end

	local mainFrame = UpgradeGui.Main

	-- Show the GUI immediately
	mainFrame.Visible = true

	-- Animate scale if UIScale exists
	local uiScale = mainFrame:FindFirstChildWhichIsA("UIScale", true)
	if uiScale then
		-- Start small for bounce effect
		uiScale.Scale = 0.92

		-- Create bounce animation (small to slightly large, then to normal)
		local expandTween = TweenService:Create(
			uiScale,
			TweenInfo.new(GUI_SCALE_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1.06 }
		)

		local settleTween = TweenService:Create(
			uiScale,
			TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = 1.0 }
		)

		-- Chain the animations
		expandTween:Play()
		expandTween.Completed:Connect(function()
			settleTween:Play()
		end)
	end
end

--[[
	Animates the upgrade GUI out of view with smooth scaling
--]]
local function AnimateGuiOut()
	if not UpgradeGui or not UpgradeGui:FindFirstChild("Main") then 
		return 
	end

	local mainFrame = UpgradeGui.Main

	-- Animate scale down if UIScale exists
	local uiScale = mainFrame:FindFirstChildWhichIsA("UIScale", true)
	if uiScale then
		local shrinkTween = TweenService:Create(
			uiScale,
			TweenInfo.new(GUI_FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Scale = 0.96 }
		)

		shrinkTween:Play()
		shrinkTween.Completed:Connect(function()
			mainFrame.Visible = false
		end)
	else
		-- Fallback if no UIScale
		mainFrame.Visible = false
	end
end

-- ══════════════════════════════════════════════════════════════════════════════════════
-- TOWER PLACEMENT SYSTEM
-- ══════════════════════════════════════════════════════════════════════════════════════

--[[
	Cancels the current tower placement operation
--]]
local function CancelTowerPlacement()
	-- Clean up preview tower and its visuals
	if CurrentTowerPreview then
		HidePlacementRangeRing(CurrentTowerPreview)
		CurrentTowerPreview:Destroy()
		CurrentTowerPreview = nil
	end

	-- Reset state
	IsCurrentlyPlacing = false
	CurrentTargetCFrame = nil
	CurrentTowerSource = nil
	CurrentRotationAngle = 0

	-- Unbind all placement controls
	ContextActionService:UnbindAction("PlaceTower")
	ContextActionService:UnbindAction("RotateTower")
	ContextActionService:UnbindAction("CancelTower")
end

--[[
	Attempts to place the current tower at the specified position
	
	@param targetPosition: Vector3 - The world position to place the tower
--]]
local function AttemptTowerPlacement(targetPosition)
	if not CurrentTowerPreview or not CurrentTowerSource then 
		warn("AttemptTowerPlacement: No tower preview or source available")
		return 
	end

	-- Perform final raycast to get ground position
	local raycastResult = CastRayFromMouse({ CurrentTowerPreview })
	if not raycastResult then
		warn("AttemptTowerPlacement: No valid ground found")
		return
	end

	-- Ensure we're placing on valid ground
	if not CollectionService:HasTag(raycastResult.Instance, "Placeable") then
		warn("AttemptTowerPlacement: Surface not tagged as Placeable")
		return
	end

	-- Calculate final position with proper height offset
	local heightOffset = CalculateTowerHeightOffset(CurrentTowerPreview)
	local finalPosition = Vector3.new(
		targetPosition.X,
		raycastResult.Position.Y + heightOffset,
		targetPosition.Z
	)

	-- Validate the position one final time
	if not IsValidPlacementPosition(finalPosition, CurrentTowerPreview, raycastResult) then
		warn("AttemptTowerPlacement: Position validation failed")
		return
	end

	-- Create final CFrame with rotation
	local finalCFrame = CFrame.new(finalPosition) * CFrame.Angles(0, math.rad(CurrentRotationAngle), 0)

	-- Send placement request to server
	local success = pcall(function()
		PlaceTowerRemote:FireServer(
			CurrentTowerPreview.Name,
			finalCFrame,
			CurrentTowerSource.Name
		)
	end)

	if not success then
		warn("AttemptTowerPlacement: Failed to send placement request to server")
		return
	end

	print("Tower placement request sent successfully!")

	-- Clean up placement mode
	CancelTowerPlacement()
end

--[[
	Starts the tower placement process for a specific tower type
	
	@param towerSourceFolder: Folder - The folder containing tower templates
	@param towerTemplateName: string - The name of the tower template to place
--]]
local function StartTowerPlacement(towerSourceFolder, towerTemplateName)
	-- Cancel any existing placement
	CancelTowerPlacement()

	-- Validate inputs
	if not towerSourceFolder then
		warn("StartTowerPlacement: Invalid tower source folder")
		return
	end

	local towerTemplate = towerSourceFolder:FindFirstChild(towerTemplateName)
	if not towerTemplate then
		warn("StartTowerPlacement: Tower template not found:", towerTemplateName, "in", towerSourceFolder.Name)
		return
	end

	-- Store source for server communication
	CurrentTowerSource = towerSourceFolder

	-- Clone the tower template for preview
	CurrentTowerPreview = towerTemplate:Clone()

	-- Set up PrimaryPart if not already set
	if not CurrentTowerPreview.PrimaryPart then
		CurrentTowerPreview.PrimaryPart = CurrentTowerPreview:FindFirstChild("HumanoidRootPart") 
			or CurrentTowerPreview:FindFirstChildWhichIsA("BasePart")
	end

	-- Position at origin initially (will be moved by render loop)
	if CurrentTowerPreview.PivotTo then
		pcall(function() 
			CurrentTowerPreview:PivotTo(CFrame.new(0, 0, 0)) 
		end)
	else
		-- Fallback for older models
		for _, part in ipairs(CurrentTowerPreview:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CFrame = CFrame.new(0, 0, 0)
			end
		end
	end

	-- Parent to preview folder (keeps it separate from placed towers)
	CurrentTowerPreview.Parent = PreviewFolder

	-- Set up visual styling for preview
	SetupPreviewModelVisuals(CurrentTowerPreview)

	-- Show placement range ring immediately
	ShowPlacementRangeRing(CurrentTowerPreview)

	-- Reset rotation and enable placement mode
	CurrentRotationAngle = 0
	IsCurrentlyPlacing = true

	print("Started placement for:", towerTemplateName, "from", towerSourceFolder.Name)

	-- ═══ BIND PLACEMENT CONTROLS ═══

	-- Primary placement action (Left Click / Touch)
	ContextActionService:BindAction(
		"PlaceTower",
		function(actionName, inputState, inputObject)
			if inputState == Enum.UserInputState.Begin then
				-- Get current mouse position
				local raycast = CastRayFromMouse({ CurrentTowerPreview })
				if not raycast then return end

				-- Validate placement
				if CollectionService:HasTag(raycast.Instance, "Placeable") then
					local heightOffset = CalculateTowerHeightOffset(CurrentTowerPreview)
					local proposedPosition = Vector3.new(
						raycast.Position.X,
						raycast.Position.Y + heightOffset,
						raycast.Position.Z
					)

					-- Only place if position is valid
					if IsValidPlacementPosition(proposedPosition, CurrentTowerPreview, raycast) then
						AttemptTowerPlacement(proposedPosition)
					else
						print("Cannot place tower here - invalid position")
					end
				else
					print("Cannot place tower here - invalid surface")
				end
			end
		end,
		false, -- Don't create touch button
		Enum.UserInputType.MouseButton1,
		Enum.UserInputType.Touch
	)

	-- Tower rotation action (R key)
	ContextActionService:BindAction(
		"RotateTower",
		function(actionName, inputState, inputObject)
			if inputState == Enum.UserInputState.Begin then
				CurrentRotationAngle = (CurrentRotationAngle + ROTATION_INCREMENT) % 360
				print("Rotated tower to", CurrentRotationAngle, "degrees")
			end
		end,
		false, -- Don't create touch button
		Enum.KeyCode.R
	)

	-- Cancel placement action (Q key / Right Click)
	ContextActionService:BindAction(
		"CancelTower",
		function(actionName, inputState, inputObject)
			if inputState == Enum.UserInputState.Begin then
				print("Tower placement cancelled")
				CancelTowerPlacement()
			end
		end,
		false, -- Don't create touch button
		Enum.KeyCode.Q,
		Enum.UserInputType.MouseButton2
	)
end

-- ══════════════════════════════════════════════════════════════════════════════════════
-- MAIN RENDER LOOP
-- ══════════════════════════════════════════════════════════════════════════════════════

--[[
	Main render loop that handles tower preview movement and visual updates
	This runs every frame while in placement mode
--]]
RunService.RenderStepped:Connect(function(deltaTime)
	-- Only run during placement mode
	if not IsCurrentlyPlacing or not CurrentTowerPreview then 
		return 
	end

	-- Cast ray from mouse to world
	local raycastResult = CastRayFromMouse({ CurrentTowerPreview })
	if not raycastResult then 
		-- No valid surface found, keep tower at last known position
		return 
	end

	-- Calculate target position with proper height offset
	local heightOffset = CalculateTowerHeightOffset(CurrentTowerPreview)
	local targetPosition = Vector3.new(
		raycastResult.Position.X,
		raycastResult.Position.Y + heightOffset,
		raycastResult.Position.Z
	)

	-- Create target CFrame with current rotation
	local targetCFrame = CFrame.new(targetPosition) * CFrame.Angles(0, math.rad(CurrentRotationAngle), 0)

	-- Smooth movement using lerp
	CurrentTargetCFrame = CurrentTargetCFrame and CurrentTargetCFrame:Lerp(targetCFrame, TOWER_MOVE_SMOOTHING) or targetCFrame

	-- Apply the CFrame to the tower
	if CurrentTowerPreview.PivotTo then
		-- Modern method (preferred)
		pcall(function()
			CurrentTowerPreview:PivotTo(CurrentTargetCFrame)
		end)
	elseif CurrentTowerPreview.PrimaryPart then
		-- Legacy method
		pcall(function()
			CurrentTowerPreview:SetPrimaryPartCFrame(CurrentTargetCFrame)
		end)
	end

	-- Update placement ring position to follow tower
	local ringData = PlacementRings[CurrentTowerPreview]
	if ringData then
		UpdateRingPosition(ringData.folder, CurrentTowerPreview, ringData.radius)
	end

	-- ═══ VISUAL VALIDATION FEEDBACK ═══

	-- Determine if current position is valid for placement
	local config = GetTowerConfiguration(CurrentTowerPreview)
	local placementRangeValue = config and config:FindFirstChild("PlacementRange")
	local placementRadius = placementRangeValue and placementRangeValue.Value or 0

	-- Run all validation checks
	local validGround = CollectionService:HasTag(raycastResult.Instance, "Placeable")
	local notTooClose = not IsPositionTooCloseToExistingTowers(targetPosition)
	local noRangeOverlap = not WouldPlacementRangesOverlap(targetPosition, placementRadius, CurrentTowerPreview)

	local isValidPosition = validGround and notTooClose and noRangeOverlap

	-- Apply visual feedback based on validation
	local feedbackColor = isValidPosition and VALID_COLOR or INVALID_COLOR

	-- Update all visible parts of the tower preview
	for _, part in ipairs(CurrentTowerPreview:GetDescendants()) do
		if part:IsA("BasePart") then
			-- Skip utility parts
			if part.Name ~= "Range" and part.Name ~= "HitboxPart" then
				part.Color = feedbackColor
				part.Transparency = HOVER_TRANSPARENCY
			end
		end
	end
end)

-- ══════════════════════════════════════════════════════════════════════════════════════
-- INPUT HANDLING
-- ══════════════════════════════════════════════════════════════════════════════════════

--[[
	Handles mouse clicks for tower selection and GUI management
--]]
Mouse.Button1Down:Connect(function()
	-- Don't interfere with placement mode
	if IsCurrentlyPlacing then 
		return 
	end

	-- Get the clicked object
	local clickedObject = Mouse.Target
	if not clickedObject then
		-- Clicked on empty space - hide GUI and attack preview
		AnimateGuiOut()
		HideAttackRangePreview()
		return
	end

	-- Find the model that was clicked
	local clickedModel = clickedObject:FindFirstAncestorOfClass("Model")

	-- Check if it's a valid tower (has Configuration)
	if clickedModel and GetTowerConfiguration(clickedModel) then
		-- Show attack range and GUI for this tower
		ShowAttackRangePreview(clickedModel)
		AnimateGuiIn()
		print("Selected tower:", clickedModel.Name)
	else
		-- Clicked on something that's not a tower
		AnimateGuiOut()
		HideAttackRangePreview()
	end
end)

-- ══════════════════════════════════════════════════════════════════════════════════════
-- SERVER EVENT HANDLERS
-- ══════════════════════════════════════════════════════════════════════════════════════

--[[
	Handles server notification of successful tower placement
--]]
if TowerPlacedEvent then
	TowerPlacedEvent.OnClientEvent:Connect(function(placedTower)
		if not placedTower or not placedTower:IsA("Model") then
			warn("TowerPlaced event received invalid tower:", tostring(placedTower))
			return
		end

		print("Server confirmed tower placement:", placedTower.Name)

		-- Wait a brief moment for the tower to fully initialize
		task.wait(0.1)

		-- Show persistent placement range ring
		ShowPlacementRangeRing(placedTower)
	end)
end

--[[
	Fallback system: Monitor PlacedTowers folder for new additions
	This ensures rings appear even if TowerPlaced event is not available
--]]
local placedTowersFolder = workspace:FindFirstChild("PlacedTowers")
if placedTowersFolder then
	placedTowersFolder.ChildAdded:Connect(function(newChild)
		-- Only process Model instances
		if not newChild:IsA("Model") then 
			return 
		end

		print("Detected new tower in PlacedTowers:", newChild.Name)

		-- Wait for the model to fully load
		local startTime = tick()
		while not newChild.PrimaryPart and not newChild:FindFirstChildWhichIsA("BasePart", true) do
			if tick() - startTime > 2 then -- 2 second timeout
				warn("Timeout waiting for tower parts to load:", newChild.Name)
				break
			end
			task.wait(0.1)
		end

		-- Show placement ring for the new tower
		ShowPlacementRangeRing(newChild)
	end)
end

-- ══════════════════════════════════════════════════════════════════════════════════════
-- USER INTERFACE BINDINGS
-- ══════════════════════════════════════════════════════════════════════════════════════

--[[
	Button click handlers for tower selection
--]]

-- Slot 1 - Striker Tower
Slot1Button.Activated:Connect(function()
	print("Slot 1 activated - Starting Striker tower placement")
	StartTowerPlacement(StrikerTowers, "0")
end)

-- Slot 2 - Soldier Tower
Slot2Button.Activated:Connect(function()
	print("Slot 2 activated - Starting Soldier tower placement")
	StartTowerPlacement(SoldierTowers, "0")
end)

--[[
	Keyboard hotkey bindings
--]]

-- Hotkey 1 - Striker Tower
ContextActionService:BindAction(
	"HotkeySlot1",
	function(actionName, inputState, inputObject)
		if inputState == Enum.UserInputState.Begin then
			print("Hotkey 1 pressed - Starting Striker tower placement")
			StartTowerPlacement(StrikerTowers, "0")
		end
	end,
	false, -- Don't create touch button
	Enum.KeyCode.One
)

-- Hotkey 2 - Soldier Tower
ContextActionService:BindAction(
	"HotkeySlot2",
	function(actionName, inputState, inputObject)
		if inputState == Enum.UserInputState.Begin then
			print("Hotkey 2 pressed - Starting Soldier tower placement")
			StartTowerPlacement(SoldierTowers, "0")
		end
	end,
	false, -- Don't create touch button
	Enum.KeyCode.Two
)

-- ══════════════════════════════════════════════════════════════════════════════════════
-- CLEANUP & INITIALIZATION
-- ══════════════════════════════════════════════════════════════════════════════════════

--[[
	Clean up any existing placement rings on script start
--]]
local function InitializeScript()
	-- Clean up any existing rings from previous script runs
	for _, model in ipairs(workspace:GetDescendants()) do
		if model:IsA("Model") then
			local placementRing = model:FindFirstChild("PlacementRangeRing")
			local attackRing = model:FindFirstChild("AttackRangeRing")

			if placementRing then placementRing:Destroy() end
			if attackRing then attackRing:Destroy() end
		end
	end

	-- Show rings for any already-placed towers
	local placedFolder = workspace:FindFirstChild("PlacedTowers")
	if placedFolder then
		for _, tower in ipairs(placedFolder:GetChildren()) do
			if tower:IsA("Model") and GetTowerConfiguration(tower) then
				ShowPlacementRangeRing(tower)
			end
		end
	end

end

-- ══════════════════════════════════════════════════════════════════════════════════════
-- SCRIPT STARTUP
-- ══════════════════════════════════════════════════════════════════════════════════════

-- Initialize the system
InitializeScript()

