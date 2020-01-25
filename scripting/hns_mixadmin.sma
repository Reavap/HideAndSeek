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

new const GetPlayersFlags:g_iGetPlayerFlags = GetPlayers_ExcludeBots | GetPlayers_ExcludeHLTV;

new bool:g_bGrantedMixAdmin[MAX_PLAYERS + 1];
new Trie:g_tDisconnectedAdmins;

new eHnsMixState:g_eMixState;

// Vote Mix Admin
new g_hNominateMixAdminMenu;
new g_iMixAdminVoteParticipants;
new g_iMixAdminVotesReceived;
new Array:g_aVotedMixAdmins;

public plugin_init()
{
	register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
	register_cvar(PLUGIN_NAME, PLUGIN_VERSION, FCVAR_SERVER|FCVAR_SPONLY);

	register_clcmd("say /nma", "cmdNominateMixAdmin");
	register_clcmd("say /gma", "cmdGiveMixAdmin");

	g_tDisconnectedAdmins = TrieCreate();
	g_aVotedMixAdmins = ArrayCreate(2);
}

public client_authorized(id)
{
	if (is_user_admin(id))
	{
		set_user_flags(id, MIX_ADMIN_FLAG);
		return;
	}
	
	static szSteamId[32];
	get_user_authid(id, szSteamId, charsmax(szSteamId));
	new Float:flGameTime;

	if (!TrieGetCell(g_tDisconnectedAdmins, szSteamId, flGameTime))
	{
		return;
	}

	TrieDeleteKey(g_tDisconnectedAdmins, szSteamId);
	new const Float:flRevokeAdminAfter = 60.0 * 5;
	
	if (flRevokeAdminAfter >= get_gametime() - flGameTime)
	{
		giveMixAdminToPeasant(id);
	}
}

public client_disconnected(id)
{
	if (g_bGrantedMixAdmin[id])
	{
		g_bGrantedMixAdmin[id] = false;

		new szSteamId[32];
		get_user_authid(id, szSteamId, charsmax(szSteamId));

		TrieSetCell(g_tDisconnectedAdmins, szSteamId, get_gametime());

		if (g_eMixState != MIXSTATE_INACTIVE)
		{
			new szUserName[MAX_NAME_LENGTH];
			get_user_name(id, szUserName, charsmax(szUserName));
			client_print_color(id, print_team_red, "* ^3Mix admin %s disconnected", szUserName);
		}
	}
}

public HNS_Mix_StateChanged(const eHnsMixState:eNewState)
{
	g_eMixState = eNewState;
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
	new hMenu = menu_create("\rGrant/Revoke mix admin:", "mixAdminRightsMenuHandler");

	new aPlayers[MAX_PLAYERS], iPlayerCount;
	new szUserName[MAX_NAME_LENGTH + 13], szUserId[32];
	get_players_ex(aPlayers, iPlayerCount, g_iGetPlayerFlags);
	
	for (new i; i < iPlayerCount; i++)
	{
		new playerId = aPlayers[i];
		
		if (playerIsOrdinaryAdmin(playerId))
		{
			continue;
		}
		
		get_user_name(playerId, szUserName, charsmax(szUserName));
		formatex(szUserId, charsmax(szUserId), "%d", get_user_userid(playerId));

		if (g_bGrantedMixAdmin[playerId])
		{
			formatex(szUserName, charsmax(szUserName), "%s [TEMP ADMIN]", szUserName);
		}
		
		menu_additem(hMenu, szUserName, szUserId, 0);
	}

	if (!menu_items(hMenu))
	{
		menu_destroy(hMenu);
		return;
	}
	
	menu_display(id, hMenu, 0, 20);
}

public mixAdminRightsMenuHandler(const id, const hMenu, const item)
{
	if (item == MENU_EXIT || item == MENU_TIMEOUT)
	{
		menu_destroy(hMenu);
		return PLUGIN_HANDLED;
	}
	
	new selectedPlayerId = menu_selected_clientid(hMenu, item);
	menu_destroy(hMenu);
	
	if (!selectedPlayerId)
	{
		client_print_color(id, print_team_red, "* ^3Failed to perform the action on the selected player");
		return PLUGIN_HANDLED;
	}

	new szAdminName[MAX_NAME_LENGTH], szPlayerName[MAX_NAME_LENGTH];
	get_user_name(id, szAdminName, charsmax(szAdminName));
	get_user_name(selectedPlayerId, szPlayerName, charsmax(szPlayerName));

	if (g_bGrantedMixAdmin[selectedPlayerId])
	{
		removeMixAdminForPeasant(selectedPlayerId);
		client_print_color(0, print_team_grey, "* ^3%s ^1revoked mix administration rights for ^3%s", szAdminName, szPlayerName);
	}
	else
	{
		giveMixAdminToPeasant(selectedPlayerId);
		client_print_color(0, print_team_grey, "* ^3%s ^1granted ^3%s ^1mix administration rights", szAdminName, szPlayerName);
	}
	
	return PLUGIN_HANDLED;
}

