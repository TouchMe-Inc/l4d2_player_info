#pragma semicolon               1
#pragma newdecls                required

#include <steamworks>
#include <geoip>
#include <colors>

#undef REQUIRE_PLUGIN
#include <readyup_rework>
#define REQUIRE_PLUGIN


public Plugin myinfo = {
	name = "PlayerInfo",
	author = "TouchMe",
	description = "Plugin displays information about players (Country, lerp, hours)",
	version = "build_0003",
	url = "https://github.com/TouchMe-Inc/l4d2_player_info"
};


/**
 * Libs.
 */
#define LIB_READY               "readyup_rework"

#define TRANSLATIONS            "player_info.phrases"

#define APP_L4D2                550

#define ITEM_BACK               9

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

bool g_bReadyUpAvailable = false;
bool g_bReadyUpOldPanelVisible[MAXPLAYERS + 1] = {false, ...};

int g_iVpnClient[MAXPLAYERS + 1] = {0, ...};


/**
 * Global event. Called when all plugins loaded.
 */
public void OnAllPluginsLoaded() {
	g_bReadyUpAvailable = LibraryExists(LIB_READY);
}

/**
 * Global event. Called when a library is removed.
 *
 * @param sName     Library name
 */
public void OnLibraryRemoved(const char[] sName) 
{
	if (StrEqual(sName, LIB_READY)) {
		g_bReadyUpAvailable = false;
	}
}

/**
 * Global event. Called when a library is added.
 *
 * @param sName     Library name
 */
public void OnLibraryAdded(const char[] sName)
{
	if (StrEqual(sName, LIB_READY)) {
		g_bReadyUpAvailable = true;
	}
}

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
 *
 */
public void OnPluginStart()
{
	LoadTranslations(TRANSLATIONS);

	RegConsoleCmd("sm_info", Cmd_Info);
}

/**
 *
 */
public void OnClientAuthorized(int iClient, const char[] sAuthId)
{
	if (sAuthId[0] == 'B' || sAuthId[9] == 'L') {
		return;
	}

	/*
	 * Get player stats.
	 */
	SteamWorks_RequestStats(iClient, APP_L4D2);

	/*
	 * Check VPN.
	 */
	g_iVpnClient[iClient] = VPN_DETECTING;

	char sIp[16];
	GetClientIP(iClient, sIp, sizeof(sIp));

	DataPack hPack = CreateDataPack();
	WritePackString(hPack, sIp);
	WritePackCell(hPack, iClient);

	char sRequestUrl[96];
	FormatEx(sRequestUrl, sizeof(sRequestUrl), "http://proxy.mind-media.com/block/proxycheck.php?ip=%s", sIp);

	Handle hDetectVpn = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, sRequestUrl);
	SteamWorks_SetHTTPCallbacks(hDetectVpn, HttpResponseCompleted, _, HttpResponseDataReceived);
	SteamWorks_SetHTTPRequestContextValue(hDetectVpn, hPack);
	SteamWorks_SetHTTPRequestNetworkActivityTimeout(hDetectVpn, 5);
	SteamWorks_SendHTTPRequest(hDetectVpn);
}

/**
 *
 */
public void HttpResponseDataReceived(Handle hRequest, bool bFailure, int offset, int bytesReceived, DataPack hPack)
{
	SteamWorks_GetHTTPResponseBodyCallback(hRequest, HttpRequestData, hPack);
	CloseHandle(hRequest);
}

/**
 *
 */
public void HttpResponseCompleted(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, DataPack hPack)
{
	if (bFailure || !bRequestSuccessful)
	{
		CloseHandle(hPack);
		CloseHandle(hRequest);
	}
}

/**
 *
 */
public void HttpRequestData(const char[] sContent, DataPack hPack)
{
	char sIp[16];
	ResetPack(hPack);

	ReadPackString(hPack, sIp, sizeof(sIp));
	int iClient = ReadPackCell(hPack);

	CloseHandle(hPack);

	if (!IsClientConnected(iClient)) {
		return;
	}

	g_iVpnClient[iClient] = StrEqual(sContent, "Y") ? VPN_DETECTED : VPN_NOT_DETECTED;
}

/**
 *
 */
