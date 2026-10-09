-------------------------------------------------
-- oblast_mp_ui: multiplayer network status, shared by LoadScreen and NewTurn.
-- Read-only: only queries Network/PreGame/Players state, sends nothing
-- except an explicit, user-clicked chat line.
-- Every state change and a periodic snapshot go to Lua.log, prefixed
-- "OblastNet:", so a stuck load or stuck turn can be matched against
-- net_connection_debug.log / net_message_debug.log afterwards.
-------------------------------------------------

OblastNet = OblastNet or {};
local M = OblastNet;

M.SNAPSHOT_INTERVAL = 5;	-- seconds between Lua.log snapshots while something is wrong
M.LAG_PING = 1000;			-- ms

-- human slots, from PreGame so it works on the loading screen too
function M.HumanSlots()
	local slots = {};
	for i = 0, GameDefines.MAX_MAJOR_CIVS - 1 do
		if PreGame.GetSlotStatus( i ) == SlotStatus.SS_TAKEN then
			table.insert( slots, i );
		end
	end
	return slots;
end

function M.Name( i )
	local name = PreGame.GetNickName( i );
	if not name or name == "" then
		name = "Player " .. (i + 1);
	end
	return name;
end

-- state: "you", "joining", "kicked", "gone", "lag", "ok"
-- ("left" is set by OblastNetGame for a player whose slot was emptied after they dropped)
function M.State( i )
	local s = { id = i, name = M.Name( i ) };
	s.isLocal = (i == Game.GetActivePlayer());
	s.isHost = (Matchmaking.GetHostID() == i);
	s.connected = Network.IsPlayerConnected( i );
	s.joining = Network.IsPlayerHotJoining( i );
	s.kicked = Network.IsPlayerKicked( i );
	s.ping = s.isLocal and -1 or Network.GetPingTime( i );
	if s.isLocal then
		s.state = "you";
	elseif s.kicked then
		s.state = "kicked";
	elseif s.joining then
		s.state = "joining";
	elseif not s.connected then
		s.state = "gone";
	elseif s.ping and s.ping >= M.LAG_PING then
		s.state = "lag";
	else
		s.state = "ok";
	end
	return s;
end

local STATE_TEXT = {
	you = "you",
	ok = "connected",
	lag = "connected, lagging",
	joining = "joining / loading",
	gone = "NOT CONNECTED",
	kicked = "kicked",
	left = "left",
};
local STATE_COLOR = {
	you = "[COLOR_WHITE]",
	ok = "[COLOR_POSITIVE_TEXT]",
	lag = "[COLOR_YELLOW]",
	joining = "[COLOR_YELLOW]",
	gone = "[COLOR_NEGATIVE_TEXT]",
	kicked = "[COLOR_NEGATIVE_TEXT]",
	left = "[COLOR_GREY]",
};

function M.IsProblem( s )
	return s.state == "joining" or s.state == "gone" or s.state == "lag";
end

-- plain text, for the log and for chat
function M.Describe( s )
	local t = s.name .. ": " .. STATE_TEXT[ s.state ];
	if s.ping and s.ping >= 0 and not s.isLocal then
		t = t .. " (" .. s.ping .. "ms)";
	end
	if s.isHost then
		t = t .. " [host]";
	end
	return t;
end

function M.DescribeColored( s, extra )
	return STATE_COLOR[ s.state ] .. M.Describe( s ) .. (extra or "") .. "[ENDCOLOR]";
end

function M.FormatTime( secs )
	secs = math.floor( secs );
	return string.format( "%d:%02d", math.floor( secs / 60 ), secs % 60 );
end

function M.Log( fmt, ... )
	print( "OblastNet: " .. string.format( fmt, ... ) );
end

-- one line per player plus the session-wide flags, for Lua.log
function M.LogSnapshot( tag, states, extra )
	local parts = {};
	for _, s in ipairs( states ) do
		local p = string.format( "%d=%s c%d j%d k%d p%s%s", s.id, s.state,
			s.connected and 1 or 0, s.joining and 1 or 0, s.kicked and 1 or 0,
			tostring( s.ping ), s.isHost and " H" or "" );
		if s.turnActive ~= nil then
			p = p .. string.format( " ta%d tc%d", s.turnActive and 1 or 0, s.turnComplete and 1 or 0 );
		end
		table.insert( parts, p );
	end
	M.Log( "%s everyoneConnected=%s %s | %s", tag, tostring( Network.IsEveryoneConnected() ), extra or "", table.concat( parts, " | " ) );
end

function M.SendChat( text )
	local ok, err = pcall( Network.SendChat, text, -1, -1 );
	M.Log( "chat sent ok=%s %s: %s", tostring( ok ), tostring( err or "" ), text );
end
