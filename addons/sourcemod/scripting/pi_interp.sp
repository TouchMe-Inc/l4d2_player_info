#pragma semicolon              1
#pragma newdecls               required

#include <sourcemod>
#include <player_info>

public Plugin myinfo =
{
    name        = "PlayerInfoInterp",
    author      = "TouchMe",
    description = "Show client iterpolation",
    version     = "build_0000",
    url         = "https://github.com/TouchMe-Inc/l4d2_player_info"
};


#define TRANSLATIONS            "pi_interp.phrases"

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
    Format(szBuffer, iLength, "%T", "DESCRIPTION", iClient, GetClientInterp(iTarget));

    return Plugin_Handled;
}

/**
 * Returns the interpolation value in milliseconds.
 */
float GetClientInterp(int iClient)
{
    char szInterp[32];
    GetClientInfo(iClient, "cl_interp", szInterp, sizeof(szInterp));

    return StringToFloat(szInterp) * 1000.0;
}
