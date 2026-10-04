#pragma semicolon              1
#pragma newdecls               required

#include <sourcemod>
#include <geoip>
#include <steamworks>
#include <player_info>
#include <json>

public Plugin myinfo = {
    name        = "[PlayerInfo] VpnStatus",
    author      = "TouchMe",
    description = "Show client VPN status",
    version     = "build_0006",
    url         = "https://github.com/TouchMe-Inc/l4d2_player_info"
};


#define TRANSLATIONS            "pi_vpnstatus.phrases"

// URL template. {ip} — client IP, {key} — API key (empty if not set).
#define URL_VPN_DETECT          "https://proxycheck.io/v3/%s?short=1&key=%s"

#define CACHE_TTL_SECONDS       604800
#define MAX_IP_LENGTH           16
#define MAX_KEY_LENGTH          64
#define REQUEST_TIMEOUT_SECONDS 10

// Fallback: resolve stuck InProgress after this many seconds.
#define STUCK_TIMEOUT_SECONDS   30.0

// Minimum risk score reported by the API to flag a client as suspicious.
#define RISK_THRESHOLD          75


enum VpnStatus
{
    VpnStatus_InProgress,
    VpnStatus_NotDetected,
    VpnStatus_Detected
}


VpnStatus g_iClientVpnStatus[MAXPLAYERS + 1] = {VpnStatus_InProgress, ...};
int       g_iClientRisk[MAXPLAYERS + 1];

Database g_hDatabase = null;
ConVar   g_cvApiKey = null;

// Tracks in-flight HTTP requests so we can resolve their status
// even when the response body callback never fires.
ArrayList g_alRequestUserIds = null;   // index → userid
ArrayList g_alRequestHandles = null;   // index → Handle


/**
  * Global event. Called when all plugins loaded.
  */
public void OnAllPluginsLoaded()
{
    if (LibraryExists("player_info")) {
        MakePlayerInfo(GetPlayerVpnStatus);
    }
}

public void OnPluginStart()
{
    LoadTranslations(TRANSLATIONS);

    g_cvApiKey = CreateConVar("sm_pi_vpnstatus_apikey", "",
        "proxycheck.io API key (optional, increases rate limit)",
        FCVAR_PROTECTED);

    g_alRequestUserIds = new ArrayList();
    g_alRequestHandles = new ArrayList();

    InitDatabase();
}

void InitDatabase()
{
    char szError[255];
    g_hDatabase = SQLite_UseDatabase("proxycheck", szError, sizeof(szError));

    if (g_hDatabase == null) {
        SetFailState("[VpnStatus] SQLite error: %s", szError);
        return;
    }

    g_hDatabase.Query(SQL_CreateTable,
        "CREATE TABLE IF NOT EXISTS proxycheck_cache ( \
            ip          TEXT PRIMARY KEY, \
            vpn         INTEGER NOT NULL DEFAULT 0, \
            proxy       INTEGER NOT NULL DEFAULT 0, \
            risk        INTEGER NOT NULL DEFAULT 0, \
            checked_at  INTEGER NOT NULL \
        );"
    );
}

public void SQL_CreateTable(Database hDatabase, DBResultSet hResults, const char[] szError, any data)
{
    if (szError[0]) {
        LogError("[VpnStatus] CreateTable: %s", szError);
    }
}

public void OnClientConnected(int iClient)
{
    if (IsFakeClient(iClient)) {
        return;
    }

    g_iClientVpnStatus[iClient] = VpnStatus_InProgress;
    g_iClientRisk[iClient] = 0;
}

/**
 * Send request for check VPN.
 */
public void OnClientPostAdminCheck(int iClient)
{
    if (IsFakeClient(iClient)) {
        return;
    }

    char szIp[MAX_IP_LENGTH];
    GetClientIP(iClient, szIp, sizeof(szIp));

    if (IsLanIP(szIp))
    {
        g_iClientVpnStatus[iClient] = VpnStatus_NotDetected;
        g_iClientRisk[iClient] = 0;
        return;
    }

    // Fallback guard: if the status is still InProgress after the timeout,
    // resolve it to NotDetected so the client never gets stuck.
    CreateTimer(STUCK_TIMEOUT_SECONDS, Timer_ResolveStuckStatus, GetClientUserId(iClient), TIMER_FLAG_NO_MAPCHANGE);

    CheckCache(iClient, szIp);
}

