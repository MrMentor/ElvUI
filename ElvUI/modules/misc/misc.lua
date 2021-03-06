local E, L, V, P, G = unpack(select(2, ...));
local M = E:NewModule("Misc", "AceEvent-3.0", "AceTimer-3.0");
E.Misc = M;

local floor = math.floor;
local format, gsub = string.format, string.gsub;
local UnitGUID = UnitGUID;
local UIErrorsFrame = UIErrorsFrame;
local MAX_PARTY_MEMBERS = MAX_PARTY_MEMBERS;

local interruptMsg = INTERRUPTED.." %s's \124cff71d5ff\124Hspell:%d\124h[%s]\124h\124r!";

function M:ErrorFrameToggle(event)
	if(not E.db.general.hideErrorFrame) then return; end
	if(event == "PLAYER_REGEN_DISABLED") then
		UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE");
	else
		UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE");
	end
end

function M:COMBAT_LOG_EVENT_UNFILTERED(_, _, event, _, sourceName, _, _, destName, _, _, _, _, spellID, spellName)
	if(E.db.general.interruptAnnounce == "NONE") then return; end -- No Announcement configured, exit.
	if not (event == "SPELL_INTERRUPT" and sourceName == UnitName("player")) then return; end -- No annoucable interrupt from player, exit.
	
	local party, raid = GetNumPartyMembers(), GetNumRaidMembers();
	local _, instanceType = IsInInstance();
	local battleground = instanceType == "pvp";
	
	if(E.db.general.interruptAnnounce == "PARTY") then
		if(party > 0) then
			SendChatMessage(format(interruptMsg, destName, spellID, spellName), battleground and "BATTLEGROUND" or "PARTY");
		end
	elseif(E.db.general.interruptAnnounce == "RAID") then
		if(raid > 0) then
			SendChatMessage(format(interruptMsg, destName, spellID, spellName), battleground and "BATTLEGROUND" or "RAID");
		elseif(party > 0) then
			SendChatMessage(format(interruptMsg, destName, spellID, spellName), battleground and "BATTLEGROUND" or "PARTY");
		end
	elseif(E.db.general.interruptAnnounce == "RAID_ONLY") then
		if(raid > 0) then
			SendChatMessage(format(interruptMsg, destName, spellID, spellName), battleground and "BATTLEGROUND" or "RAID");
		end
	elseif(E.db.general.interruptAnnounce == "SAY") then
		if(party > 0) then
			SendChatMessage(format(interruptMsg, destName, spellID, spellName), "SAY");
		end
	end
end

function M:MERCHANT_SHOW()
	if E.db.general.vendorGrays then
		E:GetModule("Bags"):VendorGrays(nil, true)
	end

	local autoRepair = E.db.general.autoRepair
	if IsShiftKeyDown() or autoRepair == "NONE" or not CanMerchantRepair() then return end
	
	local cost, possible = GetRepairAllCost()
	local withdrawLimit = GetGuildBankWithdrawMoney();
	if autoRepair == "GUILD" and (not CanGuildBankRepair() or cost > withdrawLimit) then
		autoRepair = "PLAYER"
	end
		
	if cost > 0 then
		if possible then
			RepairAllItems(autoRepair == "GUILD")
			
			if autoRepair == "GUILD" then
				E:Print(L["Your items have been repaired using guild bank funds for: "]..GetCoinTextureString(cost, 12))
			else
				E:Print(L["Your items have been repaired for: "]..GetCoinTextureString(cost, 12))
			end
		else
			E:Print(L["You don't have enough money to repair."])
		end
	end
end

function M:DisbandRaidGroup()
	if InCombatLockdown() then return end -- Prevent user error in combat

	if UnitInRaid("player") then
		for i = 1, GetNumRaidMembers() do
			local name, _, _, _, _, _, _, online = GetRaidRosterInfo(i)
			if online and name ~= E.myname then
				UninviteUnit(name)
			end
		end
	else
		for i = MAX_PARTY_MEMBERS, 1, -1 do
			if GetPartyMember(i) then
				UninviteUnit(UnitName("party"..i))
			end
		end
	end
	LeaveParty()
