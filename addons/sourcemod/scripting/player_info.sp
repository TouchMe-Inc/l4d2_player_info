#include <steamworks>
#include <colors>


public Plugin myinfo = {
	name = "PlayerInfo",
	author = "TouchMe",
	description = "Plugin displays information about players (lerp, hours)",
	version = "build_0001"
};

#define TRANSLATIONS            "player_info.phrases"
#define APP_L4D2                550


ConVar
	g_cvMinUpdateRate = null,
	g_cvMaxUpdateRate = null,
	g_cvMinInterpRatio = null,
	g_cvMaxInterpRatio = null;


/**
  * Called before OnPluginStart.
  */
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion engine = GetEngineVersion();

	if (engine != Engine_Left4Dead2)
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

public void SteamWorks_OnValidateClient(int iOwnerAuthId, int iAuthId)
{
	int iClient = GetClientFromSteamID(iAuthId);

	if (IsValidClient(iClient) && !IsFakeClient(iClient)) {
		SteamWorks_RequestStats(iClient, APP_L4D2);
	}
}

public Action Cmd_Info(iClient, int iArgs)
{
	if (!IsValidClient(iClient)) {
		return Plugin_Continue;
	}

	int iTotalPlayers = 0;
	int[] iPlayers = new int[MaxClients];

	for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer ++)
	{
		if (!IsClientInGame(iPlayer)
		|| IsFakeClient(iPlayer)) {
			continue;
		}

		iPlayers[iTotalPlayers++] = iPlayer;
	}

	if (!iTotalPlayers) {
		return Plugin_Handled;
	}

	char sBracketStart[16]; FormatEx(sBracketStart, sizeof(sBracketStart), "%T", "BRACKET_START", iClient);
	char sBracketMiddle[16]; FormatEx(sBracketMiddle, sizeof(sBracketMiddle), "%T", "BRACKET_MIDDLE", iClient);
	char sBracketEnd[16]; FormatEx(sBracketEnd, sizeof(sBracketEnd), "%T", "BRACKET_END", iClient);

	CReplyToCommand(iClient, "%s%T", sBracketStart, "HEADER", iClient);

	int iPlayer;
	int iPlayedTime;
	float fLerpTime;

	for (int iItem = 0; iItem < iTotalPlayers; iItem ++)
	{
		iPlayer = iPlayers[iItem];
		SteamWorks_GetStatCell(iPlayer, "Stat.TotalPlayTime.Total", iPlayedTime);
		fLerpTime = GetLerpTime(iPlayer) * 1000;

		CReplyToCommand(iClient, "%s%T", (iItem + 1) == iTotalPlayers ? sBracketEnd : sBracketMiddle,
		"INFO", iClient, iPlayer, fLerpTime, SecToHours(iPlayedTime));
	}

	return Plugin_Handled;
}

int GetClientFromSteamID(int authid)
{
	for(int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if(!IsClientConnected(iClient) || GetSteamAccountID(iClient) != authid) {
			continue;
		}

		return iClient;
	}

	return -1;
}

bool IsValidClient(int iClient) {
	return (iClient > 0 && iClient <= MaxClients)
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

float max(float a, float b) {
	return (a > b) ? a : b;
}

float clamp(float inc, float low, float high) {
	return (inc > high) ? high : ((inc < low) ? low : inc);
}
