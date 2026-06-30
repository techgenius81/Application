-- Discord: @crazy_awesome_developer | FuseMachineController.lua

local module = {}

-- // Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

-- // Modules
local Player = Players.LocalPlayer
local Net = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Net"))
local GuiController = require(ReplicatedStorage:WaitForChild("Controllers"):WaitForChild("GuiController"))
local TimeUtils = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("TimeUtils"))
local NumberUtils = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("NumberUtils"))
local Functions = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Functions"))

-- // Data
local Datas = ReplicatedStorage:WaitForChild("Datas")
local BrainrotData = require(Datas:WaitForChild("Brainrots"))
local RarityData = require(Datas:WaitForChild("Rarities"))

-- // Assets
local GradientFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("GradientPresets")
local Models = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Brainrots")
local AnimationsFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Animations")

-- // Interface
local PlayerGui = Player:WaitForChild("PlayerGui")
local FuseMachineGui = PlayerGui:WaitForChild("HUD"):WaitForChild("FuseMachine")
local Buy = FuseMachineGui:WaitForChild("Buy")
local BuyLabel = Buy:WaitForChild("TextLabel")
local Close = FuseMachineGui:WaitForChild("Top"):WaitForChild("Close")
local Contents = FuseMachineGui:WaitForChild("Contents")
local FusionsFolder = Contents:WaitForChild("Fusions")
local Template = FusionsFolder:WaitForChild("Template")
local TimerLabel = Contents:WaitForChild("Timer")
local BrainrotsFolder = Contents:WaitForChild("Brainrots")
local BrainrotTemplate = BrainrotsFolder:WaitForChild("Template")

-- // Machine
local Machine = workspace:WaitForChild("Machines").FuseMachine
local BillboardGui = Machine:WaitForChild("Overhead"):WaitForChild("BillboardGui")
local Amount = BillboardGui:WaitForChild("Amount")
local ProximityPrompt = Machine:WaitForChild("Prompt"):WaitForChild("ProximityPrompt")

-- // Events
local InsertedEvent = Net:RemoteEvent("FuseMachine.Inserted")
local PossibleFusionsEvent = Net:RemoteEvent("FuseMachine.PossibleFusions")
local FuseResultEvent = Net:RemoteEvent("FuseMachine.Result")
local BuyFuseEvent = Net:RemoteEvent("FuseMachine.Buy")
local SyncFuseStateEvent = Net:RemoteEvent("FuseMachine.SyncState")
local FuseTimerEvent = Net:RemoteEvent("FuseMachine.Timer")
local ReturnSlotsEvent = Net:RemoteEvent("FuseMachine.ReturnSlot")
local ClaimEvent = Net:RemoteEvent("FuseMachine.Claim")

-- // Constants
local MAX_FUSE_SLOTS = 4
local FUSE_DURATION = 60

-- // Products
local CLAIM_PRODUCT_ID = require(ReplicatedStorage:WaitForChild("Datas").Shop)["Skip Fuse Timer"].Id

-- // State
local CurrentCost = 0
local FuseTimerActive = false
local TimerDone = false
local CurrentSlotCount = 0
local CurrentPossibleFusions = {}

local function ClearViewport(Viewport)
	for _, Child in ipairs(Viewport:GetChildren()) do
		if Child:IsA("Model") or Child:IsA("Camera") or Child:IsA("WorldModel") then
			Child:Destroy()
		end
	end
end

