-----------------------------------------------------------------------------------------------
-- Client Lua Script for LFRP
-- Copyright (c) NCsoft. All rights reserved
-----------------------------------------------------------------------------------------------
 
require "Window"
require "Unit"
require "ICCommLib"
require "GameLib"

 
-----------------------------------------------------------------------------------------------
-- LFRP Module Definition
-----------------------------------------------------------------------------------------------
local LFRP = {}
local Communicator = {}
 
-----------------------------------------------------------------------------------------------
-- Constants
-----------------------------------------------------------------------------------------------

kEnumLFRP_Query = 1
kEnumLFRP_Response = 2
 
-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------
function LFRP:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self 

	o.tTracked = {}
	o.bLFRP = true
	o.bDirty = false
	o.strCharName = ""
	o.bShow = true
	o.tMsg = {}
	o.tThrottled = {}

    return o
end

function LFRP:Init()
	local bHasConfigureFunction = false
	local strConfigureButtonText = ""
	local tDependencies = {}
    Apollo.RegisterAddon(self, bHasConfigureFunction, strConfigureButtonText, tDependencies)
end
 

-----------------------------------------------------------------------------------------------
-- LFRP OnLoad
-----------------------------------------------------------------------------------------------
function LFRP:OnLoad()
    -- load our form file
	self.xmlDoc = XmlDoc.CreateFromFile("LFRP.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
	self:SetupComms()
	Apollo.RegisterEventHandler("UnitCreated", "OnUnitCreated", self)
	Apollo.RegisterEventHandler("UnitDestroyed", "OnUnitDestroyed", self)
	Apollo.RegisterEventHandler("ChangeWorld", "OnChangeWorld", self)
end

-----------------------------------------------------------------------------------------------
-- LFRP OnDocLoaded
-----------------------------------------------------------------------------------------------
function LFRP:OnDocLoaded()

	if self.xmlDoc ~= nil and self.xmlDoc:IsLoaded() then
	    self.wndMain = Apollo.LoadForm(self.xmlDoc, "LFRPForm", nil, self)
		if self.wndMain == nil then
			Apollo.AddAddonErrorText(self, "Could not load the main window for some reason.")
			return
		end
		
		-- item list
		self.wndPlayerList = self.wndMain:FindChild("PlayerList")
	    self.wndMain:Show(self.bShow)

		Apollo.RegisterSlashCommand("lfrp", "ShowLFRP", self)
		self.UpdateTimer = ApolloTimer.Create(1, true, "OnUpdateTimer", self)
		self.NameTimer = ApolloTimer.Create(1, true, "OnNameTimer", self)
		self.wndMainTimer = ApolloTimer.Create(1, true, "OnwndMainTimer", self)
		self.ThrottledTimer = ApolloTimer.Create(3, true, "OnThrottledTimer", self)
		self.ThrottledTimer:Stop()
	end
end

-----------------------------------------------------------------------------------------------
-- LFRP Saved Settings
-----------------------------------------------------------------------------------------------

function LFRP:OnSave(eLevel)
	if eLevel ~= GameLib.CodeEnumAddonSaveLevel.Character then
		return nil
	end
	local tSave = {}
	tSave['bShow'] = self.bShow
	tSave['bLFRP'] = self.bLFRP
	tSave['tLoc'] = self.wndMain:GetLocation():ToTable()
	return tSave
end

function LFRP:OnRestore(eLevel, tData)
	if eLevel ~= GameLib.CodeEnumAddonSaveLevel.Character then
		return nil
	end
	if tData ~= nil then
		self.bShow = tData['bShow']
		self.bLFRP = tData['bLFRP']
		self.tLoc = tData['tLoc']
	end
end

function LFRP:OnwndMainTimer()
	if self.wndMain == nil then
		return
	elseif self.tLoc ~= nil then
		self.wndMain:MoveToLocation(WindowLocation.new(self.tLoc))
		self.wndMainTimer:Stop()
	else
		self.wndMainTimer:Stop()
	end
	self.wndMain:FindChild('btnLFRP'):SetCheck(self.bLFRP)
end

-----------------------------------------------------------------------------------------------
-- LFRP Functions
-----------------------------------------------------------------------------------------------

function LFRP:SetupComms()
	self.Comm = ICCommLib.JoinChannel("__LFRP__", ICCommLib.CodeEnumICCommChannelType.Global)
	self.Comm:SetJoinResultFunction('OnJoinResult', self)
	self.Comm:SetReceivedMessageFunction("OnMessageReceived", self)
	self.Comm:SetSendMessageResultFunction("OnMessageSent", self)
	self.Comm:SetThrottledFunction("OnMessageThrottled", self)
end

function LFRP:OnJoinResult(channel, eResult)
	local bBadName = eResult == ICCommLib.CodeEnumICCommJoinResult.BadName
	local bJoin = eResult == ICCommLib.CodeEnumICCommJoinResult.Join
	local bLeft = eResult == ICCommLib.CodeEnumICCommJoinResult.Left
	local bMissing = eResult == ICCommLib.CodeEnumICCommJoinResult.MissingEntitlement
	local bNoGroup = eResult == ICCommLib.CodeEnumICCommJoinResult.NoGroup
	local bNoGuild = eResult == ICCommLib.CodeEnumICCommJoinResult.NoGuild
	local bTooMany = eResult == ICCommLib.CodeEnumICCommJoinResult.TooManyChannels
	
	if bJoin then
		Print(string.format('LFRP: Joined ICComm Channel "%s"', channel:GetName()))
		if channel:IsReady() then
			Print('LFRP: Channel is ready to transmit')
		else
			Print('LFRP: Channel is not ready to transmit')
		end
	elseif bLeft then
		Print('LFRP: Left ICComm Channel')
	elseif bBadName then
		Print('LFRP: Bad Channel Name')
	elseif bMissing then
		Print('LFRP: User doesn\'t have entitlement to job ICComm Channels')
	elseif bNoGroup then
		Print('LFRP: Group missing from channel Join attempt')
	elseif bNoGuil then
		Print('LFRP: Guild missing from channel Join attempt')
	else
		Print('LFRP: Too Many ICComm Channels exist')
	end
end

function LFRP:OnMessageSent(channel, eResult, idMessage)
	local bInvalid = eResult == ICCommLib.CodeEnumICCommMessageResult.InvalidText
	local bThrottled = eResult == ICCommLib.CodeEnumICCommMessageResult.Throttled
	local bMissing = eResult == ICCommLib.CodeEnumICCommMessageResult.MissingEntitlement
	local bNotIn = eResult == ICCommLib.CodeEnumICCommMessageResult.NotInChannel
	local bSent = eResult == ICCommLib.CodeEnumICCommMessageResult.Sent

	if bSent then
		--message was sent, remove it from the list
		Print(string.format('LFRP: Message Sent, Id# %d, Target: %s', idMessage, self.tMsg[idMessage]:GetName()))
		self.tMsg[idMessage] = nil
	elseif bInvalid then
		-- this one should never happen, but I'm including it for completeness
		-- and invalid message should never be resent
		Print(string.format('LFRP: Message Invalid, Id# %d', idMessage))
		self.tMsg[idMessage] = nil
	elseif bMissing then
		-- if the recipient doesn't have rights, we shouldn't bother with a resend
		Print(string.format('LFRP: Recipient Can Not Receive, Id# %d', idMessage))
		self.Msg[idMessage] = nil
	elseif bNotIn then
		-- if there not in the channel, they're not a LFRP user and they can be removed from tracking
		Print(string.format('LFRP: Recipient Not In Channel, Id# %d', idMessage))
		self.tTracked[self.tMsg[idMessage]:GetName()] = nil
		self.tMsg[idMessage] = nil
	elseif bThrottled then
		-- if it's throttled, we need to wait for a bit, then attempt a resend
		-- we'll let OnMessageThrottled handle that
		-- move the message to the throttled queue
		Print(string.format('LFRP: Message Throttled, Id# %d', idMessage))
		self.tThrottled[idMessage] = self.tMsg[idMessage]
		self.tMsg = nil
	else
		-- if none of those enums is true, something else has gone horribly wrong
		Print(string.format('LFRP: Unknown Error, Id# %d', idMessage))
		self.tMsg[idMessage] = nil
	end
	-- dump the contents of the event to debug just because
	Print(string.format('Message Sent Event Dump: %s, %s, %s', channel:GetName(), tostring(eResult), tostring(idMessage)))
end

function LFRP:OnMessageThrottled(channel, strSender, idMessage)
	--start the throttled timer
	self.ThrottledTimer:Start()
end

function LFRP:OnThrottledTimer()
	-- run through the throttled queue
	for idMsg,unit in ipairs(self.tThrottled) do
		-- send a new query to the effected unit
		self:SendQuery(unit)
		--clear the unit from the throttled queue
		self.tThrottled[idMsg] = nil
	end
	-- stop the throttled timer again
	self.ThrottledTimer:Stop()
end

function LFRP:SendQuery(unit)
	local iMsg = 0
	if (unit ~= nil) and self.Comm:IsReady() then
		iMsg = self.Comm:SendPrivateMessage(unit:GetName(), tostring(kEnumLFRP_Query))
		self.tMsg[iMsg] = unit
	end
end

function LFRP:OnMessageReceived(channel, strMessage, idMessage)
	-- first check to make sure the message was on LFRP, if it's not ignore it
	if channel:GetName() == "__LFRP__" then
		--split out the sender and the receiver
		strPattern = '(%a*%s%a*),(%d)'
		strSender,mType = string.match(strMessage, strPattern)
		mType = tonumber(mType)
		--dump them both to debug
		Print(string.format('LFRP: Received from %s, Message: %d', strSender, mType))
		-- if the message was a query, send back a response to the sender
		if mType == kEnumLFRP_Query then
			-- if your LFRP flag is on, send the response
			if self.bLFRP then
				self.Comm:SendPrivateMessage(strSender, tostring(kEnumLFRP_Response))
			end
		-- if the message is a response, update the tracked user status 
		elseif mType == kEnumLFRP_Response then
			-- if the unit still exists, update it's entry in the tracked table
			if GameLib.GetPlayerUnitByName(strSender) then
				self.tTracked[strSender]['bLFRP'] = true
			else
				-- if the unit doesn't exist anymore, remove it from the tracked table
				self.tTracked[strSender] = nil
			end
		-- the message was on LFRP, but it's not a query or a response
		-- flag it to debug
		else
			Print('LFRP:UnknownMessage')
		end
	end
	--dump to debug
	Print(string.format('LFRP: Message Received, %s %s %s', channel:GetName(), strMessage, idMessage))
end


function LFRP:ShowLFRP()
	Print('LFRP:ShowLFRP')
	self:PopulateRoleplayerList()
	self.bShow = true
	self.UpdateTimer:Start()
	self.wndMain:Show(self.bShow)
end

function LFRP:OnUnitCreated(unitCreated)
	if unitCreated:GetType() == "Player" then
		if not (unitCreated:GetName() == self.strCharName) then
			local tUnitEntry = {}
			tUnitEntry['unit'] = unitCreated
			-- setting true will result in assumption of all players as roleplayers
			tUnitEntry['bLFRP'] = false
			self.tTracked[unitCreated:GetName()] = tUnitEntry
			self:SendQuery(unitCreated)
			--Print(string.format('LFRP: %s, UnitCreated', unitCreated:GetName()))
		end
	end
end

function LFRP:OnUnitDestroyed(unitDestroyed)
	for this_name, this_unit in pairs(self.tTracked) do
		if unitDestroyed:GetName() == this_name then
			self.tTracked[this_name] = nil
			--Print(string.format('LFRP: %s, UnitDestroyed', unitDestroyed:GetName()))
		end
	end
end

function LFRP:OnChangeWorld()
	self.tTracked = {}
end

function LFRP:OnUpdateTimer()
	--debug, setting dirty to force true will result in all continual updates
	--self.bDirty = true
	if self.bDirty then
		self:PopulateRoleplayerList()
		self.bDirty = false
	end
end

function LFRP:OnNameTimer()
	if (GameLib.GetPlayerUnit() == nil) then
		return
	else
		self.strCharName = GameLib.GetPlayerUnit():GetName()
		self.tTracked[self.strCharName] = nil
		self.NameTimer:Stop()
	end
end

-----------------------------------------------------------------------------------------------
-- LFRPForm Functions
-----------------------------------------------------------------------------------------------

function LFRP:OnClose( wndHandler, wndControl, eMouseButton )
	self.wndMain:Close()
	self.bShow = false
	self.UpdateTimer:Stop()
end

function LFRP:OnMouseEnter( wndHandler, wndControl, x, y )
	--Print(string.format('Enter %s %s', wndHandler:GetName(), wndControl:GetName()))
	if wndControl == wndHandler then
		self.UpdateTimer:Stop()
	end
end

function LFRP:OnMouseExit( wndHandler, wndControl, x, y )
	--Print(string.format('Exit %s %s', wndHandler:GetName(), wndControl:GetName()))
	if wndControl == wndHandler then
		self.UpdateTimer:Start()
	end
end

function LFRP:OnLFRPCheck( wndHandler, wndControl, eMouseButton )
	self.bLFRP = true
end

function LFRP:OnLFRPUncheck( wndHandler, wndControl, eMouseButton )
	self.bLFRP = false
end

-----------------------------------------------------------------------------------------------
-- PlayerList Functions
-----------------------------------------------------------------------------------------------

function LFRP:DistanceToUnit(unit)

	unitPlayer = GameLib.GetPlayerUnit()
	
	if not(unitPlayer) then
		return 0
	end
	
	loc1 = unitPlayer:GetPosition()
	loc2 = unit:GetPosition()
	
	tVec = {}
	for axis, value in pairs(loc1) do
		tVec[axis] = loc1[axis] - loc2[axis]
	end
	
	vVec = Vector3.New(tVec['x'], tVec['y'], tVec['z'])
	return math.floor(vVec:Length())+1
end

function LFRP:PopulateRoleplayerList()
	self:DestroyRoleplayerList()
	
	--setup for a distance sorting
	aDist = {}
	for strName,tUnitEntry in pairs(self.tTracked) do
		-- only bother if it's a roleplayer
		if tUnitEntry['bLFRP'] then
			table.insert(aDist, tUnitEntry['unit'])
		end
	end
	
	--sort by distance
	table.sort(aDist, function(a,b) return self:DistanceToUnit(a)<self:DistanceToUnit(b) end)
	
	--dump to the list
	for i, unit in ipairs(aDist) do
		self:AddPlayerToList(unit)
	end
	self.wndPlayerList:ArrangeChildrenVert()
end

function LFRP:AddPlayerToList(unitAdded)
	btnPlayer = Apollo.LoadForm(self.xmlDoc, 'PlayerLine', self.wndPlayerList, self)
	btnPlayer:SetText(unitAdded:GetName())
	btnPlayer:SetData(unitAdded)
	wndDist = btnPlayer:FindChild('Distance')
	wndDist:SetText(string.format('%dm', self:DistanceToUnit(unitAdded)))
end

function LFRP:DestroyRoleplayerList()
	for i, this_btn in ipairs(self.wndPlayerList:GetChildren()) do
		this_btn:Destroy()
	end
end

---------------------------------------------------------------------------------------------------
-- PlayerLine Functions
---------------------------------------------------------------------------------------------------

function LFRP:OnPlayerButton( wndHandler, wndControl, eMouseButton )
	unit = wndControl:GetData()
	unit:ShowHintArrow()
end

-----------------------------------------------------------------------------------------------
-- LFRP Instance
-----------------------------------------------------------------------------------------------
local LFRPInst = LFRP:new()
LFRPInst:Init()
