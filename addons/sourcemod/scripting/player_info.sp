#pragma semicolon              1
#pragma newdecls               required

#include <sourcemod>
#include <colors>


public Plugin myinfo = {
    name        = "PlayerInfo",
    author      = "TouchMe",
    description = "[API ONLY] Plugin displays information about players",
    version     = "build_0010",
    url         = "https://github.com/TouchMe-Inc/l4d2_player_info"
};


#define TRANSLATIONS            "player_info.phrases"

#define MAX_SHORT_NAME_LENGTH 24

/**
 * Teams.
 */
#define TEAM_SPECTATOR          1
#define TEAM_INFECTED           3


Handle g_hPlayerInfo = INVALID_HANDLE;
int g_iPlayerInfoSize = 0;

int g_iClientMenuSelectionPosition[MAXPLAYERS + 1] = {0, ...};


public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    if (GetEngineVersion() != Engine_Left4Dead2)
    {
        strcopy(error, err_max, "Plugin only supports Left 4 Dead 2.");
        return APLRes_SilentFailure;
    }

    CreateNative("MakePlayerInfo", Native_MakePlayerInfo);

    // Library.
    RegPluginLibrary("player_info");

    return APLRes_Success;
}

any Native_MakePlayerInfo(Handle hPlugin, int iParams)
{
    Function funcPlayerInfo = GetNativeFunction(1);

    Handle hDescription = CreateForward(ET_Single, Param_String, Param_Cell, Param_Cell, Param_Cell);

    AddToForward(hDescription, hPlugin, funcPlayerInfo);

    int iIndex = PushArrayCell(g_hPlayerInfo, hDescription);

    g_iPlayerInfoSize = GetArraySize(g_hPlayerInfo);

    return iIndex;
}

public void OnPluginStart()
{
    LoadTranslations(TRANSLATIONS);

    RegConsoleCmd("sm_info", Cmd_Info);

    g_hPlayerInfo = CreateArray();
}

/**
 *
 */
Action Cmd_Info(int iClient, int iArgs)
{
    if (!iClient) {
        return Plugin_Handled;
    }

    g_iClientMenuSelectionPosition[iClient] = 0;

    if (!iArgs)
    {
        ShowPlayersMenu(iClient, g_iClientMenuSelectionPosition[iClient]);
        return Plugin_Handled;
    }

    char sArg[MAX_NAME_LENGTH];
    GetCmdArg(1, sArg, sizeof(sArg));

    int iTarget = FindOneTarget(iClient, sArg);

    if (iTarget == -1)
    {
        CReplyToCommand(iClient, "%T%T", "TAG", iClient, "BAD_ARG", iClient, sArg);
        return Plugin_Handled;
    }

    if (iTarget != iClient) {
        ShowPlayerInfoMenu(iClient, iTarget);
    }

    return Plugin_Handled;
}

/**
 *
 */
void ShowPlayersMenu(int iClient, int iSelectionPosition)
{
    int iTotalPlayers[4];
    int[][] iPlayers = new int[4][MaxClients];

    for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer ++)
    {
        if (!IsClientInGame(iPlayer) || IsFakeClient(iPlayer) || iClient == iPlayer) {
            continue;
        }

        int iTeam = GetClientTeam(iPlayer);

        iPlayers[iTeam][iTotalPlayers[iTeam]++] = iPlayer;
        iTotalPlayers[0] ++;
    }

    Menu menu = CreateMenu(HandlerPlayerMenu, MenuAction_Select|MenuAction_End);

    SetMenuTitle(menu, "%T", "MENU_PLAYERS_TITLE", iClient);

    char szTarget[4], szPlayerName[MAX_NAME_LENGTH];

    for (int iTeam = TEAM_INFECTED; iTeam >= TEAM_SPECTATOR; iTeam --)
    {
        for (int iPlayerIndex = 0; iPlayerIndex < iTotalPlayers[iTeam]; iPlayerIndex ++)
        {
            int iPlayer = iPlayers[iTeam][iPlayerIndex];

            IntToString(iPlayer, szTarget, sizeof(szTarget));
            GetClientNameFixed(iPlayer, szPlayerName, sizeof(szPlayerName), MAX_SHORT_NAME_LENGTH);

            AddMenuItem(menu, szTarget, szPlayerName);
        }
    }

    DisplayMenuAtItem(menu, iClient, iSelectionPosition, MENU_TIME_FOREVER);
}