local function PlaceModelInViewport(ModelTemplate, Viewport)
	ClearViewport(Viewport)

	local WorldModel = Instance.new("WorldModel")
	WorldModel.Parent = Viewport

	local Clone = ModelTemplate:Clone()
	Clone.Parent = WorldModel

	local Root = Clone:FindFirstChildWhichIsA("BasePart")
	if Root then
		Root.Anchored = true
	end

	Clone:PivotTo(Clone:GetPivot() * CFrame.Angles(0, math.rad(-205), 0))

	local CF, Size = Clone:GetBoundingBox()
	local Dist = math.max(Size.X, Size.Y, Size.Z) * 2

	local Cam = Instance.new("Camera")
	Cam.CFrame = CFrame.new(CF.Position + Vector3.new(0, Size.Y * 0.25, Dist), CF.Position)
	Cam.FieldOfView = 35
	Cam.Parent = Viewport
	Viewport.CurrentCamera = Cam

	task.defer(function()
		local Animation = AnimationsFolder:FindFirstChild(Clone.Name)
		if not Animation then return end

		local AnimId = Animation.AnimationId
		if not AnimId or AnimId == "" then return end

		local Controller = Clone:FindFirstChildWhichIsA("AnimationController")
		if not Controller then return end

		local Animator = Controller:FindFirstChildWhichIsA("Animator")
		if not Animator then return end

		local Anim = Instance.new("Animation")
		Anim.AnimationId = AnimId

		local Track = Animator:LoadAnimation(Anim)
		Track.Looped = true
		Track:Play()
	end)
end

-- Clears all existing Fusion viewport frames

local function ClearFusionCards()
	for _, Child in ipairs(FusionsFolder:GetChildren()) do
		if Child ~= Template and Child:IsA("ViewportFrame") then
			Child:Destroy()
		end
	end
end

-- Clears all existing Brainrot viewport frames

local function ClearBrainrotCards()
	for _, Child in ipairs(BrainrotsFolder:GetChildren()) do
		if Child ~= BrainrotTemplate and Child:IsA("Frame") then
			Child:Destroy()
		end
	end
end

local function SetBuyButtonEnabled(Enabled)
	Buy.Visible = Enabled
end

-- Updates the fusion time label

local function UpdateTimerLabel(SlotCount, TimeRemaining, IsCountingDown)
	if SlotCount == 0 then
		TimerLabel.Visible = false
		return
	end

	local Seconds = IsCountingDown and TimeRemaining or FUSE_DURATION
	TimerLabel.Visible = true
	TimerLabel.Text = string.format('Fusion Time (<font color="rgb(0,170,255)">%ds</font>)', math.ceil(Seconds))
end

local function ClearRarityColor(Label)
	for _, Child in ipairs(Label:GetChildren()) do
		if Child:IsA("UIGradient") then
			Child:Destroy()
		end
	end
end

-- Applies rarity color to the label called by cloning the gradient from gradients folder and then applying it by parenting it to the label

local function ApplyRarityColor(BrainrotName, Label)
	local Info = BrainrotData[BrainrotName]
	local Rarity = Info and RarityData[Info.Rarity]

	if not Rarity then return end

	ClearRarityColor(Label)

	if Rarity.GradientPreset and Rarity.GradientPreset ~= "" then
		local GradientTemplate = GradientFolder:FindFirstChild(Rarity.GradientPreset)
		if GradientTemplate then
			local GradientClone = GradientTemplate:Clone()
			GradientClone:AddTag("Gradient")
			GradientClone.Parent = Label
			Label.TextColor3 = Color3.fromRGB(255, 255, 255)
			return
		else
			warn("no gradient?")
		end
	end

	Label.TextColor3 = Rarity.Color
end

local function HideReturnButtons()
	for _, Card in ipairs(BrainrotsFolder:GetChildren()) do
		if Card == BrainrotTemplate then continue end
		local ReturnButton = Card:FindFirstChild("Return")
		if ReturnButton then
			ReturnButton.Visible = false
		end
	end
end

-- Creates the brainrot card for one that is currently inside the fuse machine and modifies the textlabels to match the brainrot's data

