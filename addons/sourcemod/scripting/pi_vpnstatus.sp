#pragma semicolon              1
#pragma newdecls               required

#include <sourcemod>
#include <geoip>
#include <steamworks>
#include <player_info>

public Plugin myinfo =
{
    name        = "PlayerInfoVpnStatus",
    author      = "TouchMe",
    description = "Show client VPN status",
    version     = "build_0000",
    url         = "https://github.com/TouchMe-Inc/l4d2_player_info"
};


#define TRANSLATIONS            "pi_vpnstatus.phrases"


#define URL_VPN_DETECT "https://blackbox.ipinfo.app/lookup/%s"


enum VpnStatus
{
    VpnStatus_InProgress,
    VpnStatus_NotDetected,
    VpnStatus_Detected
}


VpnStatus g_iClientVpnStatus[MAXPLAYERS + 1] = {VpnStatus_InProgress, ...};

/**
  * Global event. Called when all plugins loaded.
  */
public void OnAllPluginsLoaded()
{
    if (LibraryExists("player_info")) {
        MakePlayerInfo(GetPlayerVpnStatus);
    }
}

public void OnPluginStart() {
    LoadTranslations(TRANSLATIONS);
}

public void OnClientConnected(int iClient)
{
    if (IsFakeClient(iClient)) {
        return;
    }

    g_iClientVpnStatus[iClient] = VpnStatus_InProgress;
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

    if (!SteamWorks_IsConnected())
    {
        LogError("Steamworks: No Steam Connection!");
        return;
    }

    char sIp[16];
    GetClientIP(iClient, sIp, sizeof(sIp));

    char szRequestUrl[96];
    FormatEx(szRequestUrl, sizeof(szRequestUrl), URL_VPN_DETECT, sIp);

    Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, szRequestUrl);

    if (!hRequest) {
        CloseHandle(hRequest);
        return;
    }

    SteamWorks_SetHTTPRequestNetworkActivityTimeout(hRequest, 10);
    SteamWorks_SetHTTPCallbacks(hRequest, HttpResponseCompleted, _, HttpResponseDataReceived);
    SteamWorks_SetHTTPRequestContextValue(hRequest, GetClientUserId(iClient));
    SteamWorks_SendHTTPRequest(hRequest);
}

/**
 *
 */
public void HttpResponseDataReceived(Handle hRequest, bool bFailure, int offset, int bytesReceived, int iUserId)
{
    if (!bFailure && bytesReceived) {
        SteamWorks_GetHTTPResponseBodyCallback(hRequest, HttpRequestData, iUserId);
    }

    CloseHandle(hRequest);
}

/**
 *
 */
public void HttpResponseCompleted(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode)
{
    if (bFailure) {
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

    g_iClientVpnStatus[iClient] = StrEqual(sContent, "Y") ? VpnStatus_Detected : VpnStatus_NotDetected;
}

public Action GetPlayerVpnStatus(char[] szBuffer, int iLength, int iClient, int iTarget)
{
    char szVpnStatus[32];

    switch(g_iClientVpnStatus[iTarget])
    {
        case VpnStatus_InProgress: FormatEx(szVpnStatus, sizeof(szVpnStatus), "%T", "VPN_INPROGRESS", iClient);
        case VpnStatus_NotDetected: FormatEx(szVpnStatus, sizeof(szVpnStatus), "%T", "VPN_NOT_DETECTED", iClient);
        case VpnStatus_Detected: FormatEx(szVpnStatus, sizeof(szVpnStatus), "%T", "VPN_DETECTED", iClient);
    }

    Format(szBuffer, iLength, "%T", "DESCRIPTION", iClient, szVpnStatus);

    return Plugin_Handled;
}
