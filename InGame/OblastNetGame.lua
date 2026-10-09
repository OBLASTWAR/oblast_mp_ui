-------------------------------------------------
-- oblast_mp_ui: in-game multiplayer network status, MP only (included by NewTurn, which no other mod overrides).
-- Expects these controls in NewTurn.xml: OblastNetBox, OblastNetHeader,
-- OblastNetStack, OblastNetChat, OblastNetDismiss, and the OblastNetRow instance.
--
-- Hidden while everything is fine. Shows every human player's connection and
-- turn state when someone is disconnected, still joining/loading, or lagging,
-- or when every turn has ended but the next one has not started (the game is
-- waiting on the network to let the turn advance).
-- Players whose slot is emptied after they drop stay listed as "left".
-- When everyone has ended the turn and the host changed during it, the
-- header says so: the new host never starts the next turn on its own, and
-- only a save + reload (or another player leaving/rejoining) gets it moving.
-------------------------------------------------
include( "OblastNetStatus" );

local Net = OblastNet;

local STUCK_AFTER = 15;		-- seconds with no active turn before we call the turn stuck
local GONE_SHOW = 90;		-- seconds to keep flagging a player who disconnected

local g_tick = 0;
local g_clock = 0;
local g_noActiveSince = nil;	-- g_clock when we last saw no player's turn active
local g_turn = -1;
local g_prev = {};				-- player id -> state string
local g_changedAt = {};			-- player id -> g_clock of last state change
local g_states = {};
local g_dismissedKey = nil;		-- problem summary the user dismissed
local g_sinceSnap = 0;
local g_wasShown = false;
local g_known = {};				-- player id -> { name, wasHost } for everyone seen in a human slot
local g_left = {};				-- player id -> g_clock when their slot stopped being a human slot
local g_hostId = nil;
local g_oldHostName = nil;		-- host before the last migration
local g_hostChangedTurn = nil;	-- game turn when the host last changed

local function AnyTurnActive()
	for i = 0, GameDefines.MAX_PLAYERS - 1 do
		local p = Players[ i ];
		if p and p:IsAlive() and p:IsTurnActive() then
			return true;
		end
	end
	return false;
end

local function Collect()
	g_states = {};
	for _, i in ipairs( Net.HumanSlots() ) do
		local p = Players[ i ];
		if p and p:IsEverAlive() then
			local s = Net.State( i );
			s.alive = p:IsAlive();
			s.turnActive = p:IsTurnActive();
			s.turnComplete = p:HasReceivedNetTurnComplete();
			if g_prev[ i ] ~= s.state then
				if g_prev[ i ] ~= nil then
					Net.Log( "ingame turn %d %s: %s -> %s", Game.GetGameTurn(), s.name, g_prev[ i ], s.state );
				end
				g_prev[ i ] = s.state;
				g_changedAt[ i ] = g_clock;
			end
			table.insert( g_states, s );
			g_known[ i ] = { name = s.name, wasHost = s.isHost };
			g_left[ i ] = nil;
		end
	end

	-- a dropped player's slot stops being SS_TAKEN, which would make them vanish from the list
	local present = {};
	for _, s in ipairs( g_states ) do
		present[ s.id ] = true;
	end
	for i, k in pairs( g_known ) do
		if not present[ i ] then
			if not g_left[ i ] then
				g_left[ i ] = g_clock;
				Net.Log( "ingame turn %d %s: slot emptied%s", Game.GetGameTurn(), k.name, k.wasHost and " (was host)" or "" );
			end
			table.insert( g_states, { id = i, name = k.name, state = "left", wasHost = k.wasHost, leftFor = g_clock - g_left[ i ] } );
		end
	end
	table.sort( g_states, function( a, b ) return a.id < b.id; end );

	local host = Matchmaking.GetHostID();
	if host == nil or host < 0 then return; end	-- mid-migration
	if g_hostId ~= nil and host ~= g_hostId then
		g_oldHostName = g_known[ g_hostId ] and g_known[ g_hostId ].name or ("Player " .. (g_hostId + 1));
		g_hostChangedTurn = Game.GetGameTurn();
		Net.Log( "ingame turn %d host changed %s -> %s", g_hostChangedTurn, g_oldHostName, Net.Name( host ) );
	end
	g_hostId = host;
end

-- why the turn is stuck, when nobody is left to wait on
local function AllDoneText( turn )
	local host = Net.Name( Matchmaking.GetHostID() );
	if g_hostChangedTurn == turn then
		return "Everyone ended the turn, but the host (" .. g_oldHostName .. ") left during the turn change. "
			.. "The game stays frozen like this. Fix: new host " .. host .. " saves, everyone reloads that save "
			.. "(or one player leaves and rejoins).";
	end
	return "Everyone ended the turn; waiting on the host (" .. host .. ") to start the next one. "
		.. "If it stays frozen: host saves, everyone reloads.";
end

-- a player counts as a problem while joining or lagging, and for a while after disconnecting
local function IsFlagged( s, stuck )
	if s.state == "gone" then
		return stuck or (g_clock - (g_changedAt[ s.id ] or 0) < GONE_SHOW);
	end
	return Net.IsProblem( s );
end

local function TurnText( s )
	if s.state == "left" then
		return " " .. Net.FormatTime( s.leftFor ) .. " ago" .. (s.wasHost and " (was host)" or "");
	elseif not s.alive then
		return "";
	elseif s.turnComplete or not s.turnActive then
		return ", turn done";
	end
	return ", playing";
end

local function Refresh()
	Collect();

	local turn = Game.GetGameTurn();
	if turn ~= g_turn or Game.IsPaused() or AnyTurnActive() then
		g_turn = turn;
		g_noActiveSince = nil;
	elseif not g_noActiveSince then
		g_noActiveSince = g_clock;
	end
	local stuckFor = g_noActiveSince and (g_clock - g_noActiveSince) or 0;
	local stuck = stuckFor >= STUCK_AFTER;

	local flagged = {};
	for _, s in ipairs( g_states ) do
		if IsFlagged( s, stuck ) then
			table.insert( flagged, s );
		end
	end

	local key = (stuck and "stuck|" or "");
	for _, s in ipairs( flagged ) do
		key = key .. s.id .. s.state .. "|";
	end
	local show = (stuck or #flagged > 0) and key ~= g_dismissedKey;
	if key ~= g_dismissedKey then
		g_dismissedKey = nil;
	end

	Controls.OblastNetBox:SetHide( not show );
	if show ~= g_wasShown then
		g_wasShown = show;
		g_sinceSnap = Net.SNAPSHOT_INTERVAL;	-- log a snapshot right away
		Net.Log( "ingame panel %s", show and "shown" or "hidden" );
	end
	if not show then return; end

	if stuck then
		local names = {};
		for _, s in ipairs( flagged ) do
			table.insert( names, s.name );
		end
		for _, s in ipairs( g_states ) do
			if not IsFlagged( s, stuck ) and s.alive and not s.isLocal and not s.turnComplete then
				table.insert( names, s.name );
			end
		end
		local who = #names > 0 and (" Waiting on: " .. table.concat( names, ", " )) or (" " .. AllDoneText( turn ));
		Controls.OblastNetHeader:SetText( "[COLOR_NEGATIVE_TEXT]Turn " .. turn .. " not advancing for " .. Net.FormatTime( stuckFor ) .. ".[ENDCOLOR]" .. who );
	else
		Controls.OblastNetHeader:SetText( "[COLOR_YELLOW]Network problem[ENDCOLOR]" );
	end

	Controls.OblastNetStack:DestroyAllChildren();
	for _, s in ipairs( g_states ) do
		local row = {};
		ContextPtr:BuildInstanceForControl( "OblastNetRow", row, Controls.OblastNetStack );
		if s.state == "left" then
			row.Text:SetText( Net.DescribeColored( s, TurnText( s ) ) );
		elseif s.state == "gone" and not IsFlagged( s, stuck ) then
			row.Text:SetText( "[COLOR_GREY]" .. s.name .. ": left[ENDCOLOR]" );
		else
			row.Text:SetText( Net.DescribeColored( s, TurnText( s ) ) );
		end
	end
	Controls.OblastNetStack:CalculateSize();
	Controls.OblastNetStack:ReprocessAnchoring();
	Controls.OblastNetInner:CalculateSize();
	Controls.OblastNetInner:ReprocessAnchoring();
	local h = Controls.OblastNetInner:GetSizeY() + 34 + 8 + 26 + 12;	-- inner offset, gap, chat button, bottom margin
	Controls.OblastNetBox:SetSizeY( h );
	Controls.OblastNetFrame:SetSizeY( h );

	g_sinceSnap = g_sinceSnap + 1;
	if g_sinceSnap >= Net.SNAPSHOT_INTERVAL then
		g_sinceSnap = 0;
		Net.LogSnapshot( "ingame", g_states, string.format( "turn=%d noActiveFor=%d stuck=%s", turn, stuckFor, tostring( stuck ) ) );
	end
end

local function OnPostChat()
	local parts = {};
	local waiting = false;
	for _, s in ipairs( g_states ) do
		if not s.isLocal then
			table.insert( parts, Net.Describe( s ) .. TurnText( s ) );
		end
		if s.state ~= "left" and (Net.IsProblem( s ) or (s.alive and not s.isLocal and not s.turnComplete)) then
			waiting = true;
		end
	end
	local text = "[net status] ";
	local stuck = g_noActiveSince and (g_clock - g_noActiveSince) >= STUCK_AFTER;
	if stuck then
		text = text .. "Turn " .. Game.GetGameTurn() .. " stuck " .. Net.FormatTime( g_clock - g_noActiveSince ) .. ". ";
	end
	text = text .. table.concat( parts, "; " );
	if stuck and not waiting then
		text = text .. ". " .. AllDoneText( Game.GetGameTurn() );
	end
	Net.SendChat( text );
end
Controls.OblastNetChat:RegisterCallback( Mouse.eLClick, OnPostChat );

Controls.OblastNetDismiss:RegisterCallback( Mouse.eLClick, function()
	-- hide until the set of problems changes
	local key = "";
	if g_noActiveSince and (g_clock - g_noActiveSince) >= STUCK_AFTER then
		key = "stuck|";
	end
	for _, s in ipairs( g_states ) do
		if IsFlagged( s, key ~= "" ) then
			key = key .. s.id .. s.state .. "|";
		end
	end
	g_dismissedKey = key;
	Controls.OblastNetBox:SetHide( true );
end );

if PreGame.IsMultiplayerGame() then
	ContextPtr:SetUpdate( function( dt )
		g_clock = g_clock + dt;
		g_tick = g_tick + dt;
		if g_tick >= 1 then
			g_tick = 0;
			Refresh();
		end
	end );
	Events.MultiplayerGamePlayerDisconnected.Add( function( i ) Net.Log( "ingame disconnected event player %s", tostring( i ) ); end );
	Events.MultiplayerHotJoinStarted.Add( function() Net.Log( "ingame hot join started" ); end );
	Events.MultiplayerHotJoinCompleted.Add( function() Net.Log( "ingame hot join completed" ); end );
	Events.MultiplayerGameHostMigration.Add( function() Net.Log( "ingame host migration, new host %d", Matchmaking.GetHostID() ); end );
end
