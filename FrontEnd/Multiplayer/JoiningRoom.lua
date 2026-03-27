----------------------------------------------------------------
-- Joining Room
-- oblast_multiplayer_ui: added connection status log panel
----------------------------------------------------------------
include( "InstanceManager" )

local g_joinFailed = false;
local g_statusIM = InstanceManager:new( "JoinStatusEntry", "EntryLabel", Controls.JoinStatusStack );
local g_seenPlayers = {};

----------------------------------------------------------------
-- Connection status log
----------------------------------------------------------------
function AddLogLine( text )
	local ct = g_statusIM:GetInstance();
	ct.EntryLabel:SetText( text );
	Controls.JoinStatusStack:CalculateSize();
	Controls.JoinStatusStack:ReprocessAnchoring();
	Controls.JoinStatusScroll:CalculateInternalSize();
	Controls.JoinStatusScroll:SetScrollValue( 1 );
end

----------------------------------------------------------------
-- Label Animation
----------------------------------------------------------------
local g_animBaseText = "";
local g_animActive = false;
local g_animTimer = 0;
local ANIM_SPEED = 0.12;
local SPINNER = { "|", "/", "-", "\\" };

-- Live status: first entry in the log stack, updated every frame
local g_liveLabel = nil;
local g_liveText  = "";

function InitLiveLabel( text )
	g_liveText = text;
	local ct = g_statusIM:GetInstance();
	g_liveLabel = ct.EntryLabel;
	g_liveLabel:SetText( "  |  " .. g_liveText );
	Controls.JoinStatusStack:CalculateSize();
	Controls.JoinStatusStack:ReprocessAnchoring();
	Controls.JoinStatusScroll:CalculateInternalSize();
end

function SetLiveText( text )
	g_liveText = text;
end

function StopLiveLabel()
	g_liveLabel = nil;
	g_liveText  = "";
end

function SetAnimLabel( text )
	g_animBaseText = text;
	g_animActive = true;
	g_animTimer = 0;
	Controls.JoiningLabel:SetText( text .. "   |" );
end

function StopAnim()
	g_animActive = false;
	Controls.JoiningLabel:SetText( g_animBaseText );
end

function OnAnimUpdate( fDTime )
	if not g_animActive then return; end
	g_animTimer = g_animTimer + fDTime;
	local idx = math.floor( g_animTimer / ANIM_SPEED ) % 4 + 1;
	Controls.JoiningLabel:SetText( g_animBaseText .. "   " .. SPINNER[idx] );
	if g_liveLabel and g_liveText ~= "" then
		g_liveLabel:SetText( "  " .. SPINNER[idx] .. "  " .. g_liveText );
		Controls.JoinStatusStack:CalculateSize();
		Controls.JoinStatusStack:ReprocessAnchoring();
		Controls.JoinStatusScroll:CalculateInternalSize();
	end
end
ContextPtr:SetUpdate( OnAnimUpdate );

----------------------------------------------------------------
-- Input Handler
----------------------------------------------------------------
function InputHandler( uiMsg, wParam, lParam )
	if uiMsg == KeyEvents.KeyDown then
		if wParam == Keys.VK_ESCAPE then
			Matchmaking.LeaveMultiplayerGame();
			UIManager:DequeuePopup( ContextPtr );
		end
	end
	return true;
end
ContextPtr:SetInputHandler( InputHandler );

Controls.CancelButton:RegisterCallback( Mouse.eLClick, function()
	Matchmaking.LeaveMultiplayerGame();
	UIManager:DequeuePopup( ContextPtr );
end );

-------------------------------------------------
-- Event Handler: MultiplayerJoinRoomComplete
-------------------------------------------------
function LogNewPlayers()
	for i = 0, GameDefines.MAX_MAJOR_CIVS - 1 do
		if PreGame.GetSlotStatus( i ) == SlotStatus.SS_TAKEN and not g_seenPlayers[i] then
			local name = PreGame.GetNickName( i );
			if name and name ~= "" then
				g_seenPlayers[i] = true;
				if Network.IsPlayerConnected( i ) then
					AddLogLine( "" );
					AddLogLine( "  >> " .. name );
					AddLogLine( "     >> connected" );
				else
					AddLogLine( "" );
					AddLogLine( "  >> " .. name );
					AddLogLine( "     .. awaiting connection" );
				end
			end
		end
	end
end

function OnJoinRoomComplete()
	if Matchmaking.IsHost() then
		UIManager:QueuePopup( Controls.StagingRoomScreen, PopupPriority.StagingScreen );
		UIManager:DequeuePopup( ContextPtr );
	else
		AddLogLine( "  >> room joined -- awaiting players" );
		LogNewPlayers();
	end
end

function OnMPPlayerUpdated()
	LogNewPlayers();
end

-------------------------------------------------
-- Event Handler: MultiplayerJoinRoomFailed
-------------------------------------------------
function OnJoinRoomFailed( iExtendedError, aExtendedErrorText )
	if iExtendedError == NetErrors.MISSING_REQUIRED_DATA then
		local szText = Locale.ConvertTextKey("TXT_KEY_MP_JOIN_FAILED_MISSING_RESOURCES");
		local count = table.count(aExtendedErrorText);
		if(count > 0) then
			szText = szText .. "[NEWLINE]";
			for index, value in pairs(aExtendedErrorText) do
				szText = szText .. "[NEWLINE] [ICON_BULLET]" .. Locale.ConvertTextKey(value);
			end
		end
		Events.FrontEndPopup.CallImmediate( szText );
	elseif iExtendedError == NetErrors.ROOM_FULL then
		Events.FrontEndPopup.CallImmediate( "TXT_KEY_MP_ROOM_FULL" );
	else
		Events.FrontEndPopup.CallImmediate( "TXT_KEY_MP_JOIN_FAILED" );
	end
	g_joinFailed = true;
	Matchmaking.LeaveMultiplayerGame();
	UIManager:DequeuePopup( ContextPtr );
end

-------------------------------------------------
-- Event Handler: MultiplayerConnectionFailed
-------------------------------------------------
function OnMultiplayerConnectionFailed()
	StopLiveLabel();
	AddLogLine( "" );
	AddLogLine( "  !! connection failed !!" );
	StopAnim();
	g_joinFailed = true;
	Events.FrontEndPopup.CallImmediate( "TXT_KEY_MP_JOIN_FAILED" );
	Matchmaking.LeaveMultiplayerGame();
	UIManager:DequeuePopup( ContextPtr );
end

-------------------------------------------------
-- Event Handler: MultiplayerGameAbandoned
-------------------------------------------------
function OnMultiplayerGameAbandoned(eReason)
	StopAnim();
	if (eReason == NetKicked.BY_HOST) then
		Events.FrontEndPopup.CallImmediate( "TXT_KEY_MP_KICKED" );
	elseif (eReason == NetKicked.NO_ROOM) then
		Events.FrontEndPopup.CallImmediate( "TXT_KEY_MP_ROOM_FULL" );
	else
		Events.FrontEndPopup.CallImmediate( "TXT_KEY_MP_JOIN_FAILED" );
	end
	g_joinFailed = true;
	Matchmaking.LeaveMultiplayerGame();
	UIManager:DequeuePopup( ContextPtr );
end

-------------------------------------------------
-- Event Handler: ConnectedToNetworkHost
-------------------------------------------------
function OnHostConnect()
	SetLiveText( "connected to host -- awaiting players..." );
	SetAnimLabel( Locale.ConvertTextKey("TXT_KEY_MULTIPLAYER_JOINING_PLAYERS") );
end

-------------------------------------------------
-- Event Handler: MultiplayerConnectionComplete
-------------------------------------------------
function OnConnectionComplete()
	StopLiveLabel();
	AddLogLine( "" );
	AddLogLine( "  *** all players connected ***" );
	AddLogLine( "  *** launching game...      ***" );
	StopAnim();
	if not Matchmaking.IsHost() then
		UIManager:QueuePopup( Controls.StagingRoomScreen, PopupPriority.StagingScreen );
		UIManager:DequeuePopup( ContextPtr );
	end
end

-------------------------------------------------
-- Event Handler: MultiplayerNetRegistered
-------------------------------------------------
function OnNetRegistered()
	AddLogLine( "  >> network handshake complete" );
	SetLiveText( "syncing game state..." );
	SetAnimLabel( Locale.ConvertTextKey("TXT_KEY_MULTIPLAYER_JOINING_GAMESTATE") );
end

-------------------------------------------------
-- Event Handler: PlayerVersionMismatchEvent
-------------------------------------------------
function OnVersionMismatch( iPlayerID, playerName, bIsHost )
	if( bIsHost ) then
		Events.FrontEndPopup.CallImmediate( Locale.ConvertTextKey( "TXT_KEY_MP_VERSION_MISMATCH_FOR_HOST", playerName ) );
		Matchmaking.KickPlayer( iPlayerID );
	else
		Events.FrontEndPopup.CallImmediate( Locale.ConvertTextKey( "TXT_KEY_MP_VERSION_MISMATCH_FOR_PLAYER" ) );
		g_joinFailed = true;
		Matchmaking.LeaveMultiplayerGame();
		UIManager:DequeuePopup( ContextPtr );
	end
end
Events.PlayerVersionMismatchEvent.Add( OnVersionMismatch );

-------------------------------------------------
-- Show / Hide Handler
-------------------------------------------------
function ShowHideHandler( bIsHide, bIsInit )
	if( not bIsInit ) then
		if not bIsHide then
			g_joinFailed = false;
			g_seenPlayers = {};
			g_statusIM:ResetInstances();
			InitLiveLabel( "initiating connection..." );
			SetAnimLabel( Locale.ConvertTextKey("TXT_KEY_MULTIPLAYER_JOINING_ROOM") );

			if (not ContextPtr:IsHotLoad()) then
				local prevCursor = UIManager:SetUICursor( 1 );
				Modding.ActivateAllowedDLC();
				UIManager:SetUICursor( prevCursor );
				Events.SystemUpdateUI( SystemUpdateUIType.RestoreUI, "JoiningRoom" );
			end

			RegisterEvents();
		else
			StopAnim();
			StopLiveLabel();
			UnregisterEvents();
		end
	end
end
ContextPtr:SetShowHideHandler( ShowHideHandler );

-------------------------------------------------
function RegisterEvents()
	Events.MultiplayerJoinRoomComplete.Add( OnJoinRoomComplete );
	Events.MultiplayerJoinRoomFailed.Add( OnJoinRoomFailed );
	Events.ConnectedToNetworkHost.Add( OnHostConnect );
	Events.MultiplayerConnectionComplete.Add( OnConnectionComplete );
	Events.MultiplayerNetRegistered.Add( OnNetRegistered );
	Events.MultiplayerConnectionFailed.Add( OnMultiplayerConnectionFailed );
	Events.MultiplayerGameAbandoned.Add( OnMultiplayerGameAbandoned );
	Events.MultiplayerGamePlayerUpdated.Add( OnMPPlayerUpdated );
end

-------------------------------------------------
function UnregisterEvents()
	Events.MultiplayerJoinRoomComplete.Remove( OnJoinRoomComplete );
	Events.MultiplayerJoinRoomFailed.Remove( OnJoinRoomFailed );
	Events.ConnectedToNetworkHost.Remove( OnHostConnect );
	Events.MultiplayerConnectionComplete.Remove( OnConnectionComplete );
	Events.MultiplayerNetRegistered.Remove( OnNetRegistered );
	Events.MultiplayerConnectionFailed.Remove( OnMultiplayerConnectionFailed );
	Events.MultiplayerGameAbandoned.Remove( OnMultiplayerGameAbandoned );
	Events.MultiplayerGamePlayerUpdated.Remove( OnMPPlayerUpdated );
end

-------------------------------------------------
function AdjustScreenSize()
	local _, screenY = UIManager:GetScreenSizeVal();
	local TOP_COMPENSATION = 52 + ((screenY - 768) * 0.3);
	local gridH = screenY - TOP_COMPENSATION;
	Controls.MainGrid:SetSizeY( gridH );
	Controls.MainGrid:ReprocessAnchoring();
	-- 62 from top (below separator) + 120 from bottom (above bottom trim)
	Controls.JoinStatusScroll:SetSizeY( gridH - 182 );
end

-------------------------------------------------
function OnUpdateUI( type, tag, iData1, iData2, strData1)
	if( type == SystemUpdateUIType.ScreenResize ) then
		AdjustScreenSize();
	elseif (not g_joinFailed and type == SystemUpdateUIType.RestoreUI and tag == "JoiningRoom") then
		if (ContextPtr:IsHidden()) then
			UIManager:QueuePopup(ContextPtr, PopupPriority.JoiningScreen);
		end
	end
end
Events.SystemUpdateUI.Add( OnUpdateUI );

AdjustScreenSize();
