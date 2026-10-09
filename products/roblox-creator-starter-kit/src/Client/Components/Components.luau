--[[
	Components (ModuleScript, ReplicatedStorage.StarterKit.UI.Components)

	Small, dependency-free UI component library built from code, so it is
	easy to read, diff and restyle. Every component returns a Roblox Instance.
	Change the look in one place: Components.Theme.

	Components:
		Panel(title, size)                -> window with header + close button
		Button(text, style?)              -> rounded button with hover/press tweens
		CurrencyPill(currency)            -> icon dot + animated amount
		ProgressBar()                     -> bar with :SetAttribute("Progress", 0..1)
		QuestCard(quest)                  -> title, progress, reward, claim button
		ShopCard(name, subtitle, price)   -> card with buy button
		InventorySlot(slot, equipped)     -> grid cell with rarity stroke
		Toast(parent, text, kind)         -> temporary notification

	NOTE: Uses Roblox UI APIs; not executed in Roblox Studio by the kit author.
	See docs/STUDIO_TEST_CHECKLIST.md.
]]

local TweenService = game:GetService("TweenService")

local Components = {}

Components.Theme = {
	Background = Color3.fromHex("#141826"),
	Surface = Color3.fromHex("#1E2436"),
	SurfaceRaised = Color3.fromHex("#2A3148"),
	Stroke = Color3.fromHex("#3A4360"),
	Text = Color3.fromHex("#F4F6FB"),
	TextMuted = Color3.fromHex("#9AA3BA"),
	Primary = Color3.fromHex("#5B8CFF"),
	PrimaryDark = Color3.fromHex("#3F6BE0"),
	Success = Color3.fromHex("#2FBF71"),
	Danger = Color3.fromHex("#E5484D"),
	Warning = Color3.fromHex("#F5A524"),
	Font = Enum.Font.GothamMedium,
	FontBold = Enum.Font.GothamBold,
	Radius = UDim.new(0, 12),
	Rarity = {
		Common = Color3.fromHex("#9AA3BA"),
		Uncommon = Color3.fromHex("#2FBF71"),
		Rare = Color3.fromHex("#5B8CFF"),
		Epic = Color3.fromHex("#A855F7"),
		Legendary = Color3.fromHex("#F5A524"),
	},
}

local Theme = Components.Theme
local FAST = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SMOOTH = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local function create(className: string, props: { [string]: any }, children: { Instance }?): Instance
	local instance = Instance.new(className)
	for prop, value in props do
		(instance :: any)[prop] = value
	end
	for _, child in (children or {}) :: { Instance } do
		child.Parent = instance
	end
	return instance
end
Components.create = create

local function corner(radius: UDim?): Instance
	return create("UICorner", { CornerRadius = radius or Theme.Radius })
end

local function stroke(color: Color3?, thickness: number?): Instance
	return create("UIStroke", {
		Color = color or Theme.Stroke,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function padding(px: number): Instance
	return create("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
	})
end
Components.padding = padding

local function label(text: string, size: number, color: Color3?, bold: boolean?): TextLabel
	return create("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size,
		TextColor3 = color or Theme.Text,
		Font = if bold then Theme.FontBold else Theme.Font,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, 0, 0, size + 4),
	}) :: TextLabel
end
Components.label = label

function Components.tween(instance: Instance, props: { [string]: any }, info: TweenInfo?)
	local tween = TweenService:Create(instance, info or SMOOTH, props)
	tween:Play()
	return tween
end

-- Button ---------------------------------------------------------------------
function Components.Button(text: string, style: string?): TextButton
	local base = if style == "success" then Theme.Success
		elseif style == "danger" then Theme.Danger
		elseif style == "ghost" then Theme.SurfaceRaised
		else Theme.Primary
	local button = create("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = base,
		Text = text,
		TextColor3 = Theme.Text,
		TextSize = 16,
		Font = Theme.FontBold,
		Size = UDim2.new(0, 120, 0, 36),
	}, { corner(UDim.new(0, 10)) }) :: TextButton
	local scale = create("UIScale", { Scale = 1 }) :: UIScale
	scale.Parent = button
	button.MouseEnter:Connect(function()
		Components.tween(button, { BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), 0.12) }, FAST)
	end)
	button.MouseLeave:Connect(function()
		Components.tween(button, { BackgroundColor3 = base }, FAST)
		Components.tween(scale, { Scale = 1 }, FAST)
	end)
	button.MouseButton1Down:Connect(function()
		Components.tween(scale, { Scale = 0.95 }, FAST)
	end)
	button.MouseButton1Up:Connect(function()
		Components.tween(scale, { Scale = 1 }, FAST)
	end)
	return button
end

