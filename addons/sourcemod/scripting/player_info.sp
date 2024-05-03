#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <steamworks>
#include <geoip>
#include <colors>


public Plugin myinfo = {
	name = "PlayerInfo",
	author = "TouchMe",
	description = "Plugin displays information about players (VPN, FS, Country, Hours, Lerp, CmdRate, UpdateRate)",
	version = "build_0009",
	url = "https://github.com/TouchMe-Inc/l4d2_player_info"
};


#define TRANSLATIONS            "player_info.phrases"

#define URL_VPN_CHECK          "http://proxy.mind-media.com/block/proxycheck.php?ip=%s"

/**
 * APP ID FOR STEAMWORKS.
 */
#define APP_L4D2                550

/**
 * Teams.
 */
#define TEAM_SPECTATOR          1
#define TEAM_INFECTED           3


enum
{
	VPN_DETECTING = 0,
	VPN_NOT_DETECTED,
	VPN_DETECTED
}

int g_iClientMenuSelectionPosition[MAXPLAYERS + 1] = {0, ...};
int g_iClientWithVpn[MAXPLAYERS + 1] = {0, ...};
int g_iClientWithFamilySharing[MAXPLAYERS + 1] = {0, ...};


/**
  * Called before OnPluginStart.
  */
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if (GetEngineVersion() != Engine_Left4Dead2)
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}

	return APLRes_Success;
}

/**
 * Called when the plugin is fully initialized and all known external references are resolved.
 */
public void OnPluginStart()
{
	LoadTranslations(TRANSLATIONS);

	RegConsoleCmd("sm_info", Cmd_Info);
}


public void SteamWorks_OnValidateClient(int iOwnerAuthId, int iAuthId)
{
	int iClient = GetClientFromSteamID(iAuthId);

	if (iClient == -1) {
		return;
	}

	/*
	 * Detect Family Sharing.
	 */
	if (iOwnerAuthId > 0 && iOwnerAuthId != iAuthId) {
		g_iClientWithFamilySharing[iClient] = iOwnerAuthId;
	} else {
		g_iClientWithFamilySharing[iClient] = 0;
	}

	/*
	 * Reset VPN status.
	 */
	g_iClientWithVpn[iClient] = VPN_DETECTING;

	/*
	 * Get player stats.
	 */
	SteamWorks_RequestStats(iClient, APP_L4D2);
}

/**
 * Send request for check VPN.
 * Called once a client is authorized and fully in-game, and after all post-connection authorizations have been performed.
 */
public void OnClientPostAdminCheck(int iClient)
{
	if (IsFakeClient(iClient)) {
		return;
	}

	char sIp[16];
	GetClientIP(iClient, sIp, sizeof(sIp));

	char sRequestUrl[96];
	FormatEx(sRequestUrl, sizeof(sRequestUrl), URL_VPN_CHECK, sIp);

	Handle hDetectVpn = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, sRequestUrl);
	SteamWorks_SetHTTPCallbacks(hDetectVpn, HttpResponseCompleted, _, HttpResponseDataReceived);
	SteamWorks_SetHTTPRequestContextValue(hDetectVpn, GetClientUserId(iClient));
	SteamWorks_SetHTTPRequestNetworkActivityTimeout(hDetectVpn, 5);
	SteamWorks_SendHTTPRequest(hDetectVpn);
}

/**
 *
 */
public void HttpResponseDataReceived(Handle hRequest, bool bFailure, int offset, int bytesReceived, int iUserId)
{
	if (bFailure)
	{
		CloseHandle(hRequest);
		return;
	}

	SteamWorks_GetHTTPResponseBodyCallback(hRequest, HttpRequestData, iUserId);
	CloseHandle(hRequest);
}

/**
 *
 */
public void HttpResponseCompleted(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode)
{
	if (bFailure || !bRequestSuccessful) {
		CloseHandle(hRequest);
	}
}

/**
 *
 */
