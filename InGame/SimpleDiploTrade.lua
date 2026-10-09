-------------------------------------------------
-- Diplomacy and Advisors Buttons that float out in the screen
-- modified by bc1 from 1.0.3.144 brave new world code
-- fix spinning globe bug
-- Oblast: Close button no longer refuses/withdraws PvP proposals
-------------------------------------------------
include( "TradeLogic" );
Events.OpenPlayerDealScreenEvent.Add( OnOpenPlayerDealScreen );
Controls.ModifyButton:RegisterCallback( Mouse.eLClick, OnModify );



ContextPtr:SetInputHandler( InputHandler );

-- Oblast: a click passes void1 (0) as OnBack's flag, and 0 is truthy in Lua,
-- so Close refused their proposal / withdrew ours. Close should only close.
Controls.CloseButton:RegisterCallback( Mouse.eLClick, function() OnBack(); end );

----------------------------------------------------------------
-- 'Active' (local human) player has changed
----------------------------------------------------------------
function OnDiploActivePlayerChanged()
	if not ContextPtr:IsHidden() then
		OnBack();
	end
end
Events.GameplaySetActivePlayer.Add(OnDiploActivePlayerChanged);


----------------------------------------------------------------        
----------------------------------------------------------------  
ContextPtr:SetShowHideHandler( function( isHide, isInit )
	OnShowHide( isHide, isInit );-- the one defined in TradeLogic which got overwritten by Firaxis, leading to the bug
	if not isInit and not isHide then
		LuaEvents.OpenSimpleDiploTrade();
	end
end);


----------------------------------------------------------------        
----------------------------------------------------------------  
function OnOpenAILeaderDiploTrade()
	-- An AI leader trade was started while we're open, close ourselves.
	if not ContextPtr:IsHidden() then
		OnBack();
	end
end
LuaEvents.OpenAILeaderDiploTrade.Add(OnOpenAILeaderDiploTrade);
