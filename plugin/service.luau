--!nonstrict
-- Service for Sennheiser Momentum
-- Controls and polls headphones via scripts/momentum_ctl.py

local SNAPSHOT_KEY = "momentum_snapshot"
local COMMAND_KEY = "momentum_command"

local scriptPath = noctalia.pluginDir() .. "/scripts/momentum_ctl.py"

local function sanitizeWord(val)
	if type(val) ~= "string" then
		return nil
	end
	if string.match(val, "^[%w%-_]+$") then
		return val
	end
	return nil
end

local function safeArg(val)
	local s = tostring(val)
	if string.match(s, "^[%w%.%-%+]+$") then
		return s
	end
	return "'" .. string.gsub(s, "'", "'\\''") .. "'"
end

local function getCliCmd(...)
	local parts = { "python3", '"' .. scriptPath .. '"' }
	for _, a in ipairs({ ... }) do
		table.insert(parts, safeArg(a))
	end
	return table.concat(parts, " ")
end

local function updateSnapshot(data)
	if type(data) == "table" then
		noctalia.state.set(SNAPSHOT_KEY, data)
	end
end

local function mutateSnapshot(modifier)
	local cur = noctalia.state.get(SNAPSHOT_KEY)
	if type(cur) == "table" then
		modifier(cur)
		noctalia.state.set(SNAPSHOT_KEY, cur)
	end
end

local function pollStatus()
	local cmd = getCliCmd("status")
	noctalia.runAsync(cmd, function(result)
		if result and result.stdout and result.stdout ~= "" then
			local ok, parsed = pcall(function()
				return noctalia.json.decode(result.stdout)
			end)
			if ok and parsed then
				updateSnapshot(parsed)
			end
		end
	end)
end

local function notifyMode(mode)
	local modeKey = "panel.mode." .. tostring(mode)
	local modeLabel = noctalia.tr(modeKey) or tostring(mode)
	local curState = noctalia.state.get(SNAPSHOT_KEY)
	local devName = (curState and curState.device_name) or "Sennheiser Momentum"
	local fmt = noctalia.tr("notify.mode_changed") or "Noise Control: %s"
	pcall(function()
		noctalia.notify(devName, string.format(fmt, modeLabel), "headphones")
	end)
end

local function notifyBass(enabled)
	local label = enabled and "Enabled" or "Disabled"
	local curState = noctalia.state.get(SNAPSHOT_KEY)
	local devName = (curState and curState.device_name) or "Sennheiser Momentum"
	local fmt = noctalia.tr("notify.bass_boost_changed") or "Bass Boost: %s"
	pcall(function()
		noctalia.notify(devName, string.format(fmt, label), "headphones")
	end)
end

local function setNoiseMode(targetMode)
	local clean = sanitizeWord(targetMode)
	if not clean then
		return
	end

	-- Optimistic UI update
	mutateSnapshot(function(s)
		s.noise_mode = clean
		if clean == "active" then
			s.anc_enabled = true
			s.transparency = 0
		elseif clean == "aware" then
			s.anc_enabled = true
			s.transparency = 100
		elseif clean == "off" then
			s.anc_enabled = false
		end
	end)

	local cmd = getCliCmd("anc", clean)
	noctalia.runAsync(cmd, function(result)
		pollStatus()
		notifyMode(clean)
	end)
end

local function cycleNoiseMode()
	local cmd = getCliCmd("anc", "cycle")
	noctalia.runAsync(cmd, function(result)
		if result and result.stdout and result.stdout ~= "" then
			local ok, parsed = pcall(function()
				return noctalia.json.decode(result.stdout)
			end)
			if ok and parsed and parsed.mode then
				mutateSnapshot(function(s)
					s.noise_mode = parsed.mode
				end)
				notifyMode(parsed.mode)
			end
		end
		pollStatus()
	end)
end

local function setTransparency(val)
	local num = tonumber(val)
	if not num then return end
	num = math.max(0, math.min(100, math.floor(num)))

	mutateSnapshot(function(s)
		s.transparency = num
	end)

	local cmd = getCliCmd("transparency", tostring(num))
	noctalia.runAsync(cmd, function()
		pollStatus()
	end)
end

local function setBassBoost(enabled)
	local arg = enabled and "on" or "off"
	mutateSnapshot(function(s)
		s.bass_boost = (enabled == true)
	end)

	local cmd = getCliCmd("bass", arg)
	noctalia.runAsync(cmd, function()
		pollStatus()
		notifyBass(enabled)
	end)
end

local function toggleBassBoost()
	local curState = noctalia.state.get(SNAPSHOT_KEY)
	local cur = curState and curState.bass_boost == true
	setBassBoost(not cur)
end

local function connectHeadphones()
	local curState = noctalia.state.get(SNAPSHOT_KEY)
	local mac = curState and curState.mac
	local cmd = mac and getCliCmd("connect", mac) or getCliCmd("connect")
	noctalia.runAsync(cmd, function()
		pollStatus()
	end)
end

-- Command listener from panel
local lastProcessedNonce = nil
noctalia.state.watch(COMMAND_KEY, function(cmd)
	if type(cmd) ~= "table" then
		return
	end
	if cmd.nonce and cmd.nonce == lastProcessedNonce then
		return
	end
	lastProcessedNonce = cmd.nonce

	local action = cmd.action
	if action == "set_noise_mode" then
		setNoiseMode(cmd.value)
	elseif action == "cycle_noise_mode" then
		cycleNoiseMode()
	elseif action == "set_transparency" then
		setTransparency(cmd.value)
	elseif action == "set_bass_boost" then
		setBassBoost(cmd.value)
	elseif action == "toggle_bass_boost" then
		toggleBassBoost()
	elseif action == "connect" then
		connectHeadphones()
	elseif action == "refresh" then
		pollStatus()
	end
end)

function onIpcMessage(source, msg)
	if msg == "cycle-noise" then
		cycleNoiseMode()
	elseif msg == "toggle-bass" then
		toggleBassBoost()
	elseif msg == "refresh" then
		pollStatus()
	end
end

-- Initial poll, then interval polling every 5 seconds
pollStatus()
noctalia.setUpdateInterval(5000)

function update()
	pollStatus()
end