local function SpawnBrainrotCard(SlotData)
	local Card = BrainrotTemplate:Clone()
	Card.Name = SlotData.UUID
	Card.Visible = true
	Card.Parent = BrainrotsFolder

	local DisplayNameLabel = Card:FindFirstChild("DisplayName")
	if DisplayNameLabel then
		DisplayNameLabel.Text = SlotData.Name
	end

	local RarityLabel = Card:FindFirstChild("Rarity")
	local BrainrotInfo = BrainrotData[SlotData.Name]
	if RarityLabel and BrainrotInfo then
		RarityLabel.Text = BrainrotInfo.Rarity
		ApplyRarityColor(SlotData.Name, RarityLabel)
	end

	local ReturnButton = Card:FindFirstChild("Return")
	if ReturnButton then
		ReturnButton.Visible = not FuseTimerActive
		ReturnButton.MouseButton1Click:Connect(function()
			if FuseTimerActive then return end
			ReturnSlotsEvent:FireServer(SlotData.UUID)
		end)
	end

	local Viewport = Card:WaitForChild("ViewportFrame")
	local ModelTemplate = Viewport and Models:FindFirstChild(SlotData.Name)
	if ModelTemplate then
		PlaceModelInViewport(ModelTemplate, Viewport)
	end
end

local function ShowPossibleFusions(Fusions, Cost)
	ClearFusionCards()
	CurrentCost = Cost
	BuyLabel.Text = "$" .. NumberUtils.Format(Cost)

	for _, Fusion in ipairs(Fusions) do
		local Card = Template:Clone()
		Card.Name = Fusion.Name
		Card.Visible = true
		Card.Parent = FusionsFolder

		local ChanceLabel = Card:FindFirstChild("Chance")
		if ChanceLabel then
			ChanceLabel.Text = tostring(Fusion.Chance) .. "%"
			ChanceLabel.Visible = true
		end

		local ModelTemplate = Models:FindFirstChild(Fusion.Name)
		if ModelTemplate then
			PlaceModelInViewport(ModelTemplate, Card)
		end
	end
end

-- Sets the countdown by modifiyng the proximityprompt's objectText and actionText based on the remaining time

local function SetPromptCountdown(Remaining)
	if Remaining <= 0 then
		ProximityPrompt.ObjectText = "Fuse Machine"
		ProximityPrompt.ActionText = "Claim"
		TimerDone = true
	else
		ProximityPrompt.ObjectText = TimeUtils.Format(Remaining)
		ProximityPrompt.ActionText = "Skip Fuse"
		TimerDone = false
	end
end

local function ResetPrompt()
	ProximityPrompt.ObjectText = "Fuse Machine"
	ProximityPrompt.ActionText = "Open"
	TimerDone = false
end

function module.Start()
	Template.Visible = false
	BrainrotTemplate.Visible = false
	TimerLabel.Visible = false
	SetBuyButtonEnabled(false)

	ProximityPrompt.Triggered:Connect(function()
		if TimerDone then
			ClaimEvent:FireServer()
			return
		end

		if FuseTimerActive then
			MarketplaceService:PromptProductPurchase(Player, CLAIM_PRODUCT_ID)
			return
		end

		if FuseMachineGui.Visible then
			GuiController.Hide(FuseMachineGui)
		else
			GuiController.Show(FuseMachineGui)
		end
	end)

	Close.MouseButton1Click:Connect(function()
		GuiController.Hide(FuseMachineGui)
	end)

	InsertedEvent.OnClientEvent:Connect(function(Count, Max, Slots)
		CurrentSlotCount = Count
		Amount.Text = tostring(Count) .. "/" .. tostring(Max)

		ClearBrainrotCards()
		for _, SlotData in ipairs(Slots) do
			SpawnBrainrotCard(SlotData)
		end

		UpdateTimerLabel(Count, FUSE_DURATION, false)

		if Count < Max then
			SetBuyButtonEnabled(false)
		end
	end)

	PossibleFusionsEvent.OnClientEvent:Connect(function(Fusions, Cost)
		FuseTimerActive = false
		CurrentPossibleFusions = Fusions
		ShowPossibleFusions(Fusions, Cost)
		SetBuyButtonEnabled(CurrentSlotCount >= MAX_FUSE_SLOTS)
	end)

	FuseTimerEvent.OnClientEvent:Connect(function(Remaining)
		if Remaining <= 0 then
			FuseTimerActive = false
			TimerDone = true
			Amount.Text = "CLAIM"
			SetPromptCountdown(0)
			SetBuyButtonEnabled(false)
			UpdateTimerLabel(CurrentSlotCount, 0, true)
		else
			FuseTimerActive = true
			TimerDone = false
			Amount.Text = TimeUtils.Format(Remaining)
			SetBuyButtonEnabled(false)
			SetPromptCountdown(Remaining)
			GuiController.Hide(FuseMachineGui)
			HideReturnButtons()
		end
	end)

	SyncFuseStateEvent.OnClientEvent:Connect(function(Slots, PossibleFusions, Cost, TimeRemaining)
		CurrentSlotCount = #Slots
		Amount.Text = tostring(#Slots) .. "/" .. tostring(MAX_FUSE_SLOTS)

		ClearBrainrotCards()
		for _, SlotData in ipairs(Slots) do
			SpawnBrainrotCard(SlotData)
		end

		if TimeRemaining and TimeRemaining > 0 then
			FuseTimerActive = true
			TimerDone = false
			Amount.Text = TimeUtils.Format(TimeRemaining)
			UpdateTimerLabel(#Slots, TimeRemaining, true)
			SetPromptCountdown(TimeRemaining)
			if #PossibleFusions > 0 then
				CurrentPossibleFusions = PossibleFusions
				ShowPossibleFusions(PossibleFusions, Cost)
			end
			SetBuyButtonEnabled(false)
			HideReturnButtons()
		elseif TimeRemaining == 0 then
			FuseTimerActive = false
			TimerDone = true
			Amount.Text = "CLAIM"
			SetPromptCountdown(0)
			UpdateTimerLabel(#Slots, 0, true)
			if #PossibleFusions > 0 then
				CurrentPossibleFusions = PossibleFusions
				ShowPossibleFusions(PossibleFusions, Cost)
			end
			SetBuyButtonEnabled(false)
		elseif #PossibleFusions > 0 then
			FuseTimerActive = false
			TimerDone = false
			CurrentPossibleFusions = PossibleFusions
			UpdateTimerLabel(#Slots, FUSE_DURATION, false)
			ShowPossibleFusions(PossibleFusions, Cost)
			ResetPrompt()
			SetBuyButtonEnabled(#Slots >= MAX_FUSE_SLOTS)
		else
			FuseTimerActive = false
			TimerDone = false
			ClearFusionCards()
			UpdateTimerLabel(#Slots, FUSE_DURATION, false)
			SetBuyButtonEnabled(false)
			BuyLabel.Text = "$" .. NumberUtils.Format(Cost)
			ResetPrompt()
		end
	end)

	Buy.MouseButton1Click:Connect(function()
		if FuseTimerActive or not Buy.Active then return end
		BuyFuseEvent:FireServer()
	end)

	FuseResultEvent.OnClientEvent:Connect(function(ResultName)
		FuseTimerActive = false
		TimerDone = false
		CurrentSlotCount = 0

		local FusionNames = {}
		for _, Fusion in ipairs(CurrentPossibleFusions) do
			table.insert(FusionNames, Fusion.Name)
		end

		Functions.Cutscene(FusionNames, ResultName)

		ClearFusionCards()
		ClearBrainrotCards()
		TimerLabel.Visible = false
		Amount.Text = "0/" .. tostring(MAX_FUSE_SLOTS)
		BuyLabel.Text = "$0"
		SetBuyButtonEnabled(false)
		ResetPrompt()
		CurrentPossibleFusions = {}
	end)
end

return module
