#include <amxmodx>
#include <fakemeta>
#include <fun>
#include <cstrike>
#include <reapi>

#pragma semicolon	1

#define PLUGIN_NAME		"HNS_InstantRestart"
#define PLUGIN_VERSION	"1.1.0"
#define PLUGIN_AUTHOR	"Reavap"

#if defined set_member_game
	#define RUNNING_REAPI 1
#else
	new const g_HalfLifeMultiPlayClass[] = "CHalfLifeMultiplay";
#endif

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

	#if defined RUNNING_REAPI
		set_member_game(m_iNumCTWins, 0);
		set_member_game(m_iNumTerroristWins, 0);
	#else
		set_gamerules_int(g_HalfLifeMultiPlayClass, "m_iNumCTWins", 0);
		set_gamerules_int(g_HalfLifeMultiPlayClass, "m_iNumTerroristWins", 0);
	#endif
	
	initiateRoundRestart();
	
	return PLUGIN_HANDLED;
}

public cmdRestartRound()
{
	initiateRoundRestart();
	return PLUGIN_HANDLED;
}

initiateRoundRestart()
{
	new const Float:restartDelay = 0.3;
	new Float:restartAt = get_gametime() + restartDelay;

	#if defined RUNNING_REAPI
		set_member_game(m_flRestartRoundTime, restartAt);
		set_member_game(m_bRoundTerminating, true);
	#else
		set_gamerules_float(g_HalfLifeMultiPlayClass, "m_fTeamCount", restartAt);
		set_gamerules_int(g_HalfLifeMultiPlayClass, "m_bRoundTerminating", true);
	#endif
}