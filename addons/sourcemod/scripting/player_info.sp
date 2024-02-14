#pragma semicolon               1
#pragma newdecls                required

#include <steamworks>
#include <geoip>
#include <colors>


public Plugin myinfo = {
	name = "PlayerInfo",
	author = "TouchMe",
	description = "Plugin displays information about players (Country, lerp, hours)",
	version = "build_0002",
	url = "https://github.com/TouchMe-Inc/l4d2_player_info"
};


#define TRANSLATIONS            "player_info.phrases"
#define APP_L4D2                550

/**
 *
 */
#define TEAM_SPECTATOR          1
#define TEAM_INFECTED           3


char g_sTeamColor[][] = {
	"", "{olive}", "{blue}", "{red}"
};

ConVar
	g_cvMinUpdateRate = null,
	g_cvMaxUpdateRate = null,
	g_cvMinInterpRatio = null,
	g_cvMaxInterpRatio = null
;


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

public void OnPluginStart()
{
	LoadTranslations(TRANSLATIONS);

	g_cvMinUpdateRate = FindConVar("sv_minupdaterate");
	g_cvMaxUpdateRate = FindConVar("sv_maxupdaterate");
	g_cvMinInterpRatio = FindConVar("sv_client_min_interp_ratio");
	g_cvMaxInterpRatio = FindConVar("sv_client_max_interp_ratio");

	RegConsoleCmd("sm_info", Cmd_Info);
}

public void OnClientPostAdminCheck(int iClient)
{
	if (!IsClientInGame(iClient) || IsFakeClient(iClient)) {
		return;
	}

	if (!SteamWorks_IsConnected())
	{
		LogError("Steamworks: No Steam Connection!");
		return;
	}

	SteamWorks_RequestStats(iClient, APP_L4D2);
}

Action Cmd_Info(int iClient, int iArgs)
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

	char sBracketStart[16]; FormatEx(sBracketStart, sizeof(sBracketStart), "%T", "BRACKET_START", iClient);
	char sBracketMiddle[16]; FormatEx(sBracketMiddle, sizeof(sBracketMiddle), "%T", "BRACKET_MIDDLE", iClient);
	char sBracketEnd[16]; FormatEx(sBracketEnd, sizeof(sBracketEnd), "%T", "BRACKET_END", iClient);

	CReplyToCommand(iClient, "%s%T", sBracketStart, "TAG", iClient);

	int iPlayer, iPlayedTime;
	float fLerpTime;
	char sIp[16], sName[32], sCountry[32], sCity[32];

	for (int iTeam = TEAM_SPECTATOR; iTeam <= TEAM_INFECTED; iTeam ++)
	{
		for (int iPlayerIndex = 0; iPlayerIndex < iTotalPlayers[iTeam]; iPlayerIndex ++)
		{
			iPlayer = iPlayers[iTeam][iPlayerIndex];
			FormatEx(sName, sizeof(sName), "%s%N", g_sTeamColor[iTeam], iPlayer);
			fLerpTime = GetLerpTime(iPlayer) * 1000;
			GetClientIP(iPlayer, sIp, sizeof(sIp)); 
			SteamWorks_GetStatCell(iPlayer, "Stat.TotalPlayTime.Total", iPlayedTime);

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

			CReplyToCommand(iClient, "%s%T", (--iTotalPlayers[0]) == 0 ? sBracketEnd : sBracketMiddle,
			"INFO", iClient, sName, sCountry, sCity, fLerpTime, SecToHours(iPlayedTime));
		}
	}

	return Plugin_Handled;
}

float SecToHours(int iSeconds) {
	return float(iSeconds) / 3600.0;
}

float GetLerpTime(int iClient)
{
	char buffer[32];
	float fLerpRatio, fLerpAmount, fUpdateRate;

	if (GetClientInfo(iClient, "cl_interp_ratio", buffer, sizeof(buffer))) {
		fLerpRatio = StringToFloat(buffer);
	}

	if (g_cvMinInterpRatio != null && g_cvMaxInterpRatio != null && GetConVarFloat(g_cvMinInterpRatio) != -1.0) {
		fLerpRatio = clamp(fLerpRatio, GetConVarFloat(g_cvMinInterpRatio), GetConVarFloat(g_cvMaxInterpRatio));
	}

	if (GetClientInfo(iClient, "cl_interp", buffer, sizeof(buffer))) {
		fLerpAmount = StringToFloat(buffer);
	}

	if (GetClientInfo(iClient, "cl_updaterate", buffer, sizeof(buffer))) {
		fUpdateRate = StringToFloat(buffer);
	}

	fUpdateRate = clamp(fUpdateRate, GetConVarFloat(g_cvMinUpdateRate), GetConVarFloat(g_cvMaxUpdateRate));

	return max(fLerpAmount, fLerpRatio / fUpdateRate);
}

bool IsLanIP(char src[16])
{
	char ip4[4][4];
	int ipnum;

	if (ExplodeString(src, ".", ip4, 4, 4) == 4)
	{
		ipnum = StringToInt(ip4[0])*65536 + StringToInt(ip4[1])*256 + StringToInt(ip4[2]);
		
		if((ipnum >= 655360 && ipnum < 655360+65535) || (ipnum >= 11276288 && ipnum < 11276288+4095) || (ipnum >= 12625920 && ipnum < 12625920+255))
		{
			return true;
		}
	}

	return false;
}

float max(float a, float b) {
	return (a > b) ? a : b;
}

float clamp(float inc, float low, float high) {
	return (inc > high) ? high : ((inc < low) ? low : inc);
}
