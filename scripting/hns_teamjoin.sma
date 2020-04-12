#define PLUGIN_NAME			"HNS_TeamJoin"
#define PLUGIN_VERSION		"1.0.0"
#define PLUGIN_AUTHOR		"Reavap"

#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <fakemeta>
#include <hns_mix>

#pragma semicolon	1

#define blockTeamJoining() (g_MixState != MixState_Inactive)
#define transferMenuCanBeUsed() (g_MixState != MixState_Inactive)
#define isValidTeamTransfer(%1,%2) ((%1 == CS_TEAM_CT || %1 == CS_TEAM_T) != (%2 == CS_TEAM_CT || %2 == CS_TEAM_T) && %1 != CS_TEAM_UNASSIGNED)

new const g_JoinTeamCmd[] = "jointeam";
new const g_JoinClassCmd[] = "joinclass";

new const g_ClassBasePlayer[] = "CBasePlayer";
new const g_MemberTeamChanged[] = "m_bTeamChanged";

new const g_TeamSelectMenus[][] =
{
	"#Team_Select",
	"#Team_Select_Spect",
	"#IG_Team_Select",
	"#IG_Team_Select_Spect"
};

const g_VGuiMenuTeamSelect = 2;
const g_VGuiMenuClassSelectT = 26;
const g_VGuiMenuClassSelectCT = 27;

new const GetPlayersFlags:g_GetPlayerFlags = GetPlayers_ExcludeBots | GetPlayers_ExcludeHLTV;

new Trie:g_BlockedTeamSelectMenus;
new g_ShowMenuMessageId;
new HnsMixStates:g_MixState;

public plugin_natives()
{
	register_library("hns_teamjoin");

	register_native("hns_transfer_all_players", "nativeTransferAllPlayers", 0);
	register_native("hns_transfer_player", "nativeTransferPlayer", 0);
	register_native("hns_swap_players", "nativeSwapPlayers", 0);
}

public plugin_init()
{
	register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
	register_cvar(PLUGIN_NAME, PLUGIN_VERSION, FCVAR_SERVER|FCVAR_SPONLY);

	g_ShowMenuMessageId = get_user_msgid("ShowMenu");

	register_message(g_ShowMenuMessageId, "messageShowMenu");
	register_message(get_user_msgid("VGUIMenu"), "messageVGUIMenu");

	register_clcmd("chooseteam", "cmdBlockJoinTeam");
	register_clcmd(g_JoinTeamCmd, "cmdBlockJoinTeam");
	register_clcmd(g_JoinClassCmd, "cmdBlockJoinTeam");

	g_BlockedTeamSelectMenus = TrieCreate();
	
	for (new i = 0; i < sizeof g_TeamSelectMenus; i++)
	{
		TrieSetCell(g_BlockedTeamSelectMenus, g_TeamSelectMenus[i], 1);
	}
}

public HNS_Mix_StateChanged(const HnsMixStates:newState)
{
	g_MixState = newState;
}

public messageShowMenu(const iMsgid, const iDest, const id)
{
	static menuCode[32];
	get_msg_arg_string(4, menuCode, charsmax(menuCode));
	
	if (blockTeamJoining() && TrieKeyExists(g_BlockedTeamSelectMenus, menuCode))
	{
		delayedPlayerTransfer(id, CS_TEAM_SPECTATOR);
		return PLUGIN_HANDLED;
	}
	
	return PLUGIN_CONTINUE;
}

public messageVGUIMenu(const iMsgid, const iDest, const id)
{
	new menuType = get_msg_arg_int(1);
	
	if (blockTeamJoining())
	{
		if (menuType == g_VGuiMenuTeamSelect)
		{
			delayedPlayerTransfer(id, CS_TEAM_SPECTATOR);
			return PLUGIN_HANDLED;
		}
		
		if (menuType == g_VGuiMenuClassSelectT || menuType == g_VGuiMenuClassSelectCT)
		{
			return PLUGIN_HANDLED;
		}
	}
	
	return PLUGIN_CONTINUE;
}

public cmdBlockJoinTeam(const id)
{
	if (!blockTeamJoining())
	{
		return PLUGIN_CONTINUE;
	}
	
	if (cs_get_user_team(id) == CS_TEAM_UNASSIGNED)
	{
		instantPlayerTransfer(id, CS_TEAM_SPECTATOR);
	}
		
	return PLUGIN_HANDLED;
}

delayedPlayerTransfer(const id, const CsTeams:iTeam)
{
	if (!is_user_connected(id))
	{
		return;
	}
	
	new taskId = 1513 + id;
	remove_task(taskId);
	
	new Float:time = ((id % 4) + 1) / 10.0;
	
	new task_params[2];
	task_params[0] = id;
	task_params[1] = _:iTeam;
	
	set_task(time, "taskTransferPlayer", taskId, task_params, sizeof(task_params));
}

public taskTransferPlayer(const params[])
{
	new id = params[0];
	new CsTeams:newTeam = CsTeams:params[1];
	
	instantPlayerTransfer(id, newTeam);
}

instantPlayerTransfer(const id, const CsTeams:newTeam)
{
	if (!is_user_connected(id))
	{
		return;
	}

	new CsTeams:currentTeam = cs_get_user_team(id);
	
	if (currentTeam == newTeam || newTeam == CS_TEAM_UNASSIGNED)
	{
		return;
	}

	if (is_user_alive(id))
	{
		user_silentkill(id, 1);
	}

	set_ent_data(id, g_ClassBasePlayer, g_MemberTeamChanged, false);
	set_msg_block(g_ShowMenuMessageId, BLOCK_SET);
	
	if (currentTeam == CS_TEAM_UNASSIGNED && newTeam == CS_TEAM_SPECTATOR)
	{
		set_ent_data(id, g_ClassBasePlayer, "m_iNumSpawns", 1);
		engclient_cmd(id, g_JoinTeamCmd, "5");
		engclient_cmd(id, g_JoinClassCmd, "5");
	}
	
	switch (newTeam)
	{
		case CS_TEAM_SPECTATOR:
		{
			cs_set_user_team(id, CS_TEAM_SPECTATOR);
		}
		case CS_TEAM_T:
		{
			engclient_cmd(id, g_JoinTeamCmd, "1");
			engclient_cmd(id, g_JoinClassCmd, "5");
		}
		case CS_TEAM_CT:
		{
			engclient_cmd(id, g_JoinTeamCmd, "2");
			engclient_cmd(id, g_JoinClassCmd, "5");
		}
	}

	set_msg_block(g_ShowMenuMessageId, BLOCK_NOT);
	set_ent_data(id, g_ClassBasePlayer, g_MemberTeamChanged, false);
}

public nativeTransferAllPlayers(const iPlugin, const iParams)
{
	if (iParams != 1)
	{
		return PLUGIN_CONTINUE;
	}

	new CsTeams:team = CsTeams:get_param(1);

	if (team == CS_TEAM_UNASSIGNED)
	{
		return PLUGIN_HANDLED;
	}

	new players[32], playersCount, playerId;
	get_players_ex(players, playersCount, g_GetPlayerFlags);
	
	for (new i; i < playersCount; i++)
	{
		playerId = players[i];
		delayedPlayerTransfer(playerId, team);
	}

	return PLUGIN_HANDLED;
}

public nativeTransferPlayer(const iPlugin, const iParams)
{
	if (iParams != 2)
	{
		return PLUGIN_CONTINUE;
	}

	new id = get_param(1);
	new CsTeams:newTeam = CsTeams:get_param(2);

	instantPlayerTransfer(id, newTeam);

	return PLUGIN_HANDLED;
}

public nativeSwapPlayers(const iPlugin, const iParams)
{
	if (iParams != 2)
	{
		return PLUGIN_CONTINUE;
	}

	new client1 = get_param(1);
	new client2 = get_param(2);

	new CsTeams:team1 = cs_get_user_team(client1);
	new CsTeams:team2 = cs_get_user_team(client2);

	instantPlayerTransfer(client1, team2);
	instantPlayerTransfer(client2, team1);

	return PLUGIN_HANDLED;
}