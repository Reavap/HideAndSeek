#define PLUGIN_NAME			"HNS_MixAdmin"
#define PLUGIN_VERSION		"1.0.0"
#define PLUGIN_AUTHOR		"Reavap"

#include <amxmodx>
#include <amxmisc>
#include <hns_mix>
#include <newmenuextensions>

#pragma semicolon	1

#define MIX_ADMIN_FLAG			ADMIN_LEVEL_A
#define TASK_VOTE_MIX_ADMIN		6000

#define playerCanAdministrateMix(%1) ((get_user_flags(%1) & MIX_ADMIN_FLAG) > 0)
#define playerIsOrdinaryAdmin(%1) (!(get_user_flags(%1) & ADMIN_USER))
#define playerIsTemporaryAdmin(%1) (playerCanAdministrateMix(%1) && !playerIsOrdinaryAdmin(%1))

new const GetPlayersFlags:g_GetPlayerFlags = GetPlayers_ExcludeBots | GetPlayers_ExcludeHLTV;

new Trie:g_DisconnectedTempAdmins;
new HnsMixStates:g_MixState;

// Vote Mix Admin
new g_VoteMixAdminMenuHandler;
new g_MixAdminVoteParticipants;
new g_MixAdminVotesReceived;
new Array:g_MixAdminVoteStorage;

public plugin_init()
{
	register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
	register_cvar(PLUGIN_NAME, PLUGIN_VERSION, FCVAR_SERVER|FCVAR_SPONLY);

	register_clcmd("say /nma", "cmdNominateMixAdmin");
	register_clcmd("say /gma", "cmdGiveMixAdmin");

	g_DisconnectedTempAdmins = TrieCreate();
	g_MixAdminVoteStorage = ArrayCreate(2);
}

public client_authorized(id)
{
	if (is_user_admin(id))
	{
		set_user_flags(id, MIX_ADMIN_FLAG);
		return;
	}
	
	static steamid[32];
	get_user_authid(id, steamid, charsmax(steamid));
	new Float:gametime;

	if (!TrieGetCell(g_DisconnectedTempAdmins, steamid, gametime))
	{
		return;
	}

	TrieDeleteKey(g_DisconnectedTempAdmins, steamid);
	new const Float:revokeAdminAfter = 60.0 * 5;
	
	if (revokeAdminAfter >= get_gametime() - gametime)
	{
		giveMixAdminToPeasant(id);
	}
}

public client_disconnected(id)
{
	if (playerIsTemporaryAdmin(id))
	{
		new steamid[32];
		get_user_authid(id, steamid, charsmax(steamid));

		TrieSetCell(g_DisconnectedTempAdmins, steamid, get_gametime());

		if (g_MixState != MixState_Inactive)
		{
			new username[MAX_NAME_LENGTH];
			get_user_name(id, username, charsmax(username));
			client_print_color(0, print_team_red, "* ^3Mix admin %s disconnected", username);
		}
	}
}

public HNS_Mix_StateChanged(const HnsMixStates:newState)
{
	g_MixState = newState;
}

public cmdGiveMixAdmin(const id)
{
	if (playerIsOrdinaryAdmin(id))
	{
		displayGiveMixAdminRightsMenu(id);
	}

	return PLUGIN_HANDLED;
}

displayGiveMixAdminRightsMenu(const id)
{
	new menu = menu_create("\rGrant/Revoke mix admin:", "mixAdminRightsMenuHandler");

	new players[MAX_PLAYERS], playercount, playerId;
	new username[MAX_NAME_LENGTH + 16], userid[32];
	get_players_ex(players, playercount, g_GetPlayerFlags);
	
	for (new i; i < playercount; i++)
	{
		playerId = players[i];
		
		if (playerIsOrdinaryAdmin(playerId))
		{
			continue;
		}
		
		get_user_name(playerId, username, charsmax(username));
		formatex(userid, charsmax(userid), "%d", get_user_userid(playerId));

		if (playerIsTemporaryAdmin(playerId))
		{
			formatex(username, charsmax(username), "%s [TEMP ADMIN]", username);
		}
		
		menu_additem(menu, username, userid, 0);
	}

	if (!menu_items(menu))
	{
		menu_destroy(menu);
		return;
	}
	
	menu_display(id, menu, 0, 20);
}

public mixAdminRightsMenuHandler(const id, const menu, const item)
{
	if (item == MENU_EXIT || item == MENU_TIMEOUT)
	{
		menu_destroy(menu);
		return PLUGIN_HANDLED;
	}
	
	new selectedPlayerId = menu_selected_clientid(menu, item);
	menu_destroy(menu);
	
	if (!selectedPlayerId)
	{
		client_print_color(id, print_team_red, "* ^3Failed to perform the action on the selected player");
		return PLUGIN_HANDLED;
	}

	new adminUsername[MAX_NAME_LENGTH], playerUsername[MAX_NAME_LENGTH];
	get_user_name(id, adminUsername, charsmax(adminUsername));
	get_user_name(selectedPlayerId, playerUsername, charsmax(playerUsername));

	if (playerCanAdministrateMix(selectedPlayerId))
	{
		removeMixAdminForPeasant(selectedPlayerId);
		client_print_color(0, print_team_grey, "* ^3%s ^1revoked mix administration rights for ^3%s", adminUsername, playerUsername);
	}
	else
	{
		giveMixAdminToPeasant(selectedPlayerId);
		client_print_color(0, print_team_grey, "* ^3%s ^1granted ^3%s ^1mix administration rights", adminUsername, playerUsername);
	}
	
	return PLUGIN_HANDLED;
}