public cmdNominateMixAdmin(const id)
{
	new aPlayers[MAX_PLAYERS], iRetrievedCount;
	get_players_ex(aPlayers, iRetrievedCount, g_iGetPlayerFlags);

	if (temporaryMixAdminIsAssigned())
	{
		client_print_color(id, print_team_red, "* ^3There is already a mix admin in place");
		return PLUGIN_HANDLED;
	}

	if (get_playersnum_ex(g_iGetPlayerFlags) < 6)
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
	g_hNominateMixAdminMenu = menu_create("\rWho should administrate the mix?", "voteMixAdminMenuHandler");
	
	new aPlayers[MAX_PLAYERS], iPlayerCount;
	new szUserName[MAX_NAME_LENGTH], szUserId[32];
	get_players_ex(aPlayers, iPlayerCount, g_iGetPlayerFlags);

	for (new i; i < iPlayerCount; i++)
	{
		new playerId = aPlayers[i];
		
		if (playerCanAdministrateMix(playerId))
		{
			continue;
		}
		
		get_user_name(playerId, szUserName, charsmax(szUserName));
		formatex(szUserId, charsmax(szUserId), "%d", get_user_userid(playerId));

		menu_additem(g_hNominateMixAdminMenu, szUserName, szUserId, 0);
	}

	if (!menu_items(g_hNominateMixAdminMenu))
	{
		menu_destroy(g_hNominateMixAdminMenu);
		return;
	}

	g_iMixAdminVoteParticipants = 0;
	g_iMixAdminVotesReceived = 0;
	ArrayClear(g_aVotedMixAdmins);

	get_players_ex(aPlayers, iPlayerCount, g_iGetPlayerFlags);
	
	for (new i; i < iPlayerCount; i++)
	{
		g_iMixAdminVoteParticipants++;
		menu_display(aPlayers[i], g_hNominateMixAdminMenu, 0, 10);
	}

	set_task(10.5, "taskEndMixAdminVote", TASK_VOTE_MIX_ADMIN);
}

public voteMixAdminMenuHandler(const id, const hMenu, const item)
{
	if (!task_exists(TASK_VOTE_MIX_ADMIN))
	{
		return PLUGIN_HANDLED;
	}

	if (item != MENU_TIMEOUT && item != MENU_EXIT)
	{
		new selectedUserId = menu_selected_int(hMenu, item);
		insertVoteResponse(selectedUserId);
	}

	if (++g_iMixAdminVotesReceived >= g_iMixAdminVoteParticipants && remove_task(TASK_VOTE_MIX_ADMIN))
	{
		taskEndMixAdminVote();
	}

	return PLUGIN_HANDLED;
}

insertVoteResponse(const selectedUserId)
{
	new iArrayIndex = ArrayFindValue(g_aVotedMixAdmins, selectedUserId);
	new content[2];

	if (iArrayIndex == -1)
	{
		iArrayIndex = ArraySize(g_aVotedMixAdmins);
		content[0] = selectedUserId;
		content[1] = 1;

		ArrayPushArray(g_aVotedMixAdmins, content);
	}
	else
	{
		ArrayGetArray(g_aVotedMixAdmins, iArrayIndex, content);
		content[1]++;
		ArraySetArray(g_aVotedMixAdmins, iArrayIndex, content);
	}
}

public taskEndMixAdminVote()
{
	menu_destroy(g_hNominateMixAdminMenu);

	new iWinner = getMixAdminVoteWinner();

	if (!iWinner)
	{
		client_print_color(0, print_team_red, "* ^3Failed to assign a mix admin from the vote result");
		return;
	}

	new szName[32];
	get_user_name(iWinner, szName, charsmax(szName));
	client_print_color(0, print_team_grey, "* ^3%s ^1won the vote and is now assigned mix admin rights", szName);

	giveMixAdminToPeasant(iWinner);
}

getMixAdminVoteWinner()
{
	new iVoteEntries = ArraySize(g_aVotedMixAdmins);
	ArraySort(g_aVotedMixAdmins, "compareVoteCount");

	new iWinner;

	for (new i = 0; i < iVoteEntries; i++)
	{
		if ((iWinner = find_player_ex(FindPlayer_MatchUserId, ArrayGetCell(g_aVotedMixAdmins, i, 0))))
		{
			break;
		}
	}

	return iWinner;
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
	g_bGrantedMixAdmin[id] = true;
	set_user_flags(id, MIX_ADMIN_FLAG);
}

removeMixAdminForPeasant(const id)
{
	g_bGrantedMixAdmin[id] = false;
	remove_user_flags(id, MIX_ADMIN_FLAG);
}

bool:temporaryMixAdminIsAssigned()
{
	for (new i = 1; i <= MAX_PLAYERS; i++)
	{
		if (g_bGrantedMixAdmin[i])
		{
			return true;
		}
	}

	return false;
}