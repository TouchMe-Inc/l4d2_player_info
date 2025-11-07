#pragma semicolon              1
#pragma newdecls               required

#include <sourcemod>
#include <player_info>


public Plugin myinfo = {
    name        = "[PlayerInfo] HLxAlias",
    author      = "TouchMe",
    description = "Show player alias",
    version     = "build_0001",
    url         = "https://github.com/TouchMe-Inc/l4d2_player_info"
};


#define TRANSLATIONS            "pi_hlx_alias.phrases"

Database HlStatsX_CE;

char g_szPlayerAlias[MAXPLAYERS + 1][MAX_NAME_LENGTH];


/**
  * Global event. Called when all plugins loaded.
  */
public void OnAllPluginsLoaded()
{
    if (LibraryExists("player_info")) {
        MakePlayerInfo(GetPlayerAlias);
    }
}

public void OnPluginStart() {
    LoadTranslations(TRANSLATIONS);

    if (SQL_CheckConfig("hlstats")) {
        SQL_TConnect(OnDatabaseConnected, "hlstats");
    }
}

public Action GetPlayerAlias(char[] szBuffer, int iLength, int iClient, int iTarget)
{
    if (g_szPlayerAlias[iClient][0] != '\0')
    {
        char szTargetName[MAX_NAME_LENGTH];
        GetClientName(iTarget, szTargetName, sizeof szTargetName);

        if (strcmp(g_szPlayerAlias[iTarget], szTargetName) == 0) {
            return Plugin_Continue;
        }

        Format(szBuffer, iLength, "%T", "DESCRIPTION", iClient, g_szPlayerAlias[iTarget]);

        return Plugin_Handled;
    }

    return Plugin_Continue;
}

void OnDatabaseConnected(Handle hOwner, Handle hHndl, const char[] szError, any iData)
{
    if (hHndl == null) {
        return;
    }

    HlStatsX_CE = view_as<Database>(hHndl);

    char szAuth[MAX_AUTHID_LENGTH];
    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if (!IsClientInGame(iClient) || IsFakeClient(iClient)) {
            continue;
        }

        if (!GetClientAuthId(iClient, AuthId_Steam2, szAuth, sizeof(szAuth))) {
            continue;
        }

        RequestGetPlayerAlias(iClient, szAuth);
    }
}

public void OnClientDisconnect(int iClient) {
    g_szPlayerAlias[iClient][0] = '\0';
}

public void OnClientAuthorized(int iClient, const char[] szAuth)
{
    if (IsFakeClient(iClient)) {
        return;
    }

    RequestGetPlayerAlias(iClient, szAuth);
}

void RequestGetPlayerAlias(int iClient, const char[] szAuth)
{
    static char szQuery[512];
    FormatEx(szQuery, sizeof(szQuery), "SELECT pn.name FROM hlstats_Players p JOIN hlstats_PlayerNames pn ON p.playerId = pn.playerId WHERE p.uniqueId = MID('%s',9) ORDER BY pn.connection_time DESC LIMIT 1;", szAuth);

    SQL_TQuery(HlStatsX_CE, SQL_GetPlayerAlias, szQuery, GetClientUserId(iClient));
}

void SQL_GetPlayerAlias(Handle hOwner, Handle hHndl, const char[] szError, int iUserId)
{
    int iClient = GetClientOfUserId(iUserId);

    if (hHndl != null && SQL_FetchRow(hHndl))
    {
        SQL_FetchString(hHndl, 0, g_szPlayerAlias[iClient], sizeof g_szPlayerAlias[]);
        return;
    }

    g_szPlayerAlias[iClient][0] = '\0';
}
