#include <amxmodx>
#include <fun>
#include <cstrike>
#include <orpheu_stocks>
#include <orpheu_memory>

#pragma semicolon	1

#define PLUGIN_NAME	"HNS_InstantRestart"
#define PLUGIN_VERSION	"1.0.0"
#define PLUGIN_AUTHOR	"Reavap"

#if !defined MAX_PLAYERS
	#define MAX_PLAYERS 32
#endif

#define set_mp_pdata(%1,%2)  (OrpheuMemorySetAtAddress(g_pGameRules, %1, 1, %2))

;
new g_pGameRules;

public plugin_init() 
{
	register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
	register_cvar(PLUGIN_NAME, PLUGIN_VERSION, FCVAR_SERVER|FCVAR_SPONLY);
	
	register_srvcmd("hns_restart", "cmdRestart");
	register_srvcmd("hns_restartround", "cmdRestartRound");
}

public plugin_precache()
{
	OrpheuRegisterHook(OrpheuGetFunction("InstallGameRules"), "OnInstallGameRules", OrpheuHookPost);
}

public OnInstallGameRules()
{
	g_pGameRules = OrpheuGetReturn();
}

public cmdRestart()
{
	new aPlayers[MAX_PLAYERS], iPlayerCount, playerId;
	get_players(aPlayers, iPlayerCount);
	
	for (new i = 0; i < iPlayerCount; i++)
	{
		playerId = aPlayers[i];
		
		set_user_frags(playerId, 0);
		cs_set_user_deaths(playerId, 0);
	}
	
	set_mp_pdata("m_iNumCTWins", 0);
	set_mp_pdata("m_iNumTerroristWins", 0);
	set_mp_pdata("m_fTeamCount", get_gametime() + 0.5);
	set_mp_pdata("m_bRoundTerminating", true);
	
	return PLUGIN_HANDLED;
}

public cmdRestartRound()
{
	set_mp_pdata("m_fTeamCount", get_gametime() + 0.5);
	set_mp_pdata("m_bRoundTerminating", true);
	
	return PLUGIN_HANDLED;
}