Action Cmd_Info(int iClient, int iArgs)
{
	if (!iClient) {
		return Plugin_Handled;
	}

	if (!iArgs)
	{
		ShowPlayerMenu(iClient);
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
void ShowPlayerMenu(int iClient)
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

	SetMenuTitle(hMenu, "%T", "MENU_PLAYER_TITLE", iClient); // "Select a player for local mute"

	char sTarget[4], sName[MAX_NAME_LENGTH];

	for (int iTeam = TEAM_SPECTATOR; iTeam <= TEAM_INFECTED; iTeam ++)
	{
		for (int iPlayerIndex = 0; iPlayerIndex < iTotalPlayers[iTeam]; iPlayerIndex ++)
		{
			int iPlayer = iPlayers[iTeam][iPlayerIndex];

			IntToString(iPlayer, sTarget, sizeof(sTarget));
			GetClientNameFixed(iPlayer, sName, sizeof(sName), 18);

			AddMenuItem(hMenu, sTarget, sName);
		}
	}

	DisplayMenu(hMenu, iClient, MENU_TIME_FOREVER);
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
				ShowPlayerMenu(iClient);
			} else {
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
	 * ReadyUp support.
	 */
	if (g_bReadyUpAvailable)
	{
		g_bReadyUpOldPanelVisible[iClient] = IsClientPanelVisible(iClient);

		SetClientPanelVisible(iClient, false);
	}

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
	 * Send panel.
	 */
	Panel hPanel = CreatePanel();

	DrawPanelFormatText(hPanel, "%T", "MENU_INFO_TITLE", iClient, sName);
	DrawPanelFormatText(hPanel, "%T", "MENU_SPACE", iClient);

	switch(g_iVpnClient[iTarget])
	{
		case VPN_DETECTING: DrawPanelFormatText(hPanel, "%T", "INFO_VPN_DETECTING", iClient);
		case VPN_DETECTED: DrawPanelFormatText(hPanel, "%T", "INFO_VPN_DETECTED", iClient);
		case VPN_NOT_DETECTED: DrawPanelFormatText(hPanel, "%T", "INFO_VPN_NOT_DETECTED", iClient);
	}

	DrawPanelFormatText(hPanel, "%T", "INFO_LOCATION", iClient, sCountry, sCity);
	DrawPanelFormatText(hPanel, "%T", "INFO_LERP", iClient, GetClientLerp(iTarget));
	DrawPanelFormatText(hPanel, "%T", "INFO_PLAYED_TIME", iClient, GetClientHours(iTarget));
	DrawPanelFormatText(hPanel, "%T", "MENU_SPACE", iClient);
	DrawPanelFormatText(hPanel, "->%d. %T", ITEM_BACK, "MENU_BACK", iClient);

	SendPanelToClient(hPanel, iClient, DummyHandler, MENU_TIME_FOREVER);

	CloseHandle(hPanel);
}

/**
 *
 */
int DummyHandler(Handle hMenu, MenuAction hAction, int iParam1, int iParam2)
{
	/*
	 * ReadyUp support.
	 */
	if (g_bReadyUpAvailable) {
		SetClientPanelVisible(iParam1, g_bReadyUpOldPanelVisible[iParam1]);
	}

	if (hAction == MenuAction_Select && iParam2 == ITEM_BACK) {
		ShowPlayerMenu(iParam1);
	}

	return 0;
}

/**
 *
 */
bool DrawPanelFormatText(Handle hPanel, const char[] sText, any ...)
{
	char sFormatText[128];
	VFormat(sFormatText, sizeof(sFormatText), sText, 3);
	return DrawPanelText(hPanel, sFormatText);
}

/**
 *
 */
float GetClientLerp(int iClient)
{
	char sLerp[32];
	GetClientInfo(iClient, "cl_interp", sLerp, sizeof(sLerp));

	return StringToFloat(sLerp) * 1000;
}

/**
 *
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
 *
 */
bool IsLanIP(char src[16])
{
	char ip4[4][4];

	if (ExplodeString(src, ".", ip4, 4, 4) == 4)
	{
		int ipnum = StringToInt(ip4[0])*65536 + StringToInt(ip4[1])*256 + StringToInt(ip4[2]);

		if((ipnum >= 655360 && ipnum < 655360+65535) || (ipnum >= 11276288 && ipnum < 11276288+4095) || (ipnum >= 12625920 && ipnum < 12625920+255))
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