public cmdNominateMixAdmin(const id)
{
	if (temporaryMixAdminIsAssigned())
	{
		client_print_color(id, print_team_red, "* ^3There is already a mix admin in place");
		return PLUGIN_HANDLED;
	}

	if (get_playersnum_ex(g_GetPlayerFlags) < 6)
	{
		client_print_color(id, print_team_red, "* ^3Not enough players on the server to vote");
		return PLUGIN_HANDLED;
	}

	if (task_exists(TASK_VOTE_MIX_ADMIN))
	{
		client_print_color(id, print_team_red, "* ^3There is already a vote in progress");
		return PLUGIN_HANDLED;
	}

	displayVoteMixAdminMenu();

	return PLUGIN_HANDLED;
}

displayVoteMixAdminMenu()
{
	g_VoteMixAdminMenuHandler = menu_create("\rWho should administrate the mix?", "voteMixAdminMenuHandler");
	
	new players[MAX_PLAYERS], playercount, playerId;
	new username[MAX_NAME_LENGTH], userid[32];
	get_players_ex(players, playercount, g_GetPlayerFlags);

	for (new i; i < playercount; i++)
	{
		playerId = players[i];
		
		if (playerCanAdministrateMix(playerId))
		{
			continue;
		}
		
		get_user_name(playerId, username, charsmax(username));
		formatex(userid, charsmax(userid), "%d", get_user_userid(playerId));

		menu_additem(g_VoteMixAdminMenuHandler, username, userid, 0);
	}

	if (!menu_items(g_VoteMixAdminMenuHandler))
	{
		menu_destroy(g_VoteMixAdminMenuHandler);
		return;
	}

	g_MixAdminVoteParticipants = 0;
	g_MixAdminVotesReceived = 0;
	ArrayClear(g_MixAdminVoteStorage);

	get_players_ex(players, playercount, g_GetPlayerFlags);
	
	for (new i; i < playercount; i++)
	{
		g_MixAdminVoteParticipants++;
		menu_display(players[i], g_VoteMixAdminMenuHandler, 0, 10);
	}

	set_task(10.5, "taskEndMixAdminVote", TASK_VOTE_MIX_ADMIN);
}

public voteMixAdminMenuHandler(const id, const menu, const item)
{
	if (!task_exists(TASK_VOTE_MIX_ADMIN))
	{
		return PLUGIN_HANDLED;
	}

	if (item != MENU_TIMEOUT && item != MENU_EXIT)
	{
		new selectedUserId = menu_selected_int(menu, item);
		insertVoteResponse(selectedUserId);
	}

	if (++g_MixAdminVotesReceived >= g_MixAdminVoteParticipants && remove_task(TASK_VOTE_MIX_ADMIN))
	{
		taskEndMixAdminVote();
	}

	return PLUGIN_HANDLED;
}

insertVoteResponse(const selectedUserId)
{
	new arrayIndex = ArrayFindValue(g_MixAdminVoteStorage, selectedUserId);
	new content[2];

	if (arrayIndex == -1)
	{
		arrayIndex = ArraySize(g_MixAdminVoteStorage);
		content[0] = selectedUserId;
		content[1] = 1;

		ArrayPushArray(g_MixAdminVoteStorage, content);
	}
	else
	{
		ArrayGetArray(g_MixAdminVoteStorage, arrayIndex, content);
		content[1]++;
		ArraySetArray(g_MixAdminVoteStorage, arrayIndex, content);
	}
}

public taskEndMixAdminVote()
{
	menu_destroy(g_VoteMixAdminMenuHandler);

	new winner = getMixAdminVoteWinner();

	if (!winner)
	{
		client_print_color(0, print_team_red, "* ^3Failed to assign a mix admin from the vote result");
		return;
	}

	new username[MAX_NAME_LENGTH];
	get_user_name(winner, username, charsmax(username));
	client_print_color(0, print_team_grey, "* ^3%s ^1won the vote and is now assigned mix admin rights", username);

	giveMixAdminToPeasant(winner);
}

getMixAdminVoteWinner()
{
	new voteEntries = ArraySize(g_MixAdminVoteStorage);
	ArraySort(g_MixAdminVoteStorage, "compareVoteCount");

	new winner;

	for (new i = 0; i < voteEntries; i++)
	{
		if ((winner = find_player_ex(FindPlayer_MatchUserId, ArrayGetCell(g_MixAdminVoteStorage, i, 0))))
		{
			break;
		}
	}

	return winner;
}

public compareVoteCount(Array:array, item1, item2)
{
	new votesItem1 = ArrayGetCell(array, item1, 1);
	new votesItem2 = ArrayGetCell(array, item2, 1);

	if (votesItem1 > votesItem2)
	{
		return -1;
	}

	if (votesItem1 < votesItem2)
	{
		return 1;
	}

	// Randomize order when vote count is equal
	return random_num(0, 1) ? -1 : 1;
}

giveMixAdminToPeasant(const id)
{
	set_user_flags(id, MIX_ADMIN_FLAG);
}

removeMixAdminForPeasant(const id)
{
	remove_user_flags(id, MIX_ADMIN_FLAG);
}

bool:temporaryMixAdminIsAssigned()
{
	for (new i = 1; i <= MAX_PLAYERS; i++)
	{
		if (playerIsTemporaryAdmin(i))
		{
			return true;
		}
	}

	return false;
}