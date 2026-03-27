-------------------------------------------------
-- Game Loading Screen
-- modified by bc1 from 1.0.3.144 code
-- oblast_multiplayer_ui: added MP network status panel
-------------------------------------------------
include( "IconSupport" )
include( "PopulateUniques" )
local InitializePopulateUniques = InitializePopulateUniques
local PopulateUniquesForGameLoad = PopulateUniquesForGameLoad
local math_min = math.min
local math_max = math.max
include( "InstanceManager" )

local g_civID = -1;
local g_isLoadComplete = false;

-------------------------------------------------
-- MP Status Panel
-------------------------------------------------
local g_mpStatusIM = InstanceManager:new( "MPStatusEntry", "EntryLabel", Controls.MPStatusStack );
local g_prevPlayerConnected = {};

function AddLogLine( text )
	local ct = g_mpStatusIM:GetInstance();
	ct.EntryLabel:SetText( text );
	Controls.MPStatusStack:CalculateSize();
	Controls.MPStatusStack:ReprocessAnchoring();
	Controls.MPStatusScroll:CalculateInternalSize();
	Controls.MPStatusScroll:SetScrollValue( 1 );
end

function GetPlayerLine( i )
	local name = PreGame.GetNickName( i );
	if not name or name == "" then name = "Player " .. (i + 1); end
	if Network.IsPlayerHotJoining( i ) then
		return name .. ":  resyncing...";
	elseif Network.IsPlayerConnected( i ) then
		local ping = Network.GetPingTime( i );
		if ping and ping > 0 then
			return name .. ":  connected (" .. ping .. "ms)";
		end
		return name .. ":  connected";
	else
		return name .. ":  waiting...";
	end
end

function InitMPStatus()
	if not PreGame.IsMultiplayerGame() then return; end
	Controls.MPStatusBox:SetHide( false );
	g_mpStatusIM:ResetInstances();
	g_prevPlayerConnected = {};

	for i = 0, GameDefines.MAX_MAJOR_CIVS - 1 do
		if PreGame.GetSlotStatus( i ) == SlotStatus.SS_TAKEN then
			g_prevPlayerConnected[i] = Network.IsPlayerConnected( i );
			AddLogLine( GetPlayerLine( i ) );
		end
	end
	AddLogLine( "---" );
end

function ResetMPStatus()
	Controls.MPStatusBox:SetHide( true );
	g_mpStatusIM:ResetInstances();
	g_prevPlayerConnected = {};
end

function OnMPPlayerUpdated()
	for i = 0, GameDefines.MAX_MAJOR_CIVS - 1 do
		if PreGame.GetSlotStatus( i ) == SlotStatus.SS_TAKEN then
			local connected = Network.IsPlayerConnected( i );
			if g_prevPlayerConnected[i] ~= connected then
				g_prevPlayerConnected[i] = connected;
				AddLogLine( GetPlayerLine( i ) );
			end
		end
	end
end
Events.MultiplayerGamePlayerUpdated.Add( OnMPPlayerUpdated );
Events.MultiplayerGamePlayerDisconnected.Add( OnMPPlayerUpdated );

Events.ConnectedToNetworkHost.Add( function()
	AddLogLine( "> Connected to host" );
end );

Events.MultiplayerNetRegistered.Add( function()
	AddLogLine( "> Network registered" );
end );

Events.MultiplayerConnectionComplete.Add( function()
	AddLogLine( "> All players connected" );
	OnMPPlayerUpdated();
end );

Events.MultiplayerHotJoinStarted.Add( function()
	AddLogLine( "> Resyncing game state..." );
	OnMPPlayerUpdated();
end );

Events.MultiplayerHotJoinCompleted.Add( function()
	AddLogLine( "> Resync complete" );
	OnMPPlayerUpdated();
end );

Events.MultiplayerGameAbandoned.Add( function()
	AddLogLine( "> Session abandoned" );
end );

Events.MultiplayerConnectionFailed.Add( function()
	AddLogLine( "> Connection failed" );
end );

-------------------------------------------------
-- Base LoadScreen (EUI version)
-------------------------------------------------
Controls.ProgressBar:SetPercent( 1 );

