/* [ZP] Addon: Last Human Beam (By AttackerCat33)

   Description:
    - This addon add a feature to find any last human quickly like the pro server use today, there is zp43 and zp50 support too
    Now added zpa, zpsp (Experimental, also zp4.3 in the test)

   - Changelog(s):
        
        - v1.0:
            - Initial Release.
        
        - v1.1:
            - Added multiple zombie plague support
            - Fixed beam still exist when the last human die
        
        - v1.2:
            - Optimization to the plugin
            - Added support for AMXX 1.8.3 automatically
            - Added option to add a list of the allowed modes (ZP50 Only, ZP43 users will be infection rounds only the allowed one)
            - Added option to customize the beam (in the sma file)
        
        - v1.3_beta:
            - Rebuilt the plugin from scratch with improvements
            - Non Zombie Plague 5.0+ version will try to include one of the versions (4.3, Advance, Special)
                (Must be one file only in the include folder when compiling)
            - Updated the beam configuration (Now the player can modify the beam with say commands)
            - Added proximity sensor (can be modified by player)
            - Added plugin silent mode (idle mode when no players, still experimental)
            - Added beam activation (can be modified by player)
            - Allowed mode(s) now is available for ZP Special
*/

#include < amxmodx >
#include < fakemeta >
#include < nvault >
#include < hamsandwich >

/* Uncomment this if you want to activate debugging */
//#define ENABLE_DEBUGGING

#if defined ENABLE_DEBUGGING
    #define LOG_FILE "zp50_addon_lasthuman_beam_logs.log"
#endif

/* Uncomment this if you want to activate Zombie Plague 5.0+ version */
#define ZP50_VERSION

/* Don't care about these */
#define MAXPLAYERS 32
#define VAULT_NAME "LastHumanBeamConf"

/* Change the sound & sprite here */
#define BEAM_SPRITE "sprites/laserbeam.spr"
#define PROXIMITY_MIN_DISTANCE 150.0 /* Minimum distance to start beeping */
#define PROXIMITY_SND "buttons/blip1.wav" /* Sound file */

/* Don't modify anything :) */
#if defined ZP50_VERSION
    #include < zp50_core >
    #include < zp50_gamemodes >
#else
    /* Must have only one of them by uncommenting the two and keep the included one */
    #tryinclude < zombieplague >
    #tryinclude < zombie_plague_advance >
    #tryinclude < zombie_plague_special >
#endif

/* Do some replacements */
#if AMXX_VERSION_NUM >= 183
    #define client_disconnect client_disconnected /* Replacing client_disconnect with client_disconnected automatically */
    #define strbreak argbreak /* Replacing strbreak with argbreak automatically */
#else
    #define write_coord_f(%1) engfunc(EngFunc_WriteCoord, %1) /* A placeholder for the native write_coord_f */
#endif

/* Add allowed mode(s) here (ZP50, ZPSP only, ZPA is not support because doesn't have getting gamemode id native by default) */
#if defined ZP50_VERSION
new const g_AllowedModes[][] = {
    "Infection Mode",
    "Multiple Infection Mode"
};
#else 
    #if defined _zombie_plague_special_included
    new const g_AllowedModes[][] = {
        "Infection",
        "Multi"
    };
    #endif
#endif

/* Beam Specifectaions */
enum _:BeamConfiguration {
    Beam_Color_R = 0,
    Beam_Color_G,
    Beam_Color_B,
    Beam_Brightness,
    Beam_Size,
    bool:Beam_Activated,
    bool:Beam_BeepSound
};

/* Variables */
new g_szSprite, g_Vault, g_iForward, g_iConfiguration[MAXPLAYERS+1][BeamConfiguration];
new bool:g_IsForwardRegistered = false;
new g_iBeamRate[MAXPLAYERS+1], Float:g_flLastSoundTime[MAXPLAYERS+1];