public void HttpRequestData(const char[] sContent, int iUserId)
{
	int iClient = GetClientOfUserId(iUserId);

	if (!iClient) {
		return;
	}

	g_iClientWithVpn[iClient] = StrEqual(sContent, "Y") ? VPN_DETECTED : VPN_NOT_DETECTED;
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
		ShowPlayerMenu(iClient, g_iClientMenuSelectionPosition[iClient]);
		return Plugin_Handled;
	}

	char sArg[32];
	GetCmdArg(1, sArg, sizeof(sArg));

	int iTarget = FindOneTarget(iClient, sArg);

	if (iTarget == -1)
	{
		CReplyToCommand(iClient, "%T%T", "TAG", iClient, "BAD_ARG", iClient, sArg);
		return Plugin_Handled;
	}

	if (iTarget == iClient) {
		return Plugin_Handled;
	}

	ShowInfoMenu(iClient, iTarget);

	return Plugin_Handled;
}

/**
 *
 */
void ShowPlayerMenu(int iClient, int iSelectionPosition)
{
	int iTotalPlayers[4];
	int[][] iPlayers = new int[4][MaxClients];

	for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer ++)
	{
		if (!IsClientInGame(iPlayer) || IsFakeClient(iPlayer)) {
			continue;
		}

		int iTeam = GetClientTeam(iPlayer);

		iPlayers[iTeam][iTotalPlayers[iTeam]++] = iPlayer;
		iTotalPlayers[0] ++;
	}

	Menu hMenu = CreateMenu(HandlerPlayerMenu, MenuAction_Select|MenuAction_End);

	SetMenuTitle(hMenu, "%T", "MENU_PLAYER_TITLE", iClient);

	char sTarget[4], sName[MAX_NAME_LENGTH];

	for (int iTeam = TEAM_INFECTED; iTeam >= TEAM_SPECTATOR; iTeam --)
	{
		for (int iPlayerIndex = 0; iPlayerIndex < iTotalPlayers[iTeam]; iPlayerIndex ++)
		{
			int iPlayer = iPlayers[iTeam][iPlayerIndex];

			IntToString(iPlayer, sTarget, sizeof(sTarget));
			GetClientNameFixed(iPlayer, sName, sizeof(sName), 25);

			AddMenuItem(hMenu, sTarget, sName);
		}
	}

	DisplayMenuAtItem(hMenu, iClient, iSelectionPosition, MENU_TIME_FOREVER);
}

/**
 *
 */
int HandlerPlayerMenu(Menu hMenu, MenuAction hAction, int iClient, int iItem)
{
	switch(hAction)
	{
		case MenuAction_End: CloseHandle(hMenu);

		case MenuAction_Select:
		{
			char sTarget[4]; GetMenuItem(hMenu, iItem, sTarget, sizeof(sTarget));

			int iTarget = StringToInt(sTarget);

			if (!IsClientInGame(iTarget)) {
				ShowPlayerMenu(iClient, 0);
			}

			else
			{
				g_iClientMenuSelectionPosition[iClient] = GetMenuSelectionPosition();
				ShowInfoMenu(iClient, iTarget);
			}
		}
	}

	return 0;
}

/**
 *
 */