/**
 *
 */
int HandlerPlayerMenu(Menu menu, MenuAction action, int iClient, int iItem)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            g_iClientMenuSelectionPosition[iClient] = GetMenuSelectionPosition();

            char szTarget[4]; GetMenuItem(menu, iItem, szTarget, sizeof(szTarget));

            int iTarget = StringToInt(szTarget);

            if (!IsClientInGame(iTarget)) {
                ShowPlayersMenu(iClient, 0);
            } else {
                ShowPlayerInfoMenu(iClient, iTarget);
            }
        }

        case MenuAction_End: delete menu;
    }

    return 0;
}

void ShowPlayerInfoMenu(int iClient, int iTarget)
{
    Menu menu = CreateMenu(HandleShowInfoMenu, MenuAction_End|MenuAction_Cancel);

    char szTargetName[MAX_NAME_LENGTH];
    GetClientNameFixed(iTarget, szTargetName, sizeof(szTargetName), MAX_SHORT_NAME_LENGTH);

    SetMenuTitle(menu, "%T", "MENU_PLAYER_INFO_TITLE", iClient, szTargetName);

    char szDescription[64];
    for (int iIdx = 0; iIdx < g_iPlayerInfoSize; iIdx ++)
    {
        Handle hDescription = GetArrayCell(g_hPlayerInfo, iIdx);
        ExecuteForward_GetDescription(hDescription, szDescription, sizeof(szDescription), iClient, iTarget);

        if (szDescription[0] == '\0') {
            continue;
        }

        AddMenuItem(menu, "", szDescription, ITEMDRAW_DISABLED);
    }

    DisplayMenu(menu, iClient, MENU_TIME_FOREVER);
}

public int HandleShowInfoMenu(Menu menu, MenuAction action, int iClient, int iSelectedIndex)
{
    switch (action)
    {
        case MenuAction_Cancel: ShowPlayersMenu(iClient, g_iClientMenuSelectionPosition[iClient]);

        case MenuAction_End: delete menu;
    }

    return 0;
}

Action ExecuteForward_GetDescription(Handle hForward, char[] szBuffer, int iLength, int iClient, int iTarget)
{
    Action aReturn = Plugin_Continue;

    Call_StartForward(hForward);
    Call_PushStringEx(szBuffer, iLength, SM_PARAM_STRING_COPY|SM_PARAM_STRING_UTF8, SM_PARAM_COPYBACK);
    Call_PushCell(iLength);
    Call_PushCell(iClient);
    Call_PushCell(iTarget);
    Call_Finish(aReturn);

    return aReturn;
}

/**
 *
 */
void GetClientNameFixed(int iClient, char[] name, int length, int iMaxSize)
{
    GetClientName(iClient, name, length);

    if (strlen(name) > iMaxSize)
    {
        name[iMaxSize - 3] = name[iMaxSize - 2] = name[iMaxSize - 1] = '.';
        name[iMaxSize] = '\0';
    }
}

/*
 * Returns the player that was found by the request.
 */
int FindOneTarget(int iClient, const char[] sTarget)
{
    char iTargetName[MAX_TARGET_LENGTH];
    int iTargetList[1];
    bool isMl = false;

    bool bFound = ProcessTargetString(
        sTarget,
        iClient,
        iTargetList,
        1,
        COMMAND_FILTER_CONNECTED|COMMAND_FILTER_NO_IMMUNITY|COMMAND_FILTER_NO_MULTI|COMMAND_FILTER_NO_BOTS,
        iTargetName,
        sizeof(iTargetName),
        isMl
    ) > 0;

    return bFound ? iTargetList[0] : -1;
}
