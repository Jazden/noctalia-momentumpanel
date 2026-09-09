--!nonstrict
-- Panel for Sennheiser Momentum
-- Battery gauge, Noise Cancellation, Transparency slider, Bass Boost, and Settings.

local SNAPSHOT_KEY = "momentum_snapshot"
local COMMAND_KEY = "momentum_command"

local snapshot = noctalia.state.get(SNAPSHOT_KEY) or {}
local settingsExpanded = true

local commandSeq = 0
local function sendCommand(action, value)
	commandSeq += 1
	noctalia.state.set(COMMAND_KEY, {
		action = action,
		value = value,
		nonce = tostring(noctalia.nowMs()) .. "-" .. tostring(commandSeq),
	})
end

local function levelFraction(level)
	local n = tonumber(level)
	if n == nil or n < 0 then
		return 0
	end
	return math.max(0, math.min(100, n)) / 100
end

local function isLow(level, charging)
	return level ~= nil and level >= 0 and level <= 20 and not charging
end

local function headerIconPath()
	local isDark = noctalia.isDarkMode()
	return isDark and "icons/momentum.svg" or "icons/momentum-light.svg"
end

local function render()
	local connected = snapshot.connected == true
	local body = {}

	if connected then
		-- 1. Battery Gauge Card
		local bLevel = tonumber(snapshot.battery) or -1
		local hasLevel = bLevel >= 0
		local charging = snapshot.charging == true
		local low = isLow(bLevel, charging)
		local fillRole = "primary"
		if low then
			fillRole = "error"
		elseif charging then
			fillRole = "secondary"
		elseif not hasLevel then
			fillRole = "outline"
		end

		local statusMeta = charging and (noctalia.tr("panel.charging") or "Charging") or (noctalia.tr("panel.status.connected") or "Connected")

		table.insert(body, ui.column({
			align = "center",
			justify = "center",
			gap = 6,
			padding = 12,
		}, {
			ui.row({ align = "center", gap = 8 }, {
				ui.image({
					path = headerIconPath(),
					width = 24,
					height = 24,
					fit = "contain",
				}),
				ui.label({
					text = hasLevel and (tostring(bLevel) .. "%") or "--%",
					fontSize = 24,
					fontWeight = "bold",
					color = low and "error" or "on_surface",
				}),
			}),
			ui.progress({
				progress = levelFraction(bLevel),
				height = 6,
				radius = 3,
				fill = fillRole,
				width = 160,
			}),
			ui.label({
				text = statusMeta,
				fontSize = 11,
				color = "on_surface_variant",
			}),
		}))

		table.insert(body, ui.separator({ thickness = 1, color = "outline/0.2" }))

		-- 2. Noise Control Section
		local currentMode = snapshot.noise_mode or "off"
		table.insert(body, ui.column({ gap = 6 }, {
			ui.label({
				text = noctalia.tr("panel.noise_control") or "Noise Control",
				fontSize = 11,
				fontWeight = "bold",
				color = "on_surface_variant",
			}),
			ui.row({ align = "center", gap = 4 }, {
				ui.button({
					key = "mode-anc",
					flexGrow = 1,
					text = "Noise Cancelling",
					glyph = "shield-check",
					variant = (currentMode == "active" or currentMode == "anc") and "primary" or "ghost",
					selected = (currentMode == "active" or currentMode == "anc"),
					onClick = function()
						snapshot.noise_mode = "active"
						render()
						sendCommand("set_noise_mode", "active")
					end,
				}),
				ui.button({
					key = "mode-transparency",
					flexGrow = 1,
					text = "Transparency",
					glyph = "ear",
					variant = (currentMode == "aware" or currentMode == "transparency") and "secondary" or "ghost",
					selected = (currentMode == "aware" or currentMode == "transparency"),
					onClick = function()
						snapshot.noise_mode = "aware"
						render()
						sendCommand("set_noise_mode", "aware")
					end,
				}),
				ui.button({
					key = "mode-off",
					flexGrow = 1,
					text = "Off",
					glyph = "headphones",
					variant = (currentMode == "off") and "outline" or "ghost",
					selected = (currentMode == "off"),
					onClick = function()
						snapshot.noise_mode = "off"
						render()
						sendCommand("set_noise_mode", "off")
					end,
				}),
			}),
		}))

		-- 3. Transparency Level Slider
		if snapshot.anc_enabled ~= false then
			local curTrans = tonumber(snapshot.transparency) or 50
			table.insert(body, ui.column({ gap = 4, paddingV = 4 }, {
				ui.row({ align = "center", justify = "space_between" }, {
					ui.label({
						text = noctalia.tr("panel.transparency_level") or "Transparency Level",
						fontSize = 12,
						fontWeight = "medium",
						color = "on_surface",
					}),
					ui.label({
						text = tostring(curTrans) .. "%",
						fontSize = 12,
						fontWeight = "bold",
						color = "secondary",
					}),
				}),
				ui.slider({
					value = curTrans,
					min = 0,
					max = 100,
					step = 5,
					onChange = function(val)
						local num = math.floor(tonumber(val) or 50)
						snapshot.transparency = num
						if num >= 50 and snapshot.noise_mode ~= "aware" then
							snapshot.noise_mode = "aware"
						elseif num < 50 and snapshot.noise_mode ~= "active" then
							snapshot.noise_mode = "active"
						end
						render()
						sendCommand("set_transparency", num)
					end,
				}),
			}))
		end

		table.insert(body, ui.separator({ thickness = 1, color = "outline/0.2" }))

		-- 4. Settings Section (Accordion)
		local settingsHeader = ui.row({
			align = "center",
			justify = "space_between",
			onClick = function()
				settingsExpanded = not settingsExpanded
				render()
			end,
		}, {
			ui.row({ align = "center", gap = 6 }, {
				ui.glyph({ name = "adjustments-horizontal", size = 14, color = "on_surface_variant" }),
				ui.label({
					text = noctalia.tr("panel.settings_section") or "Settings",
					fontSize = 11,
					fontWeight = "bold",
					color = "on_surface_variant",
				}),
			}),
			ui.button({
				glyph = settingsExpanded and "chevron-up" or "chevron-down",
				variant = "ghost",
				controlSize = "sm",
				onClick = function()
					settingsExpanded = not settingsExpanded
					render()
				end,
			}),
		})

		local settingsContent = { settingsHeader }

		if settingsExpanded then
			-- Bass Boost Card
			table.insert(settingsContent, ui.row({ align = "center", justify = "space_between", gap = 8, paddingV = 4 }, {
				ui.column({ flexGrow = 1, gap = 1 }, {
					ui.label({ text = noctalia.tr("panel.bass_boost") or "Bass Boost", fontSize = 13, color = "on_surface" }),
					ui.label({ text = noctalia.tr("panel.bass_boost_desc") or "Enhance low-end frequencies", fontSize = 11, color = "on_surface_variant" }),
				}),
				ui.toggle({
					checked = snapshot.bass_boost == true,
					onChange = function(v)
						local enabled = (v == true or v == "true")
						snapshot.bass_boost = enabled
						sendCommand("set_bass_boost", enabled)
						render()
					end,
				}),
			}))

			-- Smart Pause (Wear Detection)
			table.insert(settingsContent, ui.row({ align = "center", justify = "space_between", gap = 8, paddingV = 4 }, {
				ui.column({ flexGrow = 1, gap = 1 }, {
					ui.label({ text = noctalia.tr("panel.wear_detection") or "Smart Pause", fontSize = 13, color = "on_surface" }),
					ui.label({ text = noctalia.tr("panel.wear_detection_desc") or "Pause audio automatically when removed", fontSize = 11, color = "on_surface_variant" }),
				}),
				ui.label({
					text = snapshot.wear_detection and "Active" or "Off",
					fontSize = 12,
					color = snapshot.wear_detection and "secondary" or "on_surface_variant",
					fontWeight = "bold",
				}),
			}))

			-- Sidetone
			table.insert(settingsContent, ui.row({ align = "center", justify = "space_between", gap = 8, paddingV = 4 }, {
				ui.column({ flexGrow = 1, gap = 1 }, {
					ui.label({ text = noctalia.tr("panel.sidetone") or "Sidetone", fontSize = 13, color = "on_surface" }),
					ui.label({ text = noctalia.tr("panel.sidetone_desc") or "Hear your own voice naturally", fontSize = 11, color = "on_surface_variant" }),
				}),
				ui.label({
					text = (snapshot.sidetone and snapshot.sidetone > 0) and "Enabled" or "Off",
					fontSize = 12,
					color = (snapshot.sidetone and snapshot.sidetone > 0) and "secondary" or "on_surface_variant",
					fontWeight = "bold",
				}),
			}))
		end

		table.insert(body, ui.column({ gap = 8 }, settingsContent))

	else
		-- Disconnected View
		local notConnChildren = {
			ui.image({
				path = headerIconPath(),
				width = 48,
				height = 48,
				fit = "contain",
				opacity = 0.35,
			}),
			ui.label({
				text = noctalia.tr("widget.not_connected") or "Headphones not connected",
				fontSize = 14,
				fontWeight = "medium",
				color = "on_surface",
				textAlign = "center",
			}),
			ui.label({
				text = noctalia.tr("panel.guidance") or "Connect your Sennheiser Momentum headphones via Bluetooth.",
				fontSize = 12,
				color = "on_surface_variant",
				textAlign = "center",
				maxLines = 3,
			}),
			ui.button({
				text = noctalia.tr("panel.connect_button") or "Connect Headphones",
				variant = "primary",
				glyph = "bluetooth",
				onClick = function()
					sendCommand("connect", nil)
				end,
			}),
		}

		table.insert(body, ui.column({ align = "center", gap = 12, padding = 16 }, notConnChildren))
	end

	local titleText = snapshot.device_name or noctalia.tr("panel.title") or "Sennheiser Momentum"
	local statusText = connected and ((noctalia.tr("panel.status.connected") or "Connected") .. (snapshot.mac and (" • " .. snapshot.mac) or "")) or (noctalia.tr("panel.status.disconnected") or "Not Connected")

	panel.render(ui.column({ flexGrow = 1, gap = 8, padding = 12 }, {
		ui.row({ align = "center", justify = "space_between", gap = 8 }, {
			ui.image({
				path = headerIconPath(),
				width = 28,
				height = 28,
				fit = "contain",
				opacity = connected and 1 or 0.45,
			}),
			ui.column({ flexGrow = 1, gap = 2 }, {
				ui.label({
					text = titleText,
					fontSize = 15,
					fontWeight = "bold",
					color = "on_surface",
					maxLines = 1,
				}),
				ui.label({
					text = statusText,
					fontSize = 11,
					color = connected and "secondary" or "on_surface_variant",
					maxLines = 1,
				}),
			}),
			ui.button({
				glyph = "close",
				variant = "ghost",
				onClick = "onCloseClicked",
			}),
		}),
		ui.scroll({ flexGrow = 1, gap = 8 }, body),
	}))
end

noctalia.state.watch(SNAPSHOT_KEY, function(value)
	if type(value) == "table" then
		snapshot = value
		render()
	end
end)

function onOpen(_context)
	sendCommand("refresh", nil)
	render()
end

function onCloseClicked()
	panel.close()
end
