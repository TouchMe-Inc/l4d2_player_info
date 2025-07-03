#pragma semicolon              1
#pragma newdecls               required

#include <sourcemod>
#include <geoip>
#include <player_info>


public Plugin myinfo = {
    name        = "[PlayerInfo] GeoData",
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
    char szIp[16];
    GetClientIP(iTarget, szIp, sizeof(szIp));

    char szGeoData[64];
    if (!IsLanIP(szIp))
    {
        char szCountry[32];
        if (GeoipCountryEx(szIp, szCountry, sizeof(szCountry), LANG_SERVER))
        {
            char szCity[32];
            if (GeoipCity(szIp, szCity, sizeof(szCity), LANG_SERVER)) {
                FormatEx(szGeoData, sizeof(szGeoData), "%T", "COUNTRY_AND_CITY", LANG_SERVER, szCountry, szCity);
            } else {
                FormatEx(szGeoData, sizeof(szGeoData), "%T", "ONLY_COUNTRY", LANG_SERVER, szCountry);
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
