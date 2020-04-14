#include <amxmodx>
#include <fakemeta>
#include <fun>
#include <cstrike>

#pragma semicolon	1

#define PLUGIN_NAME	"HNS_InstantRestart"
#define PLUGIN_VERSION	"1.0.1"
#define PLUGIN_AUTHOR	"Reavap"

new const g_HalfLifeMultiPlayClass[] = "CHalfLifeMultiplay";
new const Float:g_RestartDelay = 0.3;

public plugin_init() 
{
	register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
	register_cvar(PLUGIN_NAME, PLUGIN_VERSION, FCVAR_SERVER|FCVAR_SPONLY);

	register_srvcmd("hns_restart", "cmdRestart");
	register_srvcmd("hns_restartround", "cmdRestartRound");
}

public cmdRestart()
{
	new players[MAX_PLAYERS], playercount, playerId;
	get_players(players, playercount);
	
	for (new i = 0; i < playercount; i++)
	{
		playerId = players[i];
		
		set_user_frags(playerId, 0);
		cs_set_user_deaths(playerId, 0);
	}

	set_gamerules_int(g_HalfLifeMultiPlayClass, "m_iNumCTWins", 0);
	set_gamerules_int(g_HalfLifeMultiPlayClass, "m_iNumTerroristWins", 0);
	set_gamerules_float(g_HalfLifeMultiPlayClass, "m_fTeamCount", get_gametime() + g_RestartDelay);
	set_gamerules_int(g_HalfLifeMultiPlayClass, "m_bRoundTerminating", true);
	
	return PLUGIN_HANDLED;
}

public cmdRestartRound()
{
	set_gamerules_float(g_HalfLifeMultiPlayClass, "m_fTeamCount", get_gametime() + g_RestartDelay);
	set_gamerules_int(g_HalfLifeMultiPlayClass, "m_bRoundTerminating", true);
	
	return PLUGIN_HANDLED;
}
