#define PLUGIN_NAME			"HNS_TeamJoin"
#define PLUGIN_VERSION		"1.0.0"
#define PLUGIN_AUTHOR		"Reavap"

#include <amxmodx>
#include <cstrike>
#include <fakemeta>
#include <hns_common>

#define blockTeamJoining() (g_currentState != PUBLIC_MODE)

new const g_sJoinTeamCmd[] = "jointeam";
new const g_sJoinClassCmd[] = "joinclass";

new const g_sTeamSelectMenus[][] =
{
	"#Team_Select",
	"#Team_Select_Spect",
	"#IG_Team_Select",
	"#IG_Team_Select_Spect"
};

const g_iVGuiMenuTeamSelect = 2;
const g_iVGuiMenuClassSelectT = 26;
const g_iVGuiMenuClassSelectCT = 27;

new Trie:g_tBlockedTeamSelectMenus;
new g_iShowMenuMessageId;
new ePluginState:g_currentState = PUBLIC_MODE;

public plugin_natives()
{
	register_library("hns_teamjoin");

	register_native("hns_transferAllPlayersToSpectator", "nativeTransferAllPlayersToSpectator", 0);
	register_native("hns_transferPlayer", "nativeTransferPlayer", 0);
}

public plugin_init()
{
	register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
	register_cvar(PLUGIN_NAME, PLUGIN_VERSION, FCVAR_SERVER|FCVAR_SPONLY);

	g_iShowMenuMessageId = get_user_msgid("ShowMenu");

	register_message(g_iShowMenuMessageId, "messageShowMenu");
	register_message(get_user_msgid("VGUIMenu"), "messageVGUIMenu");

	register_clcmd("chooseteam", "cmdBlockJoinTeam");
	register_clcmd(g_sJoinTeamCmd, "cmdBlockJoinTeam");
	register_clcmd(g_sJoinClassCmd, "cmdBlockJoinTeam");

	g_tBlockedTeamSelectMenus = TrieCreate();
	
	for (new i = 0; i < sizeof g_sTeamSelectMenus; i++)
	{
		TrieSetCell(g_tBlockedTeamSelectMenus, g_sTeamSelectMenus[i], 1);
	}
}

public HNS_StateChanged(const ePluginState:newState)
{
	g_currentState = newState;
}

public messageShowMenu(const iMsgid, const iDest, const id)
{
	static szMenuCode[32];
	get_msg_arg_string(4, szMenuCode, charsmax(szMenuCode));
	
	if (blockTeamJoining() && TrieKeyExists(g_tBlockedTeamSelectMenus, szMenuCode))
	{
		delayedPlayerTransfer(id, CS_TEAM_SPECTATOR);
		return PLUGIN_HANDLED;
	}
	
	return PLUGIN_CONTINUE;
}

public messageVGUIMenu(const iMsgid, const iDest, const id)
{
	new iMenuType = get_msg_arg_int(1);
	
	if (blockTeamJoining())
	{
		if (iMenuType == g_iVGuiMenuTeamSelect)
		{
			delayedPlayerTransfer(id, CS_TEAM_SPECTATOR);
			return PLUGIN_HANDLED;
		}
		
		if (iMenuType == g_iVGuiMenuClassSelectT || iMenuType == g_iVGuiMenuClassSelectCT)
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
	
	new Float:flTime = ((id % 4) + 1) / 10.0;
	
	new task_params[2];
	task_params[0] = id;
	task_params[1] = _:iTeam;
	
	set_task(flTime, "taskTransferPlayer", taskId, task_params, sizeof(task_params));
}

public taskTransferPlayer(const iParams[])
{
	new id = iParams[0];
	new CsTeams:iNewTeam = CsTeams:iParams[1];
	
	instantPlayerTransfer(id, iNewTeam);
}

instantPlayerTransfer(const id, const CsTeams:iNewTeam)
{
	if (!is_user_connected(id))
	{
		return;
	}

	new CsTeams:iCurrentTeam = cs_get_user_team(id);
	
	if (iCurrentTeam == iNewTeam || iNewTeam == CS_TEAM_UNASSIGNED)
	{
		return;
	}

	if (is_user_alive(id))
	{
		user_silentkill(id, 1);
	}
	
	set_ent_data(id, "CBasePlayer", "m_bTeamChanged", false);
	set_msg_block(g_iShowMenuMessageId, BLOCK_SET);
	
	if (iCurrentTeam == CS_TEAM_UNASSIGNED && iNewTeam == CS_TEAM_SPECTATOR)
	{
		engclient_cmd(id, g_sJoinTeamCmd, "5");
		engclient_cmd(id, g_sJoinClassCmd, "5");
	}
	
	switch (iNewTeam)
	{
		case CS_TEAM_SPECTATOR:
		{
			cs_set_user_team(id, CS_TEAM_SPECTATOR);
		}
		case CS_TEAM_T:
		{
			engclient_cmd(id, g_sJoinTeamCmd, "1");
			engclient_cmd(id, g_sJoinClassCmd, "5");
		}
		case CS_TEAM_CT:
		{
			engclient_cmd(id, g_sJoinTeamCmd, "2");
			engclient_cmd(id, g_sJoinClassCmd, "5");
		}
	}
	
	set_msg_block(g_iShowMenuMessageId, BLOCK_NOT);
}

public cmdTransferPlayerToTeam()
{
	if (read_argc() < 3)
	{
		return PLUGIN_HANDLED;
	}

	new id = read_argv_int(1);
	new CsTeams:iTeam = CsTeams:read_argv_int(2);

	instantPlayerTransfer(id, iTeam);

	return PLUGIN_HANDLED;
}

public nativeTransferAllPlayersToSpectator()
{
	new aPlayers[32], iPlayerCount, i, playerId;
	get_players(aPlayers, iPlayerCount, "ch");
	
	for (; i < iPlayerCount; i++)
	{
		playerId = aPlayers[i];
		
		delayedPlayerTransfer(playerId, CS_TEAM_SPECTATOR);
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
	new CsTeams:iNewTeam = CsTeams:get_param(2);

	instantPlayerTransfer(id, iNewTeam);

	return PLUGIN_HANDLED;
}