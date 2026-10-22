local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer

local Services = RS.Packages._Index["sleitnick_knit@1.7.0"].knit.Services
local Roll = Services.StyleService.RF.Roll
local RequestJerseyUpdate = Services.JerseyService.RF.RequestJerseyUpdate
local Redeem = Services.CodeService.RF.Redeem

-- ===== อ่าน Config (ถ้าไม่ได้ตั้ง ใช้ค่าเริ่มต้น) =====
local DEFAULT = {
	AUTO_ROLL = true,
	WANTED = { "Sanju", "Kisuki" },
	MAX_ROLLS = 500,
	WAIT_AFTER_ROLL = 3,
	CALL_JERSEY_UPDATE = true,
	AUTO_REDEEM = true,
	REDEEM_LEVEL = 15,
	CODES = {},
	REDEEM_DELAY = 2,
	WAIT_REDEEM_BEFORE_DONE = false,
}

local function getCfg(key)
	local user = type(_G.RollConfig) == "table" and _G.RollConfig or {}
	if user[key] ~= nil then
		return user[key]
	end
	return DEFAULT[key]
end

-- อ่านสดทุกครั้ง เพื่อสลับเปิด/ปิดระหว่างรันได้
local function isAutoRoll() return getCfg("AUTO_ROLL") == true end
local function isAutoRedeem() return getCfg("AUTO_REDEEM") == true end

-- ===== ฟังก์ชันร่วม =====
local function clean(text)
	text = tostring(text):gsub("<[^>]+>", ""):gsub("[|;]", "")
	return text:match("^%s*(.-)%s*$")
end

local function getStyle()
	local char = workspace:FindFirstChild(player.Name)
	local jersey = char and char:FindFirstChild("JerseyBack")
	local label = jersey and jersey:FindFirstChild("StyleName", true)
	if label and label:IsA("TextLabel") then
		local text = clean(label.Text)
		return text:sub(1, 1):upper() .. text:sub(2):lower()
	end
	return ""
end

local function getLevel()
	local char = workspace:FindFirstChild(player.Name)
	local label = char
		and char:FindFirstChild("Nametag")
		and char.Nametag:FindFirstChild("Container")
		and char.Nametag.Container:FindFirstChild("PlayerLvl")
	if label and label:IsA("TextLabel") then
		return tonumber(label.Text:match("%d+")) or 0
	end
	return 0
end

-- สถานะระบบใส่โค้ด (แชร์กับระบบสุ่ม)
local redeemState = { finished = false, success = 0, failed = 0, ran = false }

local function redeemSummary()
	if not redeemState.ran then
		return "ไม่ได้ใส่โค้ด"
	end
	return ("โค้ด %d/%d"):format(redeemState.success, redeemState.success + redeemState.failed)
end

local function sendLog(status, rolls)
	if not _G.Horst_SetDescription then
		warn("ไม่พบ _G.Horst_SetDescription")
		return
	end

	local level = getLevel()
	local style = getStyle()
	local msg = clean("🌲Level : " .. level .. " , ⚔️ Style : " .. style .. " , " .. status)

	local json = HttpService:JSONEncode({
		Level = level,
		Style = style,
		Rolls = rolls,
		Status = status,
		RedeemSuccess = redeemState.success,
		RedeemFailed = redeemState.failed,
	})

	local ok, err = pcall(_G.Horst_SetDescription, msg, json)
	if not ok then
		warn("ส่ง log ไม่สำเร็จ:", err)
	end
end

local function finish(status, rolls, markDone)
	-- ถ้าตั้งไว้ รอระบบใส่โค้ดเสร็จก่อนส่ง Done
	if markDone and getCfg("WAIT_REDEEM_BEFORE_DONE") == true then
		while isAutoRedeem() and not redeemState.finished do
			task.wait(1)
		end
	end

	sendLog(status .. " , " .. redeemSummary(), rolls)

	if markDone and _G.Horst_AccountChangeDone then
		local ok, err = _G.Horst_AccountChangeDone()
		if not ok then
			warn("ส่ง Done ไม่สำเร็จ:", err)
		end
	end
end