void ShowInfoMenu(int iClient, int iTarget)
{
	/*
	 * Get name.
	 */
	char sName[MAX_NAME_LENGTH]; GetClientNameFixed(iTarget, sName, sizeof(sName), 25);

	/*
	 * Get country & city.
	 */
	char sIp[16], sCountry[32], sCity[32];

	GetClientIP(iTarget, sIp, sizeof(sIp));

	if (IsLanIP(sIp))
	{
		FormatEx(sCountry, sizeof(sCountry), "%T", "LAN_COUNTRY", iClient);
		FormatEx(sCity, sizeof(sCity), "%T", "LAN_CITY", iClient);
	}

	else
	{
		if (!GeoipCountry(sIp, sCountry, sizeof(sCountry))) {
			FormatEx(sCountry, sizeof(sCountry), "%T", "UNKNOWN_COUNTRY", iClient);
		}

		if (!GeoipCity(sIp, sCity, sizeof(sCity))) {
			FormatEx(sCity, sizeof(sCity), "%T", "UNKNOWN_CITY", iClient);
		}
	}

	/*
	 * Get VPN status.
	 */
	char sVpnStatus[32];

	switch(g_iClientWithVpn[iTarget])
	{
		case VPN_DETECTING: FormatEx(sVpnStatus, sizeof(sVpnStatus), "%T", "VPN_DETECTING", iClient);
		case VPN_NOT_DETECTED: FormatEx(sVpnStatus, sizeof(sVpnStatus), "%T", "VPN_NOT_DETECTED", iClient);
		case VPN_DETECTED: FormatEx(sVpnStatus, sizeof(sVpnStatus), "%T", "VPN_DETECTED", iClient);
	}

	/*
	 * Get Family Sharing status.
	 */
	char sFamilySharingStatus[64];

	if (!g_iClientWithFamilySharing[iTarget]) {
		FormatEx(sFamilySharingStatus, sizeof(sFamilySharingStatus), "%T", "FS_NOT_DETECTED", iClient);
	}

	else
	{
		char sSteamID[32];
		FormatEx(sSteamID, sizeof(sSteamID), "STEAM_1:%d:%d", (g_iClientWithFamilySharing[iTarget] & 1), (g_iClientWithFamilySharing[iTarget] >> 1));
		FormatEx(sFamilySharingStatus, sizeof(sFamilySharingStatus), "%T", "FS_DETECTED", iClient, sSteamID);
	}

	/*
	 * Show menu.
	 */
	Menu hMenu = CreateMenu(HandlerInfoMenu, MenuAction_Select|MenuAction_End);

	SetMenuTitle(hMenu, "%T\n%T\n%T\n%T\n%T\n%T\n%T\n%T\n%T\n%T",
		"MENU_INFO_TITLE", iClient, sName,
		"MENU_SPACE", iClient,
		"INFO_VPN", iClient, sVpnStatus,
		"INFO_FS", iClient, sFamilySharingStatus,
		"INFO_LOCATION", iClient, sCountry, sCity,
		"INFO_PLAYED_TIME", iClient, GetClientHours(iTarget),
		"INFO_LERP", iClient, GetClientLerp(iTarget),
		"INFO_CMDRATE", iClient, GetClientAvgPackets(iTarget, NetFlow_Incoming), 
		"INFO_UPDATERATE", iClient, GetClientAvgPackets(iTarget, NetFlow_Outgoing),
		"MENU_SPACE", iClient
	);

	/*
	 * Add back button (required).
	 */
	char sBack[32];
	FormatEx(sBack, sizeof(sBack), "%T", "MENU_BACK", iClient);
	AddMenuItem(hMenu,"back", sBack);

	SetMenuExitButton(hMenu, false);

	DisplayMenu(hMenu, iClient, MENU_TIME_FOREVER);
}

/**
 *
 */
int HandlerInfoMenu(Handle hMenu, MenuAction hAction, int iParam1, int iParam2)
{
	switch(hAction)
	{
		case MenuAction_End: CloseHandle(hMenu);

		case MenuAction_Select: ShowPlayerMenu(iParam1, g_iClientMenuSelectionPosition[iParam1]);
	}

	return 0;
}

/**
 *
 */
int GetClientFromSteamID(int iAuthId)
{
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IsClientConnected(iClient) || GetSteamAccountID(iClient) != iAuthId) {
			continue;
		}

		return iClient;
	}

	return -1;
}

/**
 * Returns the interpolation value in milliseconds.
 */
float GetClientLerp(int iClient)
{
	char sLerp[32];
	GetClientInfo(iClient, "cl_interp", sLerp, sizeof(sLerp));

	return StringToFloat(sLerp) * 1000;
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

/**
 * Detect lan ip.
 */
bool IsLanIP(char src[16])
{
	char ip4[4][4];

	if (ExplodeString(src, ".", ip4, 4, 4) == 4)
	{
		int ipnum = StringToInt(ip4[0])*(1<<16) + StringToInt(ip4[1])*(1<<8) + StringToInt(ip4[2]);

		if((ipnum >= 655360 && ipnum < 655360+65535)
		|| (ipnum >= 11276288 && ipnum < 11276288+4095)
		|| (ipnum >= 12625920 && ipnum < 12625920+255))
		{
			return true;
		}
	}

	return false;
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