public plugin_precache() {
    /* Register the plugin */
    register_plugin("[ZP] Addon: Last Human Beam", "1.3", "AttackerCat33");

    /* Forwards */
    RegisterHam(Ham_Spawn, "player", "CBasePlayer_Spawn_Post", true);
    RegisterHam(Ham_Killed, "player", "CBasePlayer_Killed_Post", true);

    /* Register the cmd */
    register_clcmd("say", "CMD_Handler");
    register_clcmd("say_team", "CMD_Handler");

    /* Open the vault */
    g_Vault = nvault_open(VAULT_NAME);

    /* Check if there is error */
    if(g_Vault == INVALID_HANDLE)
        set_fail_state("[ZP] Error opening the vault");

    /* Precache sprite */
    g_szSprite = precache_model(BEAM_SPRITE);
}

public client_putinserver(iPlr) {
    LoadData(iPlr); /* Load saved data */
}

public client_disconnect(iPlr) {
    SaveData(iPlr); /* Saved modified data */
    CheckCount(); /* Check count to set plugin into silent mode */
}

public CMD_Handler(iPlr) {
    /* Not alive or connected */
    if(!is_user_connected(iPlr) || !is_user_alive(iPlr))
        return PLUGIN_HANDLED;
    
    /* Reading the command */
    new said[192];
    read_args(said, charsmax(said));
    remove_quotes(said);
    trim(said);

    new szCommand[32], szParameters[160];
    strbreak(said, szCommand, charsmax(szCommand), szParameters, charsmax(szParameters));

    if(equal(szCommand, "/beam")) {
        if(!szParameters[0]) {
            client_print(iPlr, print_chat, "[ZP] Beam customization commands:");
            client_print(iPlr, print_chat, "1- 'say /beam color <red> <green> <blue>' to control beam color");
            client_print(iPlr, print_chat, "2- 'say /beam brightness <brightness>' to control beam brightness");
            client_print(iPlr, print_chat, "3- 'say /beam size <size>' to control the beam size");
            client_print(iPlr, print_chat, "4- 'say /beam beep' to activate/de-activate beep sounds for near distance");
            client_print(iPlr, print_chat, "5- 'say /beam activate' to activate/de-activate beam");
            return PLUGIN_HANDLED;
        }

        new szSubCMD[32], iValues[128];
        strbreak(szParameters, szSubCMD, charsmax(szSubCMD), iValues, charsmax(iValues));

        /* 'say /beam color <red> <green> <blue>' */
        if(equal(szSubCMD, "color")) {
            new iColors[3][8];
            parse(iValues, iColors[0], charsmax(iColors[]), iColors[1], charsmax(iColors[]), iColors[2], charsmax(iColors[]));

            if(!iValues[0]) {
                client_print(iPlr, print_chat, "[ZP] Usage: 'say /beam color <red> <green> <blue>'");
                return PLUGIN_HANDLED;
            }

            for(new i = 0; i < 3; i++) {
                g_iConfiguration[iPlr][i] = clamp(str_to_num(iColors[i]), 0, 255);
            }

            client_print(iPlr, print_chat, "[ZP] Current Colors: Red: %d - Green: %d - Blue: %d",
            g_iConfiguration[iPlr][Beam_Color_R],
            g_iConfiguration[iPlr][Beam_Color_G],
            g_iConfiguration[iPlr][Beam_Color_B]);

            SaveData(iPlr);
            return PLUGIN_HANDLED;
        } else if(equal(szSubCMD, "brightness")) { /* 'say /beam brightness <brightness>' */
            if(!iValues[0]) {
                client_print(iPlr, print_chat, "[ZP] Usage: 'say /beam brightness <brightness>'");
                return PLUGIN_HANDLED;
            }

            g_iConfiguration[iPlr][Beam_Brightness] = clamp(str_to_num(iValues), 0, 255);
            client_print(iPlr, print_chat, "[ZP] Current brightness: %d", g_iConfiguration[iPlr][Beam_Brightness]);

            SaveData(iPlr);
            return PLUGIN_HANDLED;

        } else if(equal(szSubCMD, "size")) { /* 'say /beam size <size>' */
            if(!iValues[0]) {
                client_print(iPlr, print_chat, "[ZP] Usage: 'say /beam size <size>'");
                return PLUGIN_HANDLED;
            }

            g_iConfiguration[iPlr][Beam_Size] = clamp(str_to_num(iValues), 0, 40);
            client_print(iPlr, print_chat, "[ZP] Current size: %d", g_iConfiguration[iPlr][Beam_Size]);

            SaveData(iPlr);
            return PLUGIN_HANDLED;
        } else if(equal(szSubCMD, "activate")) { /* 'say /beam activate' */
            g_iConfiguration[iPlr][Beam_Activated] = !(g_iConfiguration[iPlr][Beam_Activated]);
            client_print(iPlr, print_chat, "[ZP] Beam status: %s", g_iConfiguration[iPlr][Beam_Activated] ? "Activated" : "De-Activated");

            SaveData(iPlr);
            return PLUGIN_HANDLED;
        } else if(equal(szSubCMD, "beep")) { /* 'say /beam beep' */
            g_iConfiguration[iPlr][Beam_BeepSound] = !(g_iConfiguration[iPlr][Beam_BeepSound]);
            client_print(iPlr, print_chat, "[ZP] Beam beep sound status: %s", g_iConfiguration[iPlr][Beam_BeepSound] ? "Activated" : "De-Activated");

            SaveData(iPlr);
            return PLUGIN_HANDLED;
        }
    }

    return PLUGIN_CONTINUE;
}

