-----------------------------------------------------------------------------------------------
-- Client Lua Script for LFRP
-- Copyright (c) NCsoft. All rights reserved
-----------------------------------------------------------------------------------------------
 
require "Window"
require "Unit"
require "ICComm"
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
kEnumLFRP_OptOut = 3
kstrComm = '__LFRP__'

local Major, Minor, Patch, Suffix = 1, 1, 2, 0
local YOURADDON_CURRENT_VERSION = string.format("%d.%d.%d", Major, Minor, Patch)
 
-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------
function LFRP:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self 

	o.tTracked = {}
	o.bLFRP = true
	--o.bDirty = false
	o.strCharName = ""
	o.bShow = true
	o.tMsg = {}
	o.tThrottled = {}

    return o
end

function LFRP:Init()
	local bHasConfigureFunction = false
	local strConfigureButtonText = ""
	local tDependencies = {
		"Gemini:Logging-1.2",
	}
    Apollo.RegisterAddon(self, bHasConfigureFunction, strConfigureButtonText, tDependencies)
end
 

-----------------------------------------------------------------------------------------------
-- LFRP OnLoad
-----------------------------------------------------------------------------------------------
function LFRP:OnLoad()
	--setup logger
	local GeminiLogging = Apollo.GetPackage("Gemini:Logging-1.2").tPackage
    
	self.glog = GeminiLogging:GetLogger({
		level = GeminiLogging.DEBUG,
		pattern = "%d %n %c %l - %m",
		appender = "GeminiConsole"
	})
	
	-- load our form file
	self.xmlDoc = XmlDoc.CreateFromFile("LFRP.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
	Apollo.RegisterEventHandler("UnitCreated", "OnUnitCreated", self)
	Apollo.RegisterEventHandler("UnitDestroyed", "OnUnitDestroyed", self)
	Apollo.RegisterEventHandler("ChangeWorld", "OnChangeWorld", self)
	Apollo.RegisterEventHandler("InterfaceMenuListHasLoaded", "OnInterfaceMenuListHasLoaded", self)
end

-----------------------------------------------------------------------------------------------
-- LFRP OnDocLoaded
-----------------------------------------------------------------------------------------------
function LFRP:OnDocLoaded()

	if self.xmlDoc ~= nil and self.xmlDoc:IsLoaded() then
	    self.wndMain = Apollo.LoadForm(self.xmlDoc, "LFRPForm", nil, self)
		if self.wndMain == nil then
			Apollo.AddAddonErrorText(self, "Could not load the main window for some reason.")
			self.glog:fatal('LFRP: Could not load main window.')
			return
		end
		
		self.wndChannels = Apollo.LoadForm(self.xmlDoc, "Channels", nil, self)
		if self.wndChannels == nil then
			Apollo.AddAddonErrorText(self, "Could not load the channel window for some reason.")
			self.glog:fatal('LFRP: Could not load RP Channel Search List.')
		else
			self.wndChannels:Show(false)
			wndChannelList = self.wndChannels:FindChild("ChannelList")
			if self.strChannelList then
				wndChannelList:SetText(self.strChannelList)
			end
			self.tRPChannelNames = self:ParseChannelNames(wndChannelList:GetText())
		end
		
		-- item list
		self.wndPlayerList = self.wndMain:FindChild("PlayerList")
	    self.wndMain:Show(self.bShow)

		Apollo.RegisterSlashCommand("lfrp", "ShowLFRP", self)
		--Apollo.RegisterSlashCommand("lfrp-init", "DoInit", self)
		Apollo.RegisterSlashCommand("lfrp-channels", "ShowChannelList", self)
		
		self.UpdateTimer = ApolloTimer.Create(3, true, "OnUpdateTimer", self)
		self.UpdateTimer:Stop()
		self.NameTimer = ApolloTimer.Create(1, true, "OnNameTimer", self)
		self.wndMainTimer = ApolloTimer.Create(1, true, "OnwndMainTimer", self)
		self.ThrottledTimer = ApolloTimer.Create(3, true, "OnThrottledTimer", self)
		self.ThrottledTimer:Stop()
		self.DelayedStart = ApolloTimer.Create(5, true, "OnDelayedStart", self)
		self.PollingTimer = ApolloTimer.Create(5, true, "OnPollingTimer", self)
		self.ReEnableTimer = ApolloTimer.Create(1, true, "OnReEnableTimer", self)
		self.ReEnableTimer:Stop()
	end
end

-----------------------------------------------------------------------------------------------
-- LFRP OnInterfaceMenuListHasLoaded
-----------------------------------------------------------------------------------------------

function LFRP:OnInterfaceMenuListHasLoaded()
	Event_FireGenericEvent("OneVersion_ReportAddonInfo", "LFRP", Major, Minor, Patch)
end

-----------------------------------------------------------------------------------------------
-- LFRP Saved Settings
-----------------------------------------------------------------------------------------------

function LFRP:ShowChannelList()
	self.wndChannels:Show(true)
end

function LFRP:DoInit()

	self:SetupComms()
	self.UpdateTimer:Start()

end

function LFRP:OnDelayedStart()
	self:DoInit()
	self.DelayedStart:Stop()
end


function LFRP:OnSave(eLevel)
	if eLevel ~= GameLib.CodeEnumAddonSaveLevel.Character then
		return nil
	end
	local tSave = {}
	tSave['bShow'] = self.bShow
	tSave['bLFRP'] = self.bLFRP
	tSave['tLoc'] = self.wndMain:GetLocation():ToTable()
	tSave['strChannelList'] = self.wndChannels:FindChild('ChannelList'):GetText()
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
		self.strChannelList = tData['strChannelList']
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

function LFRP:ParseChannelNames(strNames)
	tNames = {}
	strNames = string.lower(strNames)
	pattern = '%a+;'
	for name in string.gmatch(strNames, pattern) do
		table.insert(tNames, string.sub(name, 1, (string.len(name) - 1)))
	end
	return tNames
end

function LFRP:SetupComms()
	self.Comm = ICCommLib.JoinChannel(kstrComm, ICCommLib.CodeEnumICCommChannelType.Global)
	self.Comm:SetJoinResultFunction("OnJoinResult", self)
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
		--self.glog:debug(string.format('LFRP: Joined ICComm Channel "%s"', channel:GetName()))
		if channel:IsReady() then
			--self.glog:debug('LFRP: Channel is ready to transmit')
		else
			--self.glog:debug('LFRP: Channel is not ready to transmit')
		end
	elseif bLeft then
		--self.glog:debug('LFRP: Left ICComm Channel')
	elseif bBadName then
		self.glog:fatal('LFRP: Bad Channel Name')
	elseif bMissing then
		self.glog:fatal('LFRP: User doesn\'t have entitlement to job ICComm Channels')
	elseif bNoGroup then
		self.glog:fatal('LFRP: Group missing from channel Join attempt')
	elseif bNoGuild then
		self.glog:fatal('LFRP: Guild missing from channel Join attempt')
	elseif bTooMany then
		self.glog:fatal('LFRP: Too Many ICComm Channels exist')
	else
		self.glog:info('LFRP: Join Result didn\'t match any of the Enum.')
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
		if self.tMsg[idMessage] ~= nil then
			--self.glog:debug(string.format('LFRP: Message Sent, Id# %d, Target: %s', idMessage, self.tMsg[idMessage]:GetName()))
		end
		self.tMsg[idMessage] = nil
	elseif bInvalid then
		-- this one should never happen, but I'm including it for completeness
		-- and invalid message should never be resent
		self.glog:warn(string.format('LFRP: Message Invalid, Id# %d', idMessage))
		self.tMsg[idMessage] = nil
	elseif bMissing then
		-- if the recipient doesn't have rights, we shouldn't bother with a resend
		self.glog:warn(string.format('LFRP: Recipient Can Not Receive, Id# %d', idMessage))
		self.Msg[idMessage] = nil
	elseif bNotIn then
		-- if there not in the channel, they're not a LFRP user and they can be removed from tracking
		self.glog:warn(string.format('LFRP: Recipient Not In Channel, Id# %d', idMessage))
		self.tTracked[self.tMsg[idMessage]:GetName()] = nil
		self.tMsg[idMessage] = nil
	elseif bThrottled then
		-- if it's throttled, we need to wait for a bit, then attempt a resend
		-- we'll let OnMessageThrottled handle that
		-- move the message to the throttled queue
		self.glog:info(string.format('LFRP: Message Throttled, Id# %d', idMessage))
		self.tThrottled[idMessage] = self.tMsg[idMessage]
		self.tMsg[idMessage] = nil
	else
		-- if none of those enums is true, something else has gone horribly wrong
		self.glog:warn(string.format('LFRP: Unknown Error, Id# %d', idMessage))
		self.tMsg[idMessage] = nil
	end
	-- dump the contents of the event to debug just because
	--self.glog:debug(string.format('Message Sent Event Dump: %s, %s, %s', channel:GetName(), tostring(eResult), tostring(idMessage)))
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
	--self.glog:debug(string.format("Send Query: %s,", unit:GetName()))
	local iMsg = 0
	if (unit ~= nil) and self.Comm:IsReady() then
		iMsg = self.Comm:SendPrivateMessage(unit:GetName(), kEnumLFRP_Query)
		self.tMsg[iMsg] = unit
		self.tTracked[unit:GetName()]['bQuerySent'] = true
	end
end

function LFRP:OnMessageReceived(channel, strMessage, strSender)
	-- first check to make sure the message was on LFRP, if it's not ignore it
	if channel:GetName() == kstrComm then
		--error in documentation of received event, third param is sender. No need to split
		--[[
		--split out the sender and the receiver
		strPattern = '(%a*%s%a*),(%d)'
		strSender,mType = string.match(strMessage, strPattern)
		mType = tonumber(mType)
		]]--
		mType = tonumber(strMessage)
		--dump them both to debug
		self.glog:debug(string.format('LFRP: Received from %s, Message: %d', strSender, mType))
		-- if the message was a query, send back a response to the sender
		if mType == kEnumLFRP_Query then
			-- if your LFRP flag is on, send the response
			if self.bLFRP then
				idMessage = self.Comm:SendPrivateMessage(strSender, kEnumLFRP_Response)
				self.tMsg[idMessage] = GameLib.GetPlayerUnitByName(strSender)
			else
				idMessage = self.Comm:SendPrivateMessage(strSender, kEnumLFRP_OptOut)
				self.tMsg[idMessage] = GameLib.GetPlayerUnitByName(strSender)
			end
		-- if the message is a response, update the tracked user status 
		elseif mType == kEnumLFRP_Response then
			-- if the unit still exists, update it's entry in the tracked table
			if GameLib.GetPlayerUnitByName(strSender) then
				self.tTracked[strSender]['bLFRP'] = true
				-- if they responded with this code, they want to be found
				self.tTracked[strSender]['bOptOut'] = nil
				--self.bDirty = true
			else
				-- if the unit doesn't exist anymore, remove it from the tracked table
				self.tTracked[strSender] = nil
			end
		-- if the player is opting out, the channel search will still have found them, this will
		-- flag them to not be added to the listing
		elseif mType == kEnumLFRP_OptOut then
			if GameLib.GetPlayerUnitByName(strSender) then
				self.tTracked[strSender]['bOptOut'] = true
			else
				self.tTracked[strSender] = nil
			end
		-- the message was on LFRP, but it's not a query or a response
		-- flag it to debug
		else
			self.glog:warn('LFRP:UnknownMessage')
		end
	end
	--dump to debug
	--self.glog:debug(string.format('LFRP: Message Received, %s %s %s', channel:GetName(), strMessage, strSender))
end


function LFRP:ShowLFRP()
	--self.glog:debug('LFRP:ShowLFRP')
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
			
			-- set query state to false, no query sent yet
			tUnitEntry['bQuerySent'] = false

			self.tTracked[unitCreated:GetName()] = tUnitEntry
			
			-- anytime a new unit gets added to tracked, set the tracked table to dirty
			--self.bDirty = true
			
			--moving this out so that the early calling unit created events are dependent on ICComm being loaded
			--self:SendQuery(unitCreated)
			--self.glog:info(string.format('LFRP: %s, UnitCreated', unitCreated:GetName()))
		end
	end
end

function LFRP:OnUnitDestroyed(unitDestroyed)
	for this_name, this_unit in pairs(self.tTracked) do
		if unitDestroyed:GetName() == this_name then
			self.tTracked[this_name] = nil
			--self.bDirty = true
			--self.glog:info(string.format('LFRP: %s, UnitDestroyed', unitDestroyed:GetName()))
		end
	end
end

function LFRP:OnChangeWorld()
	-- clear the tracked units
	self.tTracked = {}
	self.glog:info('LFRP: Changed World')
end

function LFRP:CommandId()
	Killroy = Apollo.GetAddon("Killroy")

	local channels = ChatSystemLib.GetChannels()
	local chan_Command
	for i, this_chan in ipairs(channels) do
		if this_chan:GetName() == "Command" then
			chan_Command = this_chan
		end
	end
	if Killroy then
		return chan_command:GetType()
	else
		return chan_Command:GetUniqueId()
	end
end

function LFRP:PollRPChannels()
	--self.glog:debug("PollRPChannels: Ran.")
	local channels = ChatSystemLib.GetChannels()
	local arInteresting_channels = {}
	--local pattern = '.*RP.*'

	--replaced old pattern with a function so that it can
	--iterate over multiple names garnerd from the channel
	--list window
	function pattern(strName)
		return '.*'..strName..'.*'
	end
	
	--have to do this to hide the requests
	--Get Members doesn't work without a request first
	--disabling command channel display, temporarily
	local ChatLog = Apollo.GetAddon("ChatLog")
	
	local bRestore = {}
	for i, this_wnd in ipairs(ChatLog.tChatWindows) do
		local tData = this_wnd:GetData()
		bRestore[i] = tData.tViewedChannels[self:CommandId()]
		tData.tViewedChannels[self:CommandId()] = false
		this_wnd:SetData(tData)
	end
	
	-- if a channel as "RP" in its name,
	-- add it to the interesting channels list
	
	for i,this_chan in ipairs(channels) do
		--self.glog:debug(string.format("PollRPChannels: Checking %s", this_chan:GetName()))
		for j,this_name in ipairs(self.tRPChannelNames) do
			if string.find(string.lower(this_chan:GetName()), pattern(this_name)) then
				--self.glog:debug("PollRPChannels: RP Channel Found.")
				table.insert(arInteresting_channels, this_chan)
			end
		end
	end
	
	-- for each channel in the interesting channels list
	for i, this_chan in ipairs(arInteresting_channels) do
		--self.glog:debug(string.format('PollRPChannels: %s', this_chan:GetName()))
		-- poll for members
		this_chan:RequestMembers()
		local members = this_chan:GetMembers()
		-- for each member
		for j, this_member in ipairs(members) do
			local strName = this_member['strMemberName']
			--self.glog:debug(string.format('PollRPChannels: %s', strName))
			-- check to see if their unit exists in the players space
			if (GameLib.GetPlayerUnitByName(strName) ~= nil) and (strName ~= GameLib.GetPlayerUnit():GetName()) then
				--check to see if it's already tracked
				--if it isn't, track it
				--self.glog:debug('PollRPChannels: Now tracking this character.')
				self.tTracked[strName] = {}
				self.tTracked[strName]['strChannel'] = this_chan:GetName()
				self.tTracked[strName]['bLFRP'] = true
				self.tTracked[strName]['unit'] = GameLib.GetPlayerUnitByName(strName)
			end
		end
	end
	
	return bRestore
end

function LFRP:OnPollingTimer()
	self.bRestore = self:PollRPChannels()
	self.ReEnableTimer:Start()
end

function LFRP:OnReEnableTimer()
	ChatLog = Apollo.GetAddon("ChatLog")
	for i, this_wnd in ipairs(ChatLog.tChatWindows) do
		local tData = this_wnd:GetData()
		tData.tViewedChannels[self:CommandId()] = self.bRestore[i]
		this_wnd:SetData(tData)
	end
	self.ReEnableTimer:Stop()
end

function LFRP:OnUpdateTimer()
	if self.bShow then
		for strName, tUnitEntry in pairs(self.tTracked) do
			if not tUnitEntry['bQuerySent'] then
				self:SendQuery(tUnitEntry['unit'])
			end
		end
		self:PopulateRoleplayerList()
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
	self.glog:info(string.format('LFRP: Mouse Entered Window %s %s', wndHandler:GetName(), wndControl:GetName()))
	if wndControl == wndHandler then
		self.UpdateTimer:Stop()
	end
end

function LFRP:OnMouseExit( wndHandler, wndControl, x, y )
	self.glog:info(string.format('LFRP: Mouse Exited Window %s %s', wndHandler:GetName(), wndControl:GetName()))
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
		if tUnitEntry['bLFRP'] and not(tUnitEntry['bOptOut']) then
			if GameLib.GetPlayerUnitByName(strName)then
				--changed to get a fresh unit for distance update
				table.insert(aDist, GameLib.GetPlayerUnitByName(strName))
			end
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
	if self.tTracked[unitAdded:GetName()]['strChannel'] then
		wndChannel = btnPlayer:FindChild('ChannelName')
		wndChannel:SetText(string.format('(%s)', self.tTracked[unitAdded:GetName()]['strChannel']))
	end
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
	bLeft = eMouseButton == GameLib.CodeEnumInputMouse.Left
	bMiddle = eMouseButton == GameLib.CodeEnumInputMouse.Middle
	unit = wndControl:GetData()
	if  bLeft or bMiddle then
		unit:ShowHintArrow()
	else
		ChatLog = Apollo.GetAddon("ChatLog")
		for i, this_wnd in ipairs(ChatLog.tChatWindows) do
			if this_wnd:IsVisible() then
				input = this_wnd:FindChild('Input')
				input:SetText(string.format('/w %s ', unit:GetName()))
				ChatLog:OnInputChanged(input, input, input:GetText())
				--input:SetFocus()
				input:ClearFocus()
				input:SetFocus()
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Channels Functions
---------------------------------------------------------------------------------------------------

function LFRP:OnCloseChannelList( wndHandler, wndControl, eMouseButton )
	self.wndChannels:Show(false)
end

function LFRP:OnChannelListChanged( wndHandler, wndControl, strText )
	--self.glog:debug(string.format('%s,', wndHandler:GetName(), wndControl:GetName(), strText))
	self.tRPChannelNames = self:ParseChannelNames(wndHandler:GetText())
end

-----------------------------------------------------------------------------------------------
-- LFRP Instance
-----------------------------------------------------------------------------------------------
local LFRPInst = LFRP:new()
LFRPInst:Init()