end

function M:CheckMovement()
	if E.db.general.mapAlpha == 100 or not WorldMapFrame:IsShown() then return end
	
	if GetUnitSpeed("player") ~= 0 then
		WorldMapFrame:SetAlpha(E.db.general.mapAlpha)
	else
		WorldMapFrame:SetAlpha(1)
	end
end

function M:PVPMessageEnhancement(_, msg)
	if(not E.db.general.enhancedPvpMessages) then return; end
	local _, instanceType = IsInInstance();
	if(instanceType == "pvp" or instanceType == "arena") then
		RaidNotice_AddMessage(RaidBossEmoteFrame, msg, ChatTypeInfo["RAID_BOSS_EMOTE"]);
	end
end

local hideStatic = false;
function M:AutoInvite(event, leaderName)
	if not E.db.general.autoAcceptInvite then return; end

	if event == "PARTY_INVITE_REQUEST" then
		if MiniMapLFGFrame:IsShown() then return end -- Prevent losing que inside LFD if someone invites you to group
		if GetNumPartyMembers() > 0 or GetNumRaidMembers() > 0 then return end
		hideStatic = true
	
		-- Update Guild and Friendlist
		if GetNumFriends() > 0 then ShowFriends() end
		if IsInGuild() then GuildRoster() end
		local inGroup = false;
		
		for friendIndex = 1, GetNumFriends() do
			local friendName = gsub(GetFriendInfo(friendIndex), "-.*", "")
			if friendName == leaderName then
				AcceptGroup()
				inGroup = true
				break
			end
		end
		
		if not inGroup then
			for guildIndex = 1, GetNumGuildMembers(true) do
				local guildMemberName = gsub(GetGuildRosterInfo(guildIndex), "-.*", "")
				if guildMemberName == leaderName then
					AcceptGroup()
					inGroup = true
					break
				end
			end
		end
		
		if not inGroup then
			for bnIndex = 1, BNGetNumFriends() do
				local _, _, _, name = BNGetFriendInfo(bnIndex)
				leaderName = leaderName:match("(.+)%-.+") or leaderName
				if name == leaderName then
					AcceptGroup()
					break
				end
			end
		end
	elseif event == "PARTY_MEMBERS_CHANGED" and hideStatic == true then
		StaticPopup_Hide("PARTY_INVITE")
		hideStatic = false
	end
end

function M:ForceCVars()
	if not GetCVarBool("lockActionBars") and E.private.actionbar.enable then
		SetCVar("lockActionBars", 1)
	end
end

function M:PLAYER_ENTERING_WORLD()
	self:ForceCVars()
end

function M:Kill()
	--Kill Frames
end

function M:Initialize()
	self:LoadExpRepBar()
	self:LoadMirrorBars()
	self:LoadLoot()
	self:LoadLootRoll()
	self:LoadChatBubbles()
	self:RegisterEvent("MERCHANT_SHOW")
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "ErrorFrameToggle")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "ErrorFrameToggle")
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	self:RegisterEvent("CHAT_MSG_BG_SYSTEM_HORDE", "PVPMessageEnhancement")
	self:RegisterEvent("CHAT_MSG_BG_SYSTEM_ALLIANCE", "PVPMessageEnhancement")
	self:RegisterEvent("CHAT_MSG_BG_SYSTEM_NEUTRAL", "PVPMessageEnhancement")
	self:RegisterEvent("PARTY_INVITE_REQUEST", "AutoInvite")
	self:RegisterEvent("PARTY_MEMBERS_CHANGED", "AutoInvite")
	self:RegisterEvent("CVAR_UPDATE", "ForceCVars")
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	
	self.MovingTimer = self:ScheduleRepeatingTimer("CheckMovement", 0.1)
	self:Kill()
end

E:RegisterModule(M:GetName())