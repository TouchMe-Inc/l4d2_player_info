#if defined _player_info_included
#endinput
#endif
#define _player_info_included

typedef PlayerInfoItem = function Action(char[] szBuffer, int iLength, int iClient, int iTarget);

native int MakePlayerInfo(PlayerInfoItem item);

public SharedPlugin __pl_player_info = 
{
	name = "player_info",
	file = "player_info.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_player_info_SetNTVOptional()
{
	MarkNativeAsOptional("MakePlayerInfo");
}
#endif