-- ==================== ระบบใส่โค้ด ====================
local function runRedeem()
	local CODES = getCfg("CODES")
	if type(CODES) == "string" then
		CODES = { CODES }
	end
	if type(CODES) ~= "table" or #CODES == 0 then
		warn("[Redeem] CODES ว่าง ข้ามระบบใส่โค้ด")
		return
	end

	local REDEEM_LEVEL = tonumber(getCfg("REDEEM_LEVEL")) or DEFAULT.REDEEM_LEVEL
	local REDEEM_DELAY = tonumber(getCfg("REDEEM_DELAY")) or DEFAULT.REDEEM_DELAY

	print("[Redeem] เปิด | รอเลเวล:", REDEEM_LEVEL, "| จำนวนโค้ด:", #CODES)

	-- รอจนเลเวลถึงเกณฑ์
	while true do
		if not isAutoRedeem() then
			print("[Redeem] ปิดอยู่ หยุดทำงาน")
			return
		end
		local level = getLevel()
		if level >= REDEEM_LEVEL then
			print("[Redeem] เลเวล", level, "ถึงเกณฑ์แล้ว เริ่มใส่โค้ด")
			break
		end
		task.wait(5)
	end

	redeemState.ran = true

	for _, code in ipairs(CODES) do
		if not isAutoRedeem() then
			print("[Redeem] ถูกปิดระหว่างทำงาน หยุด")
			break
		end

		local ok, result = pcall(function()
			return Redeem:InvokeServer(code)
		end)

		if ok and result ~= false then
			redeemState.success += 1
			print("[Redeem] ✅", code, "->", tostring(result))
		else
			redeemState.failed += 1
			warn("[Redeem] ❌", code, "->", tostring(result))
		end

		task.wait(REDEEM_DELAY)
	end

	print(("[Redeem] เสร็จแล้ว สำเร็จ %d / ไม่สำเร็จ %d"):format(redeemState.success, redeemState.failed))
end

-- ==================== ระบบสุ่ม ====================
local function runRoll()
	local WANTED = getCfg("WANTED")
	if type(WANTED) == "string" then
		WANTED = { WANTED }
	end
	if type(WANTED) ~= "table" or #WANTED == 0 then
		warn("[Roll] WANTED ว่างหรือผิดรูปแบบ ข้ามระบบสุ่ม")
		return
	end

	local MAX_ROLLS = tonumber(getCfg("MAX_ROLLS")) or DEFAULT.MAX_ROLLS
	local WAIT_AFTER_ROLL = tonumber(getCfg("WAIT_AFTER_ROLL")) or DEFAULT.WAIT_AFTER_ROLL
	local CALL_JERSEY_UPDATE = getCfg("CALL_JERSEY_UPDATE") == true

	local function isWanted(style)
		for _, name in ipairs(WANTED) do
			if style:lower() == tostring(name):lower() then
				return true
			end
		end
		return false
	end

	print("[Roll] Auto Roll:", isAutoRoll() and "เปิด" or "ปิด",
		"| เป้าหมาย:", table.concat(WANTED, ", "), "| สูงสุด:", MAX_ROLLS)

	-- เช็คก่อนเริ่ม เผื่อได้ตัวที่ต้องการอยู่แล้ว
	local startStyle = getStyle()
	if startStyle ~= "" and isWanted(startStyle) then
		finish("ได้ตัวที่ต้องการแล้ว", 0, true)
		return
	end

	-- ปิด Auto Roll: ส่งสถานะปัจจุบันแล้วจบ ไม่สุ่ม
	if not isAutoRoll() then
		finish("ปิด Auto Roll (ไม่สุ่ม)", 0, false)
		return
	end

	local rolls = 0

	for i = 1, MAX_ROLLS do
		if not isAutoRoll() then
			finish("หยุดสุ่ม (ปิด Auto Roll) สุ่มไป " .. rolls .. " ครั้ง", rolls, false)
			return
		end

		local ok, result = pcall(function()
			return Roll:InvokeServer()
		end)

		if not ok then
			warn("[Roll] สุ่มไม่สำเร็จ:", result)
			finish("สุ่มไม่สำเร็จ หยุดที่ครั้งที่ " .. rolls, rolls, false)
			return
		end
		if result == false then
			finish("สุ่มไม่ได้ (ของหมด/คูลดาวน์) หยุดที่ครั้งที่ " .. rolls, rolls, false)
			return
		end

		rolls = i
		task.wait(WAIT_AFTER_ROLL)

		if CALL_JERSEY_UPDATE then
			pcall(function()
				RequestJerseyUpdate:InvokeServer()
			end)
			task.wait(1)
		end

		local style = getStyle()
		print(("[Roll] สุ่มครั้งที่ %d -> %s"):format(i, style))

		if style ~= "" and isWanted(style) then
			finish("ได้ตัวที่ต้องการ สุ่มไป " .. i .. " ครั้ง", i, true)
			return
		end
	end

	finish("สุ่มครบ " .. MAX_ROLLS .. " ครั้ง ยังไม่ได้ตัวที่ต้องการ", rolls, false)
end

-- ==================== เริ่มทำงาน ====================
if isAutoRedeem() then
	task.spawn(function()
		pcall(runRedeem)
		redeemState.finished = true
	end)
else
	redeemState.finished = true
end

runRoll()
