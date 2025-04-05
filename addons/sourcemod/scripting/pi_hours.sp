#pragma semicolon              1
#pragma newdecls               required

#include <sourcemod>
#include <player_info>
#include <steamworks>


public Plugin myinfo =
{
    name        = "PlayerInfoHours",
    author      = "TouchMe",
    description = "Show client hours",
    version     = "build_0000",
    url         = "https://github.com/TouchMe-Inc/l4d2_player_info"
};


#define TRANSLATIONS            "pi_hours.phrases"

/**
 * APP ID FOR STEAMWORKS.
 */
#define APP_L4D2                550


/**
  * Global event. Called when all plugins loaded.
  */
public void OnAllPluginsLoaded()
{
    if (LibraryExists("player_info")) {
        MakePlayerInfo(GetPlayerHours);
    }
}

public void OnPluginStart() {
    LoadTranslations(TRANSLATIONS);
}

public Action GetPlayerHours(char[] szBuffer, int iLength, int iClient, int iTarget)
{
    Format(szBuffer, iLength, "%T", "DESCRIPTION", iClient, GetClientHours(iTarget));

    return Plugin_Handled;
}

/**
 * Returns the hours played by the player from steam statistics.
 */
float GetClientHours(int iClient)
{
    int iPlayedTime = 0;

    if (!SteamWorks_GetStatCell(iClient, "Stat.TotalPlayTime.Total", iPlayedTime)) {
        return 0.0;
    }

    return float(iPlayedTime) / 3600.0;
}

public void SteamWorks_OnValidateClient(int iOwnerAuthId, int iAuthId) {
    SteamWorks_RequestStatsAuthID(iAuthId, APP_L4D2);
}
