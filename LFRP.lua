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
	o.strCharName = ""

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
	    self.wndMain:Show(true)

		Apollo.RegisterSlashCommand("lfrp", "ShowLFRP", self)
		self.UpdateTimer = ApolloTimer.Create(1, true, "OnUpdateTimer", self)
		self.NameTimer = ApolloTimer.Create(1, true, "OnNameTimer", self)
		Event_FireGenericEvent("SendVarToRover", "tSomeVariable", Apollo.GetAddon("LFRP"))
	end
end

-----------------------------------------------------------------------------------------------
-- LFRP Functions
-----------------------------------------------------------------------------------------------

function LFRP:SetupComms()
	self.Comm = ICCommLib.JoinChannel("_LFRP_", ICCommLib.CodeEnumICCommChannelType.Global)
	if not(self.Comm:IsReady()) then
		Print("LFRP: Unable to Establish Comm")
	else
		self.Comm:SetReceivedMessageFunction("OnMessageReceived")
		self.Comm:SetSendMessageResultFunction("OnMessageSent")
		self.Comm:SetThrottledFunction("OnMessageThrottled")
	end
end

function LFRP:SendQuery(unit)
	self.Comm:SendPrivateMessage(unit:GetName(), tostring(kEnumLFRP_Query))
end

function LFRP:OnMessageReceived(channel, strMessage, idMessage)
	if channel == "_LFRP_" then
		strPattern = '(%a*%s%a*),(%d)'
		strSender,mType = string.match(strMessage, strPattern)
		mType = tonumber(mType)
		if mType == kEnumLFRP_Query then
			self.Comm:SendPrivateMessage(strSender,kEnumLFRP_Response)
		elseif mType == kEnumLFRP_Response then
			for this_name, this_tUnitEntry in pairs(self.tTracked) do
				if strSender == this_name then
					this_tUnitEntry['bLFRP'] = true
				end
			end
		else
			Print('LFRP:UnknownMessage')
		end
	end
end


function LFRP:ShowLFRP()
	Print('LFRP:ShowLFRP')
	self:PopulateRoleplayerList()
	self.wndMain:Show(true)
end

function LFRP:OnUnitCreated(unitCreated)
	if unitCreated:GetType() == "Player" then
		if not (unitCreated:GetName() == self.strCharName) then
			local tUnitEntry = {}
			tUnitEntry['unit'] = unitCreated
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
	self:PopulateRoleplayerList()
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
end

function LFRP:OnMouseEnter( wndHandler, wndControl, x, y )
	self.UpdateTimer:Stop()
end

function LFRP:OnMouseExit( wndHandler, wndControl, x, y )
	self.UpdateTimer:Start()
end

-----------------------------------------------------------------------------------------------
-- PlayerList Functions
-----------------------------------------------------------------------------------------------

function LFRP:PopulateRoleplayerList()
	self:DestroyRoleplayerList()
	
	for strName,tUnitEntry in pairs(self.tTracked) do
		if tUnitEntry['bLFRP'] then
			self:AddPlayerToList(tUnitEntry['unit'])
		end
	end
	
	self.wndPlayerList:ArrangeChildrenVert()
end

function LFRP:AddPlayerToList(unitAdded)
	btnPlayer = Apollo.LoadForm(self.xmlDoc, 'PlayerLine', self.wndPlayerList, self)
	btnPlayer:SetText(unitAdded:GetName())
	btnPlayer:SetData(unitAdded)
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