/* ============================ Cache ============================ */

void CheckCache(int iClient, const char[] szIp)
{
    if (g_hDatabase == null)
    {
        SendVpnRequest(iClient, szIp);
        return;
    }

    char szEscaped[MAX_IP_LENGTH * 2];
    g_hDatabase.Escape(szIp, szEscaped, sizeof(szEscaped));

    char szQuery[256];
    FormatEx(szQuery, sizeof(szQuery),
        "SELECT vpn, risk, checked_at FROM proxycheck_cache WHERE ip = '%s'",
        szEscaped);

    DataPack hPack = new DataPack();
    hPack.WriteCell(GetClientUserId(iClient));
    hPack.WriteString(szIp);

    g_hDatabase.Query(SQL_SelectCache, szQuery, hPack, DBPrio_High);
}

public void SQL_SelectCache(Database hDatabase, DBResultSet hResults, const char[] szError, any data)
{
    DataPack hPack = view_as<DataPack>(data);
    hPack.Reset();

    int iUserId = hPack.ReadCell();

    char szIp[MAX_IP_LENGTH];
    hPack.ReadString(szIp, sizeof(szIp));
    delete hPack;

    if (szError[0])
    {
        LogError("[VpnStatus] SelectCache: %s", szError);
        return;
    }

    int iClient = GetClientOfUserId(iUserId);

    if (!iClient) {
        return;
    }

    if (hResults.FetchRow())
    {
        int iCheckedAt = hResults.FetchInt(2);
        int iAge = GetTime() - iCheckedAt;

        if (iAge < CACHE_TTL_SECONDS)
        {
            bool bSuspicious = hResults.FetchInt(0) != 0;
            int  iRisk       = hResults.FetchInt(1);

            ApplyStatus(iClient, bSuspicious, iRisk, true);
            return;
        }
    }

    SendVpnRequest(iClient, szIp);
}

void SendVpnRequest(int iClient, const char[] szIp)
{
    if (!SteamWorks_IsConnected())
    {
        LogError("[VpnStatus] Steamworks: No Steam Connection!");
        g_iClientVpnStatus[iClient] = VpnStatus_NotDetected;
        return;
    }

    char szApiKey[MAX_KEY_LENGTH];
    g_cvApiKey.GetString(szApiKey, sizeof(szApiKey));

    char szRequestUrl[256];
    FormatEx(szRequestUrl, sizeof(szRequestUrl), URL_VPN_DETECT, szIp, szApiKey);

    Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, szRequestUrl);

    if (!hRequest)
    {
        LogError("[VpnStatus] CreateHTTPRequest returned null for %s", szRequestUrl);
        g_iClientVpnStatus[iClient] = VpnStatus_NotDetected;
        return;
    }

    int iUserId = GetClientUserId(iClient);

    g_alRequestUserIds.Push(iUserId);
    g_alRequestHandles.Push(hRequest);

    SteamWorks_SetHTTPRequestNetworkActivityTimeout(hRequest, REQUEST_TIMEOUT_SECONDS);
    SteamWorks_SetHTTPCallbacks(hRequest, HttpResponseCompleted, _, HttpResponseDataReceived);
    SteamWorks_SetHTTPRequestContextValue(hRequest, iUserId);
    SteamWorks_SendHTTPRequest(hRequest);
}

/**
 * Called as response body chunks are received.
 *
 * Does NOT close the request handle — the body read is asynchronous,
 * and the handle must live until HttpResponseCompleted fires.
 */
public void HttpResponseDataReceived(Handle hRequest, bool bFailure, int offset, int bytesReceived, int iUserId)
{
    if (hRequest == null) {
        return;
    }

    if (!bFailure && bytesReceived) {
        SteamWorks_GetHTTPResponseBodyCallback(hRequest, HttpRequestData, iUserId);
    }
}

/**
 * Called once the request has fully completed (success or failure).
 *
 * The handle is NOT closed here: SteamWorks may fire the data-received
 * callback AFTER this one. Instead, the close is scheduled for the next frame.
 */
public void HttpResponseCompleted(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode)
{
    int iIndex = g_alRequestHandles.FindValue(hRequest);
    int iUserId = 0;

    if (iIndex != -1)
    {
        iUserId = g_alRequestUserIds.Get(iIndex);
    }

    if (bFailure || !bRequestSuccessful)
    {
        int iClient = GetClientOfUserId(iUserId);

        if (iClient > 0 && g_iClientVpnStatus[iClient] == VpnStatus_InProgress)
        {
            g_iClientVpnStatus[iClient] = VpnStatus_NotDetected;
            LogMessage("[VpnStatus] Request failed for client %d, marking NotDetected", iClient);
        }
    }

    DataPack hPack = new DataPack();
    hPack.WriteCell(view_as<int>(hRequest));
    CreateTimer(0.0, Timer_CloseRequest, hPack, TIMER_DATA_HNDL_CLOSE | TIMER_FLAG_NO_MAPCHANGE);
}

/**
 * Closes a request handle one frame after HttpResponseCompleted.
 */
Action Timer_CloseRequest(Handle timer, DataPack hPack)
{
    hPack.Reset();
    Handle hRequest = view_as<Handle>(hPack.ReadCell());

    if (hRequest == null) {
        return Plugin_Stop;
    }

    int iIndex = g_alRequestHandles.FindValue(hRequest);

    if (iIndex != -1)
    {
        g_alRequestHandles.Erase(iIndex);
        g_alRequestUserIds.Erase(iIndex);
    }

    CloseHandle(hRequest);

    return Plugin_Stop;
}

/**
 * Fallback: if the status is still InProgress after STUCK_TIMEOUT_SECONDS,
 * resolve it to NotDetected.
 */
Action Timer_ResolveStuckStatus(Handle timer, int iUserId)
{
    int iClient = GetClientOfUserId(iUserId);

    if (iClient <= 0) {
        return Plugin_Stop;
    }

    if (g_iClientVpnStatus[iClient] == VpnStatus_InProgress)
    {
        g_iClientVpnStatus[iClient] = VpnStatus_NotDetected;
    }

    return Plugin_Stop;
}

/**
 * Parses the raw JSON response and stores/updates the client status.
 */
public void HttpRequestData(const char[] szContent, int iUserId)
{
    int iClient = GetClientOfUserId(iUserId);

    if (!iClient) {
        return;
    }

    if (g_iClientVpnStatus[iClient] != VpnStatus_InProgress) {
        return;
    }

    JSON_Object obj = json_decode(szContent);

    if (obj == null)
    {
        char szError[256];
        json_get_last_error(szError, sizeof(szError));

        LogError("[VpnStatus] Failed to decode JSON: %s", szError);
        g_iClientVpnStatus[iClient] = VpnStatus_NotDetected;
        return;
    }

    // Check status field
    char szStatus[16];
    if (obj.GetString("status", szStatus, sizeof(szStatus))
        && !StrEqual(szStatus, "ok", false))
    {
        LogError("[VpnStatus] API returned non-ok status: %s", szContent);
        json_cleanup_and_delete(obj);
        g_iClientVpnStatus[iClient] = VpnStatus_NotDetected;
        return;
    }

    JSON_Object detections = obj.GetObject("detections");

    if (detections == null)
    {
        LogError("[VpnStatus] No detections block in response: %s", szContent);
        json_cleanup_and_delete(obj);
        g_iClientVpnStatus[iClient] = VpnStatus_NotDetected;
        return;
    }

    bool bVpn   = detections.GetBool("vpn");
    bool bProxy = detections.GetBool("proxy");
    bool bHosting = detections.GetBool("hosting");
    int  iRisk  = detections.GetInt("risk");

    json_cleanup_and_delete(obj);

    // Suspicious if the API flagged the IP as VPN/proxy,
    // or the risk score is high enough.
    bool bSuspicious = bVpn || bProxy || bHosting || iRisk >= RISK_THRESHOLD;

    char szIp[MAX_IP_LENGTH];
    GetClientIP(iClient, szIp, sizeof(szIp));

    StoreInCache(szIp, bSuspicious, iRisk);
    ApplyStatus(iClient, bSuspicious, iRisk, false);
}

void StoreInCache(const char[] szIp, bool bSuspicious, int iRisk)
{
    if (g_hDatabase == null) {
        return;
    }

    char szEscaped[MAX_IP_LENGTH * 2];
    g_hDatabase.Escape(szIp, szEscaped, sizeof(szEscaped));

    char szQuery[256];
    FormatEx(szQuery, sizeof(szQuery),
        "INSERT OR REPLACE INTO proxycheck_cache (ip, vpn, risk, checked_at) \
         VALUES ('%s', %d, %d, %d)",
        szEscaped, bSuspicious ? 1 : 0, iRisk, GetTime());

    g_hDatabase.Query(SQL_InsertDone, szQuery);
}

public void SQL_InsertDone(Database hDatabase, DBResultSet hResults, const char[] szError, any data)
{
    if (szError[0]) {
        LogError("[VpnStatus] Insert: %s", szError);
    }
}

void ApplyStatus(int iClient, bool bSuspicious, int iRisk, bool bFromCache)
{
    if (!IsClientInGame(iClient)) {
        return;
    }

    g_iClientRisk[iClient] = iRisk;

    if (bSuspicious)
    {
        g_iClientVpnStatus[iClient] = VpnStatus_Detected;

        char szName[MAX_NAME_LENGTH];
        GetClientName(iClient, szName, sizeof(szName));

        char szIp[MAX_IP_LENGTH];
        GetClientIP(iClient, szIp, sizeof(szIp));

        LogMessage("[VpnStatus] %s (%s) flagged: risk=%d %s",
            szName, szIp, iRisk, bFromCache ? "[cache]" : "[api]");
    }
    else
    {
        g_iClientVpnStatus[iClient] = VpnStatus_NotDetected;
    }
}

/**
 * Called by player_info to compose the VPN status line.
 */
public Action GetPlayerVpnStatus(char[] szBuffer, int iLength, int iClient, int iTarget)
{
    char szVpnStatus[64];
    char szRiskSuffix[32];

    if (g_iClientVpnStatus[iTarget] == VpnStatus_Detected && g_iClientRisk[iTarget] > 0)
    {
        FormatEx(szRiskSuffix, sizeof(szRiskSuffix), "%T", "VPN_RISK_SUFFIX", iClient, g_iClientRisk[iTarget]);
    }
    else
    {
        szRiskSuffix[0] = '\0';
    }

    switch(g_iClientVpnStatus[iTarget])
    {
        case VpnStatus_InProgress:
            FormatEx(szVpnStatus, sizeof(szVpnStatus), "%T", "VPN_INPROGRESS", iClient);

        case VpnStatus_NotDetected:
            FormatEx(szVpnStatus, sizeof(szVpnStatus), "%T", "VPN_NOT_DETECTED", iClient);

        case VpnStatus_Detected:
            FormatEx(szVpnStatus, sizeof(szVpnStatus), "%T", "VPN_DETECTED", iClient);
    }

    Format(szBuffer, iLength, "%T", "DESCRIPTION", iClient, szVpnStatus, szRiskSuffix);

    return Plugin_Handled;
}

/**
 * RFC 1918: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16.
 */
bool IsLanIP(const char ip[MAX_IP_LENGTH])
{
    char ip4[4][4];

    if (ExplodeString(ip, ".", ip4, sizeof ip4, sizeof ip4[]) != 4) {
        return false;
    }

    int a = StringToInt(ip4[0]);
    int b = StringToInt(ip4[1]);

    if ((a == 10)
     || (a == 172 && b >= 16 && b <= 31)
     || (a == 192 && b == 168))
        return true;

    return false;
}