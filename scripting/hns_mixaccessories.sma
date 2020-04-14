#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <hns_mix>
#include <hns_teamjoin>
#include <newmenuextensions>

#pragma semicolon				1

#define PLUGIN_NAME				"HNS_MixAccessories"
#define PLUGIN_VERSION			"1.0.0"
#define PLUGIN_AUTHOR			"Reavap"

#define canExecuteReplace(%1) ((g_MixState == MixState_Ongoing && !is_user_alive(id)) || g_MixState == MixState_Paused)

new HnsMixStates:g_MixState;
new g_MixParticipationChangedForward;

new bool:g_OptOutOfMixParticipation[MAX_PLAYERS + 1];
new Float:g_ReplaceCooldown[MAX_PLAYERS + 1];

new Trie:g_DisconnectedReplaceCooldownLookup;

public plugin_init()
{
	register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
	register_cvar(PLUGIN_NAME, PLUGIN_VERSION, FCVAR_SERVER|FCVAR_SPONLY);
	
	register_clcmd("say /np", "cmdNoPlay");
	register_clcmd("say /noplay", "cmdNoPlay");
	register_clcmd("say /play", "cmdPlay");
	register_clcmd("say /replace", "cmdReplace");

	g_DisconnectedReplaceCooldownLookup = TrieCreate();

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

public client_authorized(id)
{
	static steamid[32];
	get_user_authid(id, steamid, charsmax(steamid));
	
	if (TrieKeyExists(g_DisconnectedReplaceCooldownLookup, steamid))
	{
		TrieGetCell(g_DisconnectedReplaceCooldownLookup, steamid, g_ReplaceCooldown[id]);
		TrieDeleteKey(g_DisconnectedReplaceCooldownLookup, steamid);
	}
	else
	{
		g_ReplaceCooldown[id] = 0.0;
	}
}

public client_disconnected(id)
{
	static steamid[32];
	get_user_authid(id, steamid, charsmax(steamid));
	
	if (g_ReplaceCooldown[id] > get_gametime())
	{
		TrieSetCell(g_DisconnectedReplaceCooldownLookup, steamid, g_ReplaceCooldown[id]);
	}
}

public HNS_Mix_StateChanged(const HnsMixStates:newState)
{
	g_MixState = newState;

	if (newState == MixState_Inactive)
	{
		for (new i = 1; i <= MAX_PLAYERS; i++)
		{
			g_ReplaceCooldown[i] = 0.0;
		}
	}
}

public cmdNoPlay(const id)
{
	if (g_MixState == MixState_Inactive)
	{
		client_print_color(id, print_team_red, "^3Command is only available during mix");
		return PLUGIN_CONTINUE;
	}
	
	changeOptOutStatus(id, true);
	return PLUGIN_HANDLED;
}

public cmdPlay(const id)
{
	if (g_MixState == MixState_Inactive)
	{
		client_print_color(id, print_team_red, "^3Command is only available during mix");
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
		client_print_color(id, print_team_grey, "^3Your mix participation state did not change");
		return;
	}

	g_OptOutOfMixParticipation[id] = optOut;

	if (!ExecuteForward(g_MixParticipationChangedForward, _, optOut))
	{
		log_amx("Could not execute mix participation changed forward");
	}

	new userName[MAX_NAME_LENGTH];
	get_user_name(id, userName, charsmax(userName));

	if (optOut)
	{
		client_print_color(0, print_team_grey, "^3%s ^1is not participating in the mix", userName);
	}
	else
	{
		client_print_color(0, print_team_grey, "^3%s ^1is participating in the mix", userName);
	}
}

public cmdReplace(const id)
{
	if (g_MixState == MixState_Inactive)
	{
		client_print_color(id, print_team_red, "^3Command is only available during mix");
		return PLUGIN_HANDLED;
	}
	
	new Float:gametime = get_gametime();
	
	if (cs_get_user_team(id) == CS_TEAM_SPECTATOR)
	{
		client_print_color(id, print_team_red, "^3You can not execute this command as a spectator");
	}
	else if (!canExecuteReplace(id))
	{
		client_print_color(id, print_team_red, "^3You must be dead or the game must be paused in order to replace");
	}
	else if (g_ReplaceCooldown[id] && g_ReplaceCooldown[id] > gametime)
	{
		client_print_color(id, print_team_red, "^3You currently have a cooldown on this command. Time left: ^1%s", getTimeAsText(g_ReplaceCooldown[id] - gametime));
	}
	else
	{
		displayReplaceMenu(id);
	}
	
	return PLUGIN_HANDLED;
}

displayReplaceMenu(const id)
{
	new players[MAX_PLAYERS], playerCount, playerId;
	new username[MAX_NAME_LENGTH + 16], userid[32];
	get_players_ex(players, playerCount, GetPlayers_ExcludeBots | GetPlayers_ExcludeHLTV | GetPlayers_MatchTeam, "SPECTATOR");
	
	if (!playerCount)
	{
		client_print_color(id, print_team_red, "^3There are currently no spectators to replace with");
		return;
	}
	
	new menu = menu_create("\rSelect a player to replace with:", "replaceMenuHandler");
	new disableCallBack = menu_makecallback("replaceMenuCallBack");

	new Float:gametime = get_gametime();
	
	for (new i; i < playerCount; i++)
	{
		playerId = players[i];
		
		get_user_name(playerId, username, charsmax(username));
		
		if (g_OptOutOfMixParticipation[playerId])
		{
			formatex(username, charsmax(username), "%s [NOT PLAYING]", username);
		}
		else if (g_ReplaceCooldown[playerId] > gametime)
		{
			formatex(username, charsmax(username), "%s [COOLDOWN]", username);
		}
		
		formatex(userid, charsmax(userid), "%d", get_user_userid(playerId));

		menu_additem(menu, username, userid, 0, disableCallBack);
	}
	
	menu_display(id, menu, 0, 20);
}

public replaceMenuHandler(const id, const menu, const item)
{
	if (item == MENU_EXIT || item == MENU_TIMEOUT || !canExecuteReplace(id))
	{
		menu_destroy(menu);
		return PLUGIN_HANDLED;
	}
	
	new selectedPlayerId = menu_selected_clientid(menu, item);
	menu_destroy(menu);

	if (selectedPlayerId && validReplaceBetweenPlayers(id, selectedPlayerId))
	{
		new userame[MAX_NAME_LENGTH];
		get_user_name(selectedPlayerId, userame, charsmax(userame));
		client_print_color(id, print_team_grey, "Sent replace request to ^3%s", userame);
		
		displayReplaceRequestMenu(selectedPlayerId, id);

		return PLUGIN_HANDLED;
	}

	client_print_color(id, print_team_red, "^3Can not replace with the selected player");
	displayReplaceMenu(id);
	return PLUGIN_HANDLED;
}

public replaceMenuCallBack(const id, const menu, const item)
{
	new selectedPlayer = menu_selected_clientid(menu, item);
	
	if (selectedPlayer && (g_OptOutOfMixParticipation[selectedPlayer] || g_ReplaceCooldown[selectedPlayer] > get_gametime()))
	{
		return ITEM_DISABLED;
	}
	
	return ITEM_ENABLED;
}

displayReplaceRequestMenu(const id, const replaceWithClient)
{
	new menuTitle[MAX_NAME_LENGTH + 16], userid[MAX_NAME_LENGTH];
	
	get_user_name(replaceWithClient, userid, charsmax(userid));
	formatex(menuTitle, charsmax(menuTitle), "\rReplace %s?", userid);
	
	formatex(userid, charsmax(userid), "%d", get_user_userid(replaceWithClient));
	
	new menu = menu_create(menuTitle, "replaceRequestMenuHandler");
	
	menu_additem(menu, "Accept", userid, 0);
	menu_additem(menu, "Reject", userid, 0);
	menu_setprop(menu, MPROP_EXIT, MEXIT_NEVER);
	menu_display(id, menu, 0, 10);
}

public replaceRequestMenuHandler(const id, const menu, const item)
{
	new selectedPlayerId = menu_selected_clientid(menu, 0);
	menu_destroy(menu);

	if (item == MENU_TIMEOUT || !canExecuteReplace(selectedPlayerId) || !validReplaceBetweenPlayers(selectedPlayerId, id))
	{
		return PLUGIN_HANDLED;
	}

	if (item == 1)
	{
		new username[MAX_NAME_LENGTH];
		get_user_name(id, username, charsmax(username));

		client_print_color(selectedPlayerId, print_team_red, "^3%s rejected your replace request", username);
		
		return PLUGIN_HANDLED;
	}
	
	new const Float:replaceCommandCooldown = 60.0 * 5;
	new Float:cooldown = get_gametime() + replaceCommandCooldown;
	
	g_ReplaceCooldown[id] = cooldown;
	g_ReplaceCooldown[selectedPlayerId] = cooldown;
	
	new CsTeams:newTeam = cs_get_user_team(selectedPlayerId);
	hns_swap_players(id, selectedPlayerId);

	new username1[MAX_NAME_LENGTH], username2[MAX_NAME_LENGTH];
	get_user_name(id, username1, charsmax(username1));
	get_user_name(selectedPlayerId, username2, charsmax(username2));
	
	client_print_color(0, getTeamColor(newTeam), "^3%s ^1replaced ^3%s", username1, username2);
	
	return PLUGIN_HANDLED;
}

bool:validReplaceBetweenPlayers(const client1, const client2)
{
	new CsTeams:team1 = cs_get_user_team(client1);
	new CsTeams:team2 = cs_get_user_team(client2);

	if (team1 == CS_TEAM_UNASSIGNED || team2 == CS_TEAM_UNASSIGNED)
	{
		return false;
	}

	return (team1 == CS_TEAM_CT || team1 == CS_TEAM_T) && team2 == CS_TEAM_SPECTATOR;
}