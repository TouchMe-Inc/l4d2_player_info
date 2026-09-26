#pragma semicolon              1
#pragma newdecls               required

#include <sourcemod>
#include <player_info>

public Plugin myinfo = {
    name        = "[PlayerInfo] SteamId",
    author      = "TouchMe",
    description = "Show client steamid",
    version     = "build_0000",
    url         = "https://github.com/TouchMe-Inc/l4d2_player_info"
};


#define TRANSLATIONS            "pi_steamid.phrases"

/**
  * Global event. Called when all plugins loaded.
  */
public void OnAllPluginsLoaded()
{
    if (LibraryExists("player_info")) {
        MakePlayerInfo(GetPlayerInterp);
    }
}

public void OnPluginStart() {
    LoadTranslations(TRANSLATIONS);
}

public Action GetPlayerInterp(char[] szBuffer, int iLength, int iClient, int iTarget)
{
    char szSteamId[MAX_AUTHID_LENGTH];
    GetClientAuthId(iTarget, AuthId_Steam2, szSteamId, sizeof szSteamId, false);

    Format(szBuffer, iLength, "%T", "DESCRIPTION", iClient, szSteamId);

    return Plugin_Handled;
}
