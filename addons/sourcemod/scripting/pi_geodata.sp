#pragma semicolon              1
#pragma newdecls               required

#include <sourcemod>
#include <geoip>
#include <player_info>


public Plugin myinfo =
{
    name        = "PlayerInfoGeoData",
    author      = "TouchMe",
    description = "Show client geodata",
    version     = "build_0000",
    url         = "https://github.com/TouchMe-Inc/l4d2_player_info"
};


#define TRANSLATIONS            "pi_geodata.phrases"

/**
  * Global event. Called when all plugins loaded.
  */
public void OnAllPluginsLoaded()
{
    if (LibraryExists("player_info")) {
        MakePlayerInfo(GetPlayerGeoData);
    }
}

public void OnPluginStart() {
    LoadTranslations(TRANSLATIONS);
}

public Action GetPlayerGeoData(char[] szBuffer, int iLength, int iClient, int iTarget)
{
    char sIp[16];
    GetClientIP(iTarget, sIp, sizeof(sIp));

    char szGeoData[64];
    if (!IsLanIP(sIp))
    {
        char sCountry[32];
        if (GeoipCountryEx(sIp, sCountry, sizeof(sCountry), LANG_SERVER))
        {
            char sCity[32];
            if (GeoipCity(sIp, sCity, sizeof(sCity), LANG_SERVER)) {
                FormatEx(szGeoData, sizeof(szGeoData), "%T", "COUNTRY_AND_CITY", LANG_SERVER, sCountry, sCity);
            } else {
                FormatEx(szGeoData, sizeof(szGeoData), "%T", "ONLY_COUNTRY", LANG_SERVER, sCountry);
            }
        }
        else
        {
            FormatEx(szGeoData, sizeof(szGeoData), "%T", "UNKNOWN_COUNTRY", LANG_SERVER);
        }
    }
    else
    {
        FormatEx(szGeoData, sizeof(szGeoData), "%T", "LAN", LANG_SERVER);
    }

    Format(szBuffer, iLength, "%T", "DESCRIPTION", iClient, szGeoData);

    return Plugin_Handled;
}

bool IsLanIP(char ip[16])
{
    char ip4[4][4];

    if (ExplodeString(ip, ".", ip4, 4, 4) == 4)
    {
        int ipnum = StringToInt(ip4[0]) * 65536 + StringToInt(ip4[1]) * 256 + StringToInt(ip4[2]);

        if((ipnum >= 655360 && ipnum < 655360+65535)
        || (ipnum >= 11276288 && ipnum < 11276288+4095)
        || (ipnum >= 12625920 && ipnum < 12625920+255))
        {
            return true;
        }
    }

    return false;
}