function Components.setButtonEnabled(button: TextButton, enabled: boolean)
	button.Active = enabled
	button.AutoButtonColor = false
	button.TextTransparency = if enabled then 0 else 0.45
	button.BackgroundTransparency = if enabled then 0 else 0.5
end

-- Panel ----------------------------------------------------------------------
-- Returns (panel, contentFrame, closeButton)
function Components.Panel(title: string, size: UDim2): (Frame, Frame, TextButton)
	local panel = create("Frame", {
		Name = title .. "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = size,
		BackgroundColor3 = Theme.Background,
		Visible = false,
	}, {
		corner(UDim.new(0, 18)),
		stroke(Theme.Stroke, 2),
		create("UISizeConstraint", { MaxSize = Vector2.new(720, 560) }),
		create("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Theme.Surface, Theme.Background),
		}),
	}) :: Frame

	local header = create("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 56),
	}, { padding(14) })
	header.Parent = panel

	local titleLabel = label(title, 22, Theme.Text, true)
	titleLabel.Size = UDim2.new(1, -48, 1, 0)
	titleLabel.Parent = header

	local close = Components.Button("X", "ghost")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.new(1, 0, 0.5, 0)
	close.Size = UDim2.fromOffset(32, 32)
	close.Parent = header

	local content = create("ScrollingFrame", {
		Name = "Content",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 1, -56),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Stroke,
	}, { padding(14) }) :: Frame
	content.Parent = panel

	close.Activated:Connect(function()
		Components.hidePanel(panel)
	end)
	return panel, content, close
end

function Components.showPanel(panel: Frame)
	local scale = panel:FindFirstChildOfClass("UIScale") or create("UIScale", { Parent = panel })
	;(scale :: UIScale).Scale = 0.85
	panel.Visible = true
	Components.tween(scale, { Scale = 1 })
end

function Components.hidePanel(panel: Frame)
	panel.Visible = false
end

function Components.listLayout(parent: Instance, gap: number)
	create("UIListLayout", {
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

-- Currency pill --------------------------------------------------------------
function Components.CurrencyPill(currency: { id: string, label: string, color: string }): Frame
	local pill = create("Frame", {
		Name = currency.id,
		BackgroundColor3 = Theme.Surface,
		Size = UDim2.fromOffset(150, 40),
	}, {
		corner(UDim.new(1, 0)),
		stroke(),
		create("Frame", {
			Name = "Icon",
			BackgroundColor3 = Color3.fromHex(currency.color),
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.fromOffset(24, 24),
		}, { corner(UDim.new(1, 0)), stroke(Color3.new(1, 1, 1), 1) }),
	}) :: Frame
	local amount = label("0", 18, Theme.Text, true)
	amount.Name = "Amount"
	amount.Position = UDim2.fromOffset(40, 9)
	amount.Size = UDim2.new(1, -48, 0, 22)
	amount.Parent = pill
	return pill
end

-- Animates the number shown in a CurrencyPill and pops it when it increases.
function Components.setCurrency(pill: Frame, value: number, format: (number) -> string)
	local amount = pill:FindFirstChild("Amount") :: TextLabel
	local previous = (pill:GetAttribute("Value") :: number?) or value
	pill:SetAttribute("Value", value)
	amount.Text = format(value)
	if value > previous then
		amount.TextColor3 = Theme.Success
		Components.tween(amount, { TextColor3 = Theme.Text }, TweenInfo.new(0.6))
	end
end

-- Progress bar ---------------------------------------------------------------
function Components.ProgressBar(): Frame
	local bar = create("Frame", {
		Name = "ProgressBar",
		BackgroundColor3 = Theme.SurfaceRaised,
		Size = UDim2.new(1, 0, 0, 10),
	}, { corner(UDim.new(1, 0)) }) :: Frame
	local fill = create("Frame", {
		Name = "Fill",
		BackgroundColor3 = Theme.Primary,
		Size = UDim2.fromScale(0, 1),
	}, {
		corner(UDim.new(1, 0)),
		create("UIGradient", { Color = ColorSequence.new(Theme.Primary, Theme.Success) }),
	})
	fill.Parent = bar
	bar:GetAttributeChangedSignal("Progress"):Connect(function()
		local p = math.clamp((bar:GetAttribute("Progress") :: number?) or 0, 0, 1)
		Components.tween(fill, { Size = UDim2.fromScale(p, 1) })
	end)
	return bar
end

-- Quest card -----------------------------------------------------------------
-- quest = { id, title, progress, target, claimed, reward = { currency, amount } }
function Components.QuestCard(quest: any, onClaim: (string) -> ()): Frame
	local card = create("Frame", {
		Name = quest.id,
		BackgroundColor3 = Theme.Surface,
		Size = UDim2.new(1, 0, 0, 92),
	}, { corner(), stroke(), padding(12) }) :: Frame

	local title = label(quest.title, 17, Theme.Text, true)
	title.Size = UDim2.new(1, -130, 0, 22)
	title.Parent = card

	local sub = label(string.format("%d / %d  ·  Reward: %d %s", quest.progress, quest.target, quest.reward.amount, quest.reward.currency), 14, Theme.TextMuted)
	sub.Position = UDim2.fromOffset(0, 26)
	sub.Size = UDim2.new(1, -130, 0, 18)
	sub.Parent = card

	local bar = Components.ProgressBar()
	bar.Position = UDim2.new(0, 0, 1, -10)
	bar.Size = UDim2.new(1, -130, 0, 10)
	bar.Parent = card
	bar:SetAttribute("Progress", quest.progress / quest.target)

	local done = quest.progress >= quest.target
	local button = Components.Button(if quest.claimed then "Claimed" elseif done then "Claim" else "In progress", if done and not quest.claimed then "success" else "ghost")
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.fromScale(1, 0.5)
	button.Parent = card
	Components.setButtonEnabled(button, done and not quest.claimed)
	button.Activated:Connect(function()
		if button.Active then
			onClaim(quest.id)
		end
	end)
	return card
end

-- Shop card ------------------------------------------------------------------
function Components.ShopCard(name: string, subtitle: string, priceText: string, onBuy: () -> (), disabledText: string?): Frame
	local card = create("Frame", {
		Name = name,
		BackgroundColor3 = Theme.Surface,
	}, { corner(), stroke(), padding(12) }) :: Frame

	local title = label(name, 17, Theme.Text, true)
	title.Parent = card
	local sub = label(subtitle, 14, Theme.TextMuted)
	sub.TextWrapped = true
	sub.TextTruncate = Enum.TextTruncate.None
	sub.Position = UDim2.fromOffset(0, 24)
	sub.Size = UDim2.new(1, 0, 0, 36)
	sub.Parent = card

	local button = Components.Button(disabledText or priceText, if disabledText then "ghost" else "primary")
	button.AnchorPoint = Vector2.new(0, 1)
	button.Position = UDim2.fromScale(0, 1)
	button.Size = UDim2.new(1, 0, 0, 34)
	button.Parent = card
	Components.setButtonEnabled(button, disabledText == nil)
	button.Activated:Connect(function()
		if button.Active then
			onBuy()
		end
	end)
	return card
end

-- Inventory slot -------------------------------------------------------------
function Components.InventorySlot(slot: any?, equipped: boolean, onClick: (() -> ())?): TextButton
	local rarityColor = if slot then (Theme.Rarity[slot.rarity] or Theme.Rarity.Common) else Theme.Stroke
	local cell = create("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = if equipped then Theme.SurfaceRaised else Theme.Surface,
		Text = "",
	}, { corner(UDim.new(0, 10)), stroke(rarityColor, if equipped then 3 else 1.5) }) :: TextButton
	if slot then
		local name = label(slot.name, 13, Theme.Text, true)
		name.TextXAlignment = Enum.TextXAlignment.Center
		name.TextWrapped = true
		name.TextTruncate = Enum.TextTruncate.None
		name.Size = UDim2.new(1, -8, 0.6, 0)
		name.Position = UDim2.new(0, 4, 0.1, 0)
		name.Parent = cell
		if slot.count > 1 then
			local count = label("x" .. slot.count, 12, Theme.TextMuted, true)
			count.TextXAlignment = Enum.TextXAlignment.Right
			count.AnchorPoint = Vector2.new(1, 1)
			count.Position = UDim2.new(1, -6, 1, -4)
			count.Size = UDim2.fromOffset(40, 14)
			count.Parent = cell
		end
		if onClick then
			cell.Activated:Connect(onClick)
		end
	end
	return cell
end

-- Toast ----------------------------------------------------------------------
function Components.Toast(parent: Instance, text: string, kind: string?)
	local color = if kind == "success" then Theme.Success elseif kind == "error" then Theme.Danger else Theme.Primary
	local toast = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -60),
		Size = UDim2.fromOffset(320, 44),
		BackgroundColor3 = Theme.Surface,
		ZIndex = 50,
	}, { corner(UDim.new(0, 10)), stroke(color, 2) })
	local msg = label(text, 16, Theme.Text, true)
	msg.TextXAlignment = Enum.TextXAlignment.Center
	msg.Size = UDim2.fromScale(1, 1)
	msg.ZIndex = 51
	msg.Parent = toast
	toast.Parent = parent
	Components.tween(toast, { Position = UDim2.new(0.5, 0, 0, 16) })
	task.delay(2.5, function()
		local out = Components.tween(toast, { Position = UDim2.new(0.5, 0, 0, -60) })
		out.Completed:Wait()
		toast:Destroy()
	end)
end

return Components