ContextPtr:SetShowHideHandler(
function( isHide, isInit )
	if not isHide then
		UI.SetDontShowPopups(true);
		if not isInit then
			UIManager:SetUICursor( 1 );
			g_isLoadComplete = false;

			Controls.AlphaAnim:SetToBeginning();
			Controls.ActivateButton:SetHide(true);

			-- Force some settings off when loading a HotSeat game.
			if not PreGame.IsMultiplayerGame() then
				PreGame.SetGameOption("GAMEOPTION_DYNAMIC_TURNS", false);
				PreGame.SetGameOption("GAMEOPTION_SIMULTANEOUS_TURNS", false);
				PreGame.SetGameOption("GAMEOPTION_PITBOSS", false);
			end

			-- Sets up Selected Civ Slot
			local civ = GameInfo.Civilizations[ PreGame.GetCivilization( Game:GetActivePlayer() ) ];
			if civ then
				g_civID = civ.ID;
				local leader = GameInfo.Leaders[ GameInfo.Civilization_Leaders{ CivilizationType = civ.Type }().LeaderheadType ];

				Controls.Civilization:LocalizeAndSetText( civ.Description );
				Controls.Leader:LocalizeAndSetText( leader.Description );

				SimpleCivIconHookup( Game.GetActivePlayer(), 80, Controls.IconShadow );

				local trait = GameInfo.Traits[ GameInfo.Leader_Traits{ LeaderType = leader.Type }().TraitType ];
				Controls.BonusTitle:LocalizeAndSetText( trait.ShortDescription );
				Controls.BonusDescription:LocalizeAndSetText( trait.Description );

				InitializePopulateUniques();
				Controls.SubStack:DestroyAllChildren();
				PopulateUniquesForGameLoad( Controls.SubStack, civ.Type );

				Controls.Quote:LocalizeAndSetText( civ.DawnOfManQuote or "" );

				Controls.Image:SetTexture(civ.DawnOfManImage);
				local x, y = UIManager:GetScreenSizeVal()
				local a = math_min( x-500, y/0.75 )
				local b = math_max( 500, x-a )
				Controls.Image:Resize( a, 0.75*a )
				Controls.Details:SetSizeX( b )
				Controls.Details:ReprocessAnchoring();
			else
				g_civID = -1;
				PreGame.SetCivilization( 0, -1 );
			end
			if g_civID ~= -1 then
				Events.SerialEventDawnOfManShow(g_civID);
			end

			-- Initialize MP status panel
			InitMPStatus();
		end
	elseif not isInit then
		UIManager:SetUICursor( 0 );
		Controls.Image:UnloadTexture();
		if g_civID ~= -1 then
			Events.SerialEventDawnOfManHide(g_civID);
		end
		ResetMPStatus();
	end
end );

-------------
-- Start Game
-------------
local function OnActivateButtonClicked ()
	Events.LoadScreenClose();
	if not PreGame.IsMultiplayerGame() and not PreGame.IsHotSeatGame() then
		Game.SetPausePlayer( -1 );
	end
	UI.SetDontShowPopups( false );
end
Controls.ActivateButton:RegisterCallback( Mouse.eLClick, OnActivateButtonClicked );

----------------------
-- Key Down Processing
----------------------
ContextPtr:SetInputHandler(
function( uiMsg, wParam, lParam )
	if g_isLoadComplete
		and uiMsg == KeyEvents.KeyDown
		and ( wParam == Keys.VK_ESCAPE or wParam == Keys.VK_RETURN )
	then
		OnActivateButtonClicked();
	end
	return true;
end );

---------------------
-- Game Init Complete
---------------------
Events.SequenceGameInitComplete.Add(
function()
	g_isLoadComplete = true;

	if PreGame.IsMultiplayerGame() or PreGame.IsHotSeatGame() then
		AddLogLine( "> Game loaded — launching" );
		OnActivateButtonClicked();
	else
		Game.SetPausePlayer( Game.GetActivePlayer() );
		Controls.ActivateButtonText:LocalizeAndSetText( UI:IsLoadedGame() and "TXT_KEY_BEGIN_GAME_BUTTON_CONTINUE" or "TXT_KEY_BEGIN_GAME_BUTTON" );
		Controls.ActivateButton:SetHide(false);
		Controls.AlphaAnim:Play();
		UIManager:SetUICursor( 0 );
	end
end );
