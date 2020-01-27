#include <amxmodx>
#include <cstrike>
#include <hns_mix>

#pragma semicolon				1

#define PLUGIN_NAME				"HNS_MixParticipation"
#define PLUGIN_VERSION			"1.0.0"
#define PLUGIN_AUTHOR			"Reavap"

new HnsMixStates:g_MixState;
new g_MixParticipationChangedForward;

new bool:g_OptOutOfMixParticipation[MAX_PLAYERS + 1];

public plugin_init()
{
	register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
	register_cvar(PLUGIN_NAME, PLUGIN_VERSION, FCVAR_SERVER|FCVAR_SPONLY);
	
	register_clcmd("say /np", "cmdNoPlay");
	register_clcmd("say /noplay", "cmdNoPlay");
	register_clcmd("say /play", "cmdPlay");

	g_MixParticipationChangedForward = CreateMultiForward("HNS_Mix_ParticipationChanged", ET_IGNORE, FP_CELL);
	
	if (g_MixParticipationChangedForward < 0)
	{
		g_MixParticipationChangedForward = 0;
		log_amx("Mix participation changed forward could not be created.");
	}
}

public plugin_end()
{
	DestroyForward(g_MixParticipationChangedForward);
	g_MixParticipationChangedForward = 0;
}

public HNS_Mix_StateChanged(const HnsMixStates:newState)
{
	g_MixState = newState;
}

public cmdNoPlay(const id)
{
	if (g_MixState == MixState_Inactive)
	{
		return PLUGIN_CONTINUE;
	}
	
	changeOptOutStatus(id, true);
	return PLUGIN_HANDLED;
}

public cmdPlay(const id)
{
	if (g_MixState == MixState_Inactive)
	{
		return PLUGIN_CONTINUE;
	}
	
	changeOptOutStatus(id, false);
	return PLUGIN_HANDLED;
}

changeOptOutStatus(const id, bool:optOut)
{
	if (cs_get_user_team(id) != CS_TEAM_SPECTATOR)
	{
		client_print_color(id, print_team_red, "^3You must be a spectator to execute this command");
		return;
	}

	if (g_OptOutOfMixParticipation[id] == optOut)
	{
		return;
	}

	g_OptOutOfMixParticipation[id] = optOut;

	if (!ExecuteForward(g_MixParticipationChangedForward, _, optOut))
	{
		log_amx("Could not execute mix participation changed forward");
	}

	new userName[32];
	get_user_name(id, userName, charsmax(userName));

	if (optOut)
	{
		client_print_color(0, print_team_grey, "^3%s ^1is not available for playing", userName);
	}
	else
	{
		client_print_color(0, print_team_grey, "^3%s ^1is available for playing", userName);
	}
}