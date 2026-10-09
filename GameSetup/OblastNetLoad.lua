-------------------------------------------------
-- oblast_mp_ui: network status panel on the loading (leader) screen, MP only.
-- Based on oblast_mp_ui's LoadScreen status log. Expects these controls in
-- LoadScreen.xml: OblastNetBox, OblastNetHeader, OblastNetStack,
-- OblastNetEvents, OblastNetChat, and the OblastNetRow instance.
--
-- After a desync the game reloads every client and then holds each one on
-- this screen until all players have loaded (SequenceGameInitComplete).
-- NewTurn fires LuaEvents.OblastNetInGameLoaded when the in-game UI has
-- been built, which is when our own load is done; from then on we are only
-- waiting for other players, and the panel says so and counts.
-------------------------------------------------
include( "OblastNetStatus" );

OblastLoad = {};
local L = OblastLoad;
local Net = OblastNet;

local CHAT_AFTER = 20;	-- seconds of waiting before offering "post to chat"
local MAX_EVENTS = 6;

local g_active = false;
local g_elapsed = 0;
local g_tick = 0;
local g_sinceSnap = 0;
local g_loadedAt = nil;		-- g_elapsed when our own load finished
local g_prev = {};			-- player id -> state string
local g_events = {};
local g_states = {};

local function AddEvent( text )
	table.insert( g_events, Net.FormatTime( g_elapsed ) .. "  " .. text );
	if #g_events > MAX_EVENTS then
		table.remove( g_events, 1 );
	end
	Controls.OblastNetEvents:SetText( table.concat( g_events, "[NEWLINE]" ) );
	Net.Log( "loadscreen %s %s", Net.FormatTime( g_elapsed ), text );
end

local function Refresh()
	g_states = {};
	for _, i in ipairs( Net.HumanSlots() ) do
		local s = Net.State( i );
		table.insert( g_states, s );
		if g_prev[ i ] ~= nil and g_prev[ i ] ~= s.state then
			AddEvent( Net.Describe( s ) );
		end
		g_prev[ i ] = s.state;
	end

	Controls.OblastNetStack:DestroyAllChildren();
	for _, s in ipairs( g_states ) do
		local row = {};
		ContextPtr:BuildInstanceForControl( "OblastNetRow", row, Controls.OblastNetStack );
		row.Text:SetText( Net.DescribeColored( s ) );
	end
	Controls.OblastNetStack:CalculateSize();
	Controls.OblastNetStack:ReprocessAnchoring();

	if g_loadedAt then
		local waited = g_elapsed - g_loadedAt;
		Controls.OblastNetHeader:SetText( "[COLOR_YELLOW]Loaded. Waiting for other players: " .. Net.FormatTime( waited ) .. "[ENDCOLOR]" );
		Controls.OblastNetChat:SetHide( waited < CHAT_AFTER );
	else
		Controls.OblastNetHeader:SetText( "Loading... " .. Net.FormatTime( g_elapsed ) );
		Controls.OblastNetChat:SetHide( true );
	end
end

local function OnUpdate( dt )
	if not g_active then return; end
	g_elapsed = g_elapsed + dt;
	g_tick = g_tick + dt;
	if g_tick < 1 then return; end
	g_tick = 0;
	Refresh();
	if g_loadedAt then
		g_sinceSnap = g_sinceSnap + 1;
		if g_sinceSnap >= Net.SNAPSHOT_INTERVAL then
			g_sinceSnap = 0;
			Net.LogSnapshot( "load-wait " .. Net.FormatTime( g_elapsed - g_loadedAt ), g_states );
		end
	end
end

local function OnPostChat()
	local waited = g_loadedAt and (g_elapsed - g_loadedAt) or g_elapsed;
	local problems = {};
	for _, s in ipairs( g_states ) do
		if Net.IsProblem( s ) then
			table.insert( problems, Net.Describe( s ) );
		end
	end
	local text = "[net status] " .. Net.Name( Game.GetActivePlayer() ) .. " stuck on loading screen " .. Net.FormatTime( waited ) .. ". ";
	if #problems > 0 then
		text = text .. "Not ready: " .. table.concat( problems, ", " );
	else
		text = text .. "Everyone shows connected; someone has not finished loading.";
	end
	Net.SendChat( text );
	AddEvent( "status posted to chat" );
end

function L.OnShow()
	g_active = PreGame.IsMultiplayerGame();
	Controls.OblastNetBox:SetHide( not g_active );
	if not g_active then return; end
	g_elapsed, g_tick, g_sinceSnap = 0, 1, 0;
	g_loadedAt = nil;
	g_prev, g_events, g_states = {}, {}, {};
	Controls.OblastNetEvents:SetText( "" );
	Controls.OblastNetChat:RegisterCallback( Mouse.eLClick, OnPostChat );
	ContextPtr:SetUpdate( OnUpdate );
	Refresh();
	Net.LogSnapshot( "loadscreen shown", g_states );
end

function L.OnHide()
	g_active = false;
	Controls.OblastNetBox:SetHide( true );
end

function L.OnGameInitComplete()
	if not g_active then return; end
	if g_loadedAt then
		Net.LogSnapshot( "load released after waiting " .. Net.FormatTime( g_elapsed - g_loadedAt ), g_states );
	else
		Net.Log( "load complete %s (no wait)", Net.FormatTime( g_elapsed ) );
	end
end

LuaEvents.OblastNetInGameLoaded.Add( function()
	if g_active and not g_loadedAt then
		g_loadedAt = g_elapsed;
		AddEvent( "loaded, waiting for other players" );
		Refresh();
		Net.LogSnapshot( "local load done", g_states );
	end
end );

Events.ConnectedToNetworkHost.Add( function() if g_active then AddEvent( "connected to host" ); end end );
Events.MultiplayerConnectionComplete.Add( function() if g_active then AddEvent( "all players connected" ); end end );
Events.MultiplayerHotJoinStarted.Add( function() if g_active then AddEvent( "resync started" ); end end );
Events.MultiplayerHotJoinCompleted.Add( function() if g_active then AddEvent( "resync complete" ); end end );
Events.MultiplayerGameHostMigration.Add( function() if g_active then AddEvent( "host migrated" ); end end );
Events.MultiplayerGameAbandoned.Add( function() if g_active then AddEvent( "session abandoned" ); end end );
Events.MultiplayerConnectionFailed.Add( function() if g_active then AddEvent( "connection failed" ); end end );
