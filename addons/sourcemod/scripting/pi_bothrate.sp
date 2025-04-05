#pragma semicolon              1
#pragma newdecls               required

#include <sourcemod>
#include <player_info>


public Plugin myinfo =
{
    name        = "PlayerInfoBothRate",
    author      = "TouchMe",
    description = "Show client rate",
    version     = "build_0001",
    url         = "https://github.com/TouchMe-Inc/l4d2_player_info"
};


#define TRANSLATIONS            "pi_bothrate.phrases"

/**
  * Global event. Called when all plugins loaded.
  */
public void OnAllPluginsLoaded()
{
    if (LibraryExists("player_info")) {
        MakePlayerInfo(GetPlayerBothRate);
    }
}

public void OnPluginStart() {
    LoadTranslations(TRANSLATIONS);
}

public Action GetPlayerBothRate(char[] szBuffer, int iLength, int iClient, int iTarget)
{
    Format(szBuffer, iLength, "%T", "DESCRIPTION", iClient, GetClientAvgPackets(iTarget, NetFlow_Incoming), GetClientAvgPackets(iTarget, NetFlow_Outgoing));

    return Plugin_Handled;
}
