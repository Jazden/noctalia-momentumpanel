--!nonstrict
-- Bar widget for Sennheiser Momentum

local SNAPSHOT_KEY = "momentum_snapshot"

local snapshot = noctalia.state.get(SNAPSHOT_KEY) or {}
local hideWhenDisconnected = noctalia.getConfig("hide_when_disconnected") ~= false

local function getModeName(mode)
	if mode == "active" or mode == "anc" then
		return noctalia.tr("panel.mode.active") or "Noise Cancellation"
	elseif mode == "aware" or mode == "transparency" then
		return noctalia.tr("panel.mode.aware") or "Transparency"
	elseif mode == "off" then
		return noctalia.tr("panel.mode.off") or "Off"
	end
	return mode or ""
end

local function render()
	local connected = snapshot.connected == true

	if hideWhenDisconnected then
		barWidget.setVisible(connected)
	else
		barWidget.setVisible(true)
	end

	local container = barWidget.isVertical() and ui.column or ui.row

	if not connected then
		barWidget.render(container({ gap = 4, align = "center" }, {
			ui.glyph({ name = "headphones", color = "on_surface_variant" }),
		}))
		barWidget.setTooltip({
			{ key = noctalia.tr("panel.title") or "Sennheiser Momentum", value = noctalia.tr("widget.not_connected") or "Not connected" },
			{ key = noctalia.tr("widget.action.left_click") or "Left Click", value = noctalia.tr("panel.title") or "Sennheiser Momentum" }
		})
		return
	end

	local mode = snapshot.noise_mode or "off"
	local glyphName = "headphones"
	local glyphColor = "on_surface"

	if mode == "active" or mode == "anc" then
		glyphName = "shield-check"
		glyphColor = "primary"
	elseif mode == "aware" or mode == "transparency" then
		glyphName = "ear"
		glyphColor = "secondary"
	end

	local bLevel = tonumber(snapshot.battery) or -1

	local children = {
		ui.glyph({ name = glyphName, color = glyphColor }),
	}

	if bLevel >= 0 and not barWidget.isVertical() then
		table.insert(children, ui.label({ text = tostring(bLevel) .. "%" }))
	end

	barWidget.render(container({ gap = 4, align = "center" }, children))

	-- Tooltip
	local tooltipRows = {
		{ key = "Device", value = snapshot.device_name or "Sennheiser Momentum" },
		{ key = noctalia.tr("widget.mode") or "Mode", value = getModeName(mode) },
	}

	if snapshot.codec and snapshot.codec ~= "" then
		table.insert(tooltipRows, { key = "Codec", value = snapshot.codec })
	end

	if bLevel >= 0 then
		local chargingStr = snapshot.charging and (" (" .. (noctalia.tr("panel.charging") or "Charging") .. ")") or ""
		table.insert(tooltipRows, { key = noctalia.tr("panel.battery") or "Battery", value = tostring(bLevel) .. "%" .. chargingStr })
	end

	if snapshot.bass_boost ~= nil then
		table.insert(tooltipRows, { key = noctalia.tr("panel.bass_boost") or "Bass Boost", value = snapshot.bass_boost and "On" or "Off" })
	end

	table.insert(tooltipRows, { key = "Left Click", value = noctalia.tr("widget.action.left_click") or "Open Controls" })
	table.insert(tooltipRows, { key = "Right Click", value = noctalia.tr("widget.action.right_click") or "Cycle Noise Mode" })

	barWidget.setTooltip(tooltipRows)
end

noctalia.state.watch(SNAPSHOT_KEY, function(value)
	if type(value) == "table" then
		snapshot = value
		render()
	end
end)

function onConfigChanged()
	hideWhenDisconnected = noctalia.getConfig("hide_when_disconnected") ~= false
	render()
end

render()
