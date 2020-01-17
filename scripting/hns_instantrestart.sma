#include <amxmodx>
#include <fakemeta>
#include <fun>
#include <cstrike>

#pragma semicolon	1

#define PLUGIN_NAME	"HNS_InstantRestart"
#define PLUGIN_VERSION	"1.0.1"
#define PLUGIN_AUTHOR	"Reavap"

new const multiPlayerClass[] = "CHalfLifeMultiplay";
new const Float:restartDelay = 0.3;

public plugin_init() 
{
	register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
	register_cvar(PLUGIN_NAME, PLUGIN_VERSION, FCVAR_SERVER|FCVAR_SPONLY);

	register_srvcmd("hns_restart", "cmdRestart");
	register_srvcmd("hns_restartround", "cmdRestartRound");
}

public cmdRestart()
{
	new players[MAX_PLAYERS], playerCount, playerId;
	get_players(players, playerCount);
	
	for (new i = 0; i < playerCount; i++)
	{
		playerId = players[i];
		
		set_user_frags(playerId, 0);
		cs_set_user_deaths(playerId, 0);
	}

	set_gamerules_int(multiPlayerClass, "m_iNumCTWins",0);
	set_gamerules_int(multiPlayerClass, "m_iNumTerroristWins", 0);
	set_gamerules_float(multiPlayerClass, "m_fTeamCount", get_gametime() + restartDelay);
	set_gamerules_int(multiPlayerClass, "m_bRoundTerminating", true);
	
	return PLUGIN_HANDLED;
}

public cmdRestartRound()
{
	set_gamerules_float(multiPlayerClass, "m_fTeamCount", get_gametime() + restartDelay);
	set_gamerules_int(multiPlayerClass, "m_bRoundTerminating", true);
	
	return PLUGIN_HANDLED;
}