#if defined ZP50_VERSION
public zp_fw_core_last_human() {
#else
public zp_user_last_human() {
#endif
    if(!IsAllowedMode())
        return;
    
    ManageForward(true);
}

#if defined ZP50_VERSION
public zp_fw_gamemodes_end() {
#else
public zp_round_ended() {
#endif
    #if defined ENABLE_DEBUGGING
    log_to_file(LOG_FILE, "[ZP] Round ended, unregistering the forward....");
    #endif
    ManageForward(false);
}

public CBasePlayer_Killed_Post()
    CheckCount();

public CBasePlayer_Spawn_Post()
    CheckCount();

public CBasePlayer_PreThink_Post(iPlr) {
    /* Not connected? */
    if(!is_user_connected(iPlr))
        return FMRES_IGNORED;
    
    /* Dead? */
    if(!is_user_alive(iPlr))
        return FMRES_IGNORED;
    
    /* Only works for 1 human left */
    if(GetHumanCount() != 1)
        return FMRES_IGNORED;
    
    /* Beam rate */
    if(++g_iBeamRate[iPlr] < 13)
        return FMRES_IGNORED;
    
    g_iBeamRate[iPlr] = 0;

    static Float:flOrigin[2][3];

    /* Get human origin */
    if(IsLastHuman(iPlr))
        pev(iPlr, pev_origin, flOrigin[0]);
    
    if(IsUserZombie(iPlr) && !is_user_bot(iPlr)) {
        pev(iPlr, pev_origin, flOrigin[1]); /* Get zombie origin */

        if(g_iConfiguration[iPlr][Beam_Activated]) {
            message_begin(MSG_ONE_UNRELIABLE, SVC_TEMPENTITY, { 0, 0, 0 }, iPlr) /* Creating the beam */
            {
                write_byte(0);
                write_coord_f(flOrigin[0][0]);
                write_coord_f(flOrigin[0][1]);
                write_coord_f(flOrigin[0][2]);
                write_coord_f(flOrigin[1][0]);
                write_coord_f(flOrigin[1][1]);
                write_coord_f(flOrigin[1][2]);
                write_short(g_szSprite);
                write_byte(1);
                write_byte(1);
                write_byte(1);
                write_byte(g_iConfiguration[iPlr][Beam_Size]);
                write_byte(0);
                write_byte(g_iConfiguration[iPlr][Beam_Color_R]);
                write_byte(g_iConfiguration[iPlr][Beam_Color_G]);
                write_byte(g_iConfiguration[iPlr][Beam_Color_B]);
                write_byte(g_iConfiguration[iPlr][Beam_Brightness]);
                write_byte(150);
            }
            message_end();
        }
    }

    if(g_iConfiguration[iPlr][Beam_BeepSound]) {
        static Float:flDistance;
        flDistance = get_distance_f(flOrigin[1], flOrigin[0]);
        
        if(flDistance <= PROXIMITY_MIN_DISTANCE) {
            static Float:flGameTime, Float:flBeepInterval;
            flGameTime = get_gametime();
            flBeepInterval = (0.01 + (flDistance / PROXIMITY_MIN_DISTANCE) * (1.0 - 0.01));

            if(flGameTime - g_flLastSoundTime[iPlr] >= flBeepInterval) {
                client_cmd(iPlr, "spk %s", PROXIMITY_SND);
                g_flLastSoundTime[iPlr] = flGameTime;
            }
        }
    }

    return FMRES_IGNORED;
}

public plugin_end() {
    nvault_close(g_Vault);
}

LoadData(iPlr) {
    new szAuthID[35], szData[64];
    get_user_authid(iPlr, szAuthID, charsmax(szAuthID));

    if(nvault_get(g_Vault, szAuthID, szData, charsmax(szData))) {
        new BeamConfig[BeamConfiguration][8];
        parse(szData, BeamConfig[Beam_Color_R], charsmax(BeamConfig[]), BeamConfig[Beam_Color_G], charsmax(BeamConfig[]), BeamConfig[Beam_Color_B], charsmax(BeamConfig[]),
        BeamConfig[Beam_Brightness], charsmax(BeamConfig[]), BeamConfig[Beam_Size], charsmax(BeamConfig[]), BeamConfig[Beam_BeepSound], charsmax(BeamConfig[]), 
        BeamConfig[Beam_Activated], charsmax(BeamConfig[]));

        #if defined ENABLE_DEBUGGING
        log_to_file(LOG_FILE, "[ZP] Viewing loaded data for '%s': %s", szAuthID, szData);
        #endif

        g_iConfiguration[iPlr][Beam_Color_R] = str_to_num(BeamConfig[Beam_Color_R]);
        g_iConfiguration[iPlr][Beam_Color_G] = str_to_num(BeamConfig[Beam_Color_G]);
        g_iConfiguration[iPlr][Beam_Color_B] = str_to_num(BeamConfig[Beam_Color_B]);
        g_iConfiguration[iPlr][Beam_Brightness] = str_to_num(BeamConfig[Beam_Brightness]);
        g_iConfiguration[iPlr][Beam_Size] = str_to_num(BeamConfig[Beam_Size]);
        g_iConfiguration[iPlr][Beam_BeepSound] = bool:str_to_num(BeamConfig[Beam_BeepSound]);
        g_iConfiguration[iPlr][Beam_Activated] = bool:str_to_num(BeamConfig[Beam_Activated]);

    } else {
        g_iConfiguration[iPlr][Beam_Color_R] = 10;
        g_iConfiguration[iPlr][Beam_Color_G] = 10;
        g_iConfiguration[iPlr][Beam_Color_B] = 255;
        g_iConfiguration[iPlr][Beam_Brightness] = 255;
        g_iConfiguration[iPlr][Beam_Size] = 33;
        g_iConfiguration[iPlr][Beam_BeepSound] = false;
        g_iConfiguration[iPlr][Beam_Activated] = true;
    }
}

SaveData(iPlr) {
    new szAuthID[35], szData[64];
    get_user_authid(iPlr, szAuthID, charsmax(szAuthID));
    formatex(szData, charsmax(szData), "%d %d %d %d %d %d %d", g_iConfiguration[iPlr][Beam_Color_R], g_iConfiguration[iPlr][Beam_Color_G], g_iConfiguration[iPlr][Beam_Color_B],
    g_iConfiguration[iPlr][Beam_Brightness], g_iConfiguration[iPlr][Beam_Size], g_iConfiguration[iPlr][Beam_BeepSound], g_iConfiguration[iPlr][Beam_Activated]);
    #if defined ENABLE_DEBUGGING
    log_to_file(LOG_FILE, "[ZP] Viewing data for '%s': %s", szAuthID, szData);
    #endif

    nvault_set(g_Vault, szAuthID, szData);
}

stock ManageForward(bool:register) {
    if(g_IsForwardRegistered == register)
        return;
    
    if(register) {
        g_iForward = register_forward(FM_PlayerPreThink, "CBasePlayer_PreThink_Post", 1);
        g_IsForwardRegistered = true;
        #if defined ENABLE_DEBUGGING
        log_to_file(LOG_FILE, "[ZP] Forward successfully registered!");
        #endif
    } else {
        unregister_forward(FM_PlayerPreThink, g_iForward, 1);
        g_IsForwardRegistered = false;
        #if defined ENABLE_DEBUGGING
        log_to_file(LOG_FILE, "[ZP] Forward successfully unregistered!");
        #endif
    }
}

stock CheckCount() {
    new iPlayers[MAXPLAYERS], iNum;
    get_players(iPlayers, iNum, "a");

    #if defined ENABLE_DEBUGGING
    log_to_file(LOG_FILE, "[ZP] Checking count: %d - Status: %s", iNum, iNum == 0 ? "Required to disable forward, please wait..." : "No need to disable forward");
    #endif

    ManageForward(iNum > 0);
}

stock bool:IsAllowedMode() {
    #if defined ZP50_VERSION || defined _zombie_plague_special_included
    new iModes[sizeof g_AllowedModes], g_CurrentMode = GetCurrentMode();

    for(new i = 0; i < sizeof g_AllowedModes; i++) {

        /* Get gamemode(s) id */
        iModes[i] = GetModeID(g_AllowedModes[i]);

        /* Invalid mode? */
        if(iModes[i] == -1)
            return false;
        
        /* Round isn't started yet */
        #if defined ZP50_VERSION
        if(g_CurrentMode == ZP_NO_GAME_MODE)
        #else
        if(g_CurrentMode == 0 /* 0 means None or no gamemode in zpsp, check sma file */)
        #endif
            return false;
        
        /* Current mode is from the list */
        if(g_CurrentMode == iModes[i])
            return true;
    }
    #else
        #if defined _zombie_plague_advance_included
        if(zp_has_round_started() /* Round Started */ && !zp_is_nemesis_round() /* Isn't nemesis */ && !zp_is_plague_round() /* Isn't plague */
        && !zp_is_swarm_round() /* Isn't swarm */ && !zp_is_survivor_round() /* Isn't survivor */ && !zp_is_assassin_round() /* Isn't assassin */
        && !zp_is_sniper_round() /* Isn't sniper */ && !zp_is_lnj_round() /* Isn't armageddon */)
            return true;
        #else
        if(zp_has_round_started() /* Round started */ && !zp_is_nemesis_round() /* Isn't nemesis */ && !zp_is_plague_round() /* Isn't plague */
        && !zp_is_swarm_round() /* Isn't swarm */ && !zp_is_survivor_round() /* Isn't survivor */)
            return true;
        #endif
    #endif

    return false;
}

bool:IsUserZombie(iPlr) {
    #if defined ZP50_VERSION
    return bool:zp_core_is_zombie(iPlr);
    #else
    return bool:zp_get_user_zombie(iPlr);
    #endif
}

bool:IsLastHuman(iPlr) {
    #if defined ZP50_VERSION
    return bool:zp_core_is_last_human(iPlr);
    #else
    return bool:zp_get_user_last_human(iPlr);
    #endif
}

GetHumanCount() {
    #if defined ZP50_VERSION
    return zp_core_get_human_count();
    #else
    return zp_get_human_count();
    #endif
}

#if defined ZP50_VERSION || defined _zombie_plague_special_included
GetCurrentMode() {
    #if defined ZP50_VERSION
    return zp_gamemodes_get_current();
    #else
        #if defined _zombie_plague_special_included
        return zp_get_current_mode();
        #endif
    #endif
}
#endif

#if defined ZP50_VERSION || defined _zombie_plague_special_included
GetModeID(const name[]) {
    #if defined ZP50_VERSION
    return zp_gamemodes_get_id(name);
    #else
        #if defined _zombie_plague_special_included
        return zp_get_gamemode_id(name);
        #endif
    #endif
}
#endif