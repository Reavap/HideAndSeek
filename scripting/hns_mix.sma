#include <amxmodx>
#include <cstrike>
#include <fakemeta>
#include <chatcolor>
#include <hns_common>
#include <dhudmessage>

#pragma semicolon			1

#define PLUGIN_NAME			"HNS_Mix"
#define PLUGIN_VERSION			"1.0.0"
#define PLUGIN_AUTHOR			"Reavap"

#define PLUGIN_ACCESS_LEVEL		ADMIN_LEVEL_A

#define MAX_PLAYERS			32

#define TASK_COUNTDOWN			4000
#define TASK_TRANSFER_PLAYER		5000

#define playerCanAdministrateMix(%1) ((get_user_flags(%1) & PLUGIN_ACCESS_LEVEL) > 0 || g_bTemporaryAdmin[%1])

#define canTransferPlayers(%1) (g_eMixState == MIX_PAUSED && playerCanAdministrateMix(%1))
#define isValidTeamTransfer(%1,%2) ((%1 == CS_TEAM_CT || %1 == CS_TEAM_T) != (%2 == CS_TEAM_CT || %2 == CS_TEAM_T) && %1 != CS_TEAM_UNASSIGNED)

#define isCaptain(%1) (%1 == g_iCaptainT || %1 == g_iCaptainCT)
#define isPlayersTurnToPick(%1) ((%1 == g_iCaptainT && g_eMixState == SELECT_PLAYER_T) || (%1 == g_iCaptainCT && g_eMixState == SELECT_PLAYER_CT))

#define canExecuteReplace(%1) ((g_eMixState == MIX_ONGOING && !is_user_alive(id)) || g_eMixState == MIX_PAUSED)
#define mixIsActive() (g_eMixState != MIX_INACTIVE)

// Cvars
new mp_roundtime;

// Mix-Forwards (Events)
new g_iMixStartedForward;
new g_iMixEndedForward;
new g_iMixRoundCompletedForward;

// HNS States
new bool:g_bStateChanged;

new Trie:g_tReplaceCooldowns;
new Trie:g_tBlockedTeamSelectMenus;

new Float:g_flRoundTime;
new Float:g_flRoundStart;

new g_iCurrentRound;
new g_iRoundsToPlay;

new Float:g_flSurvivedTimeTeamT;
new Float:g_flSurvivedTimeTeamCT;

new bool:g_bTemporaryAdmin[MAX_PLAYERS + 1];
new bool:g_bNoPlay[MAX_PLAYERS + 1];
new Float:g_flReplaceCooldown[MAX_PLAYERS + 1];

// Mix initialization
enum eHnsMixState:g_iMixStates (+= 1)
{
	MIX_INACTIVE = 0,
	SELECT_ROUNDS,
	SELECT_ROUNDTIME,
	SELECT_PLAYER_COUNT,
	SELECT_CAPTAIN_T,
	SELECT_CAPTAIN_CT,
	DUEL_FIRST_PICK,
	SELECT_PLAYER_T,
	SELECT_PLAYER_CT,
	MIX_PAUSED,
	MIX_ONGOING
};
new eHnsMixState:g_eMixState;
new g_iMixStartedBy;
new g_iPlayerCount;
new g_iCaptainT;
new g_iCaptainCT;
new g_iStartPicker;

// Constants
new const g_sTeamNames[][] =
{
	"Unassigned",
	"T",
	"CT",
	"Spectator"
};

const g_iVGuiMenuTeamSelect = 2;
const g_iVGuiMenuClassSelectT = 26;
const g_iVGuiMenuClassSelectCT = 27;

const EXTRAOFFSET_PLAYER = 5;
const m_bHasChangeTeamThisRound = 125;
const m_iNumRespawns = 365;

new const g_sTeamSelectMenus[][] =
{
	"#Team_Select",
	"#Team_Select_Spect",
	"#IG_Team_Select",
	"#IG_Team_Select_Spect"
};

new const g_sPluginPrefix[] = "^1[^4HNS^1]";
new const g_sNotPlayingMenuItem[] = " [NOT PLAYING]";

new const g_sJoinTeamCmd[] = "jointeam";
new const g_sJoinClassCmd[] = "joinclass";

new const g_bEarlyExitSetting = false;

public plugin_init()
{
	register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
	register_cvar(PLUGIN_NAME, PLUGIN_VERSION, FCVAR_SERVER|FCVAR_SPONLY);
	
	mp_roundtime = get_cvar_pointer("mp_roundtime");
	
	register_logevent("eventRoundStart", 2, "1=Round_Start");
	register_logevent("eventHostage", 6, "3=Hostages_Not_Rescued");
	register_logevent("eventTwin", 6, "3=Terrorists_Win");
	register_logevent("eventCTwin", 6, "3=CTs_Win");
	
	register_message(get_user_msgid("ShowMenu"), "message_ShowMenu");
	register_message(get_user_msgid("VGUIMenu"), "message_VGUIMenu");
	register_clcmd("chooseteam", "cmdBlockJoinTeam");
	register_clcmd(g_sJoinTeamCmd, "cmdBlockJoinTeam");
	register_clcmd(g_sJoinClassCmd, "cmdBlockJoinTeam");
	
	register_clcmd("hnsmenu","cmdHnsMenu");
	register_clcmd("say /hnsmenu","cmdHnsMenu");
	
	register_clcmd("say /t", "cmdTransferToT");
	register_clcmd("say /ct", "cmdTransferToCT");
	register_clcmd("say /spec", "cmdTransferToSpec");
	register_clcmd("say /pick", "cmdPickPlayer");
	
	register_clcmd("say /np", "cmdNoPlay");
	register_clcmd("say /noplay", "cmdNoPlay");
	register_clcmd("say /play", "cmdPlay");
	register_clcmd("say /replace", "cmdReplace");
	
	register_clcmd("say /s", "cmdShowScore");
	register_clcmd("say /score", "cmdShowScore");
	register_clcmd("say /time", "cmdShowScore");
	
	register_clcmd("say /st", "cmdStartingTeam");
	register_clcmd("say /startingteam", "cmdStartingTeam");
	
	g_tReplaceCooldowns = TrieCreate();
	g_tBlockedTeamSelectMenus = TrieCreate();
	
	for (new i = 0; i < sizeof g_sTeamSelectMenus; i++)
	{
		TrieSetCell(g_tBlockedTeamSelectMenus, g_sTeamSelectMenus[i], 1);
	}
	
	initializeEventForwards();
}

initializeEventForwards()
{
	new pluginId = find_plugin_byfile("HNS_MixStats.amxx");
	
	if (pluginId >= 0)
	{
		g_iMixStartedForward = CreateOneForward(pluginId, "HNS_Mix_Started", FP_CELL);
		g_iMixEndedForward = CreateOneForward(pluginId, "HNS_Mix_Ended");
		g_iMixRoundCompletedForward = CreateOneForward(pluginId, "HNS_Mix_RoundCompleted", FP_CELL);
		
		if (g_iMixStartedForward < 0)
		{
			g_iMixStartedForward = 0;
			log_amx("Mix started forward could not be created.");
		}
		
		if (g_iMixEndedForward < 0)
		{
			g_iMixEndedForward = 0;
			log_amx("Mix ended forward could not be created.");
		}
		
		if (g_iMixRoundCompletedForward < 0)
		{
			g_iMixRoundCompletedForward = 0;
			log_amx("Mix round completed forward could not be created.");
		}
	}
}

public plugin_end()
{
	DestroyForward(g_iMixStartedForward);
	g_iMixStartedForward = 0;
	
	DestroyForward(g_iMixEndedForward);
	g_iMixEndedForward = 0;
	
	DestroyForward(g_iMixRoundCompletedForward);
	g_iMixRoundCompletedForward = 0;
}

public client_authorized(id)
{
	g_bTemporaryAdmin[id] = false;
	g_bNoPlay[id] = false;
	
	static szSteamId[32];
	get_user_authid(id, szSteamId, charsmax(szSteamId));
	
	if (TrieKeyExists(g_tReplaceCooldowns, szSteamId))
	{
		TrieGetCell(g_tReplaceCooldowns, szSteamId, g_flReplaceCooldown[id]);
		TrieDeleteKey(g_tReplaceCooldowns, szSteamId);
	}
	else
	{
		g_flReplaceCooldown[id] = 0.0;
	}
}

public client_disconnect(id)
{
	if (id == g_iCaptainT)
	{
		client_print_color(0, RED, "%s Captain for team ^3T ^1disconnected!", g_sPluginPrefix);
		g_iCaptainT = 0;
	}
	
	if (id == g_iCaptainCT)
	{
		client_print_color(0, BLUE, "%s Captain for team ^3CT ^1disconnected!", g_sPluginPrefix);
		g_iCaptainCT = 0;
	}
	
	if (id == g_iMixStartedBy)
	{
		resetMixInitialization();
		
		changeState(PUBLIC_MODE);
		serverRestart();
	}
	
	static szSteamId[32];
	get_user_authid(id, szSteamId, charsmax(szSteamId));
	
	new Float:flGameTime = get_gametime();
	
	if (g_flReplaceCooldown[id] > flGameTime)
	{
		TrieSetCell(g_tReplaceCooldowns, szSteamId, g_flReplaceCooldown[id]);
	}
}

// ===============================================
// Round start/end events
// ===============================================

public HNS_NewRound()
{
	remove_task(TASK_COUNTDOWN);
	g_bStateChanged = false;
	
	g_flRoundStart = 0.0;
	g_flRoundTime = floatclamp(get_pcvar_float(mp_roundtime), 1.0, 9.0) * 60.0;
}

public eventRoundStart()
{
	g_flRoundStart = get_gametime();
	
	new iRoundsLeft = g_iRoundsToPlay - g_iCurrentRound + 1;
	new Float:flTimeDif;
	
	if (g_iCurrentRound % 2)
	{
		flTimeDif = (g_flSurvivedTimeTeamCT + maxSurvivalTimeRemainingRounds(CS_TEAM_CT, iRoundsLeft)) - g_flSurvivedTimeTeamT;
	}
	else
	{
		flTimeDif = (g_flSurvivedTimeTeamT + maxSurvivalTimeRemainingRounds(CS_TEAM_T, iRoundsLeft)) - g_flSurvivedTimeTeamCT;
	}
	
	if (!g_bStateChanged && g_eMixState == MIX_ONGOING && flTimeDif <= g_flRoundTime && g_bEarlyExitSetting)
	{
		new iSeconds = 10;
		new Float:flCountdownStart = flTimeDif + 0.1;
		
		if (flCountdownStart < 0)
		{
			flCountdownStart = 0.0;
			iSeconds = 0;
		}
		else if (flCountdownStart >= iSeconds)
		{
			flCountdownStart -= iSeconds;
		}
		else if (flCountdownStart < iSeconds)
		{
			iSeconds = floatround(floatclamp(flCountdownStart, 0.0, 10.0), floatround_floor);
			flCountdownStart -= iSeconds;
		}
		
		new task_params[1];
		task_params[0] = iSeconds;
		
		set_task(flCountdownStart, "taskCountDown", TASK_COUNTDOWN, task_params, sizeof(task_params));
	}
}

public eventHostage()
{
	if (g_eMixState == MIX_ONGOING)
	{
		roundEnd(CS_TEAM_T);
	}
}

public eventTwin()
{
	roundEnd(CS_TEAM_T);
}

public eventCTwin()
{
	roundEnd(CS_TEAM_CT);
}

public roundEnd(const CsTeams:iWinningTeam)
{
	remove_task(TASK_COUNTDOWN);
	
	if (g_bStateChanged)
	{
		return;
	}
	
	if (g_eMixState == MIX_ONGOING)
	{
		new Float:flSurvivedTime;
		
		if (iWinningTeam == CS_TEAM_CT)
		{
			flSurvivedTime = g_flRoundStart ? (get_gametime() - g_flRoundStart) : 0.0;
		}
		else
		{
			flSurvivedTime = g_flRoundTime;
		}
		
		if (g_iCurrentRound % 2 == 1)
		{
			g_flSurvivedTimeTeamT += flSurvivedTime;
		}
		else
		{
			g_flSurvivedTimeTeamCT += flSurvivedTime;
		}
		
		new iRoundsLeft = g_iRoundsToPlay - g_iCurrentRound;
		new bool:bEarlyExit = g_flSurvivedTimeTeamT > g_flSurvivedTimeTeamCT + maxSurvivalTimeRemainingRounds(CS_TEAM_CT, iRoundsLeft) ||
					g_flSurvivedTimeTeamCT > g_flSurvivedTimeTeamT + maxSurvivalTimeRemainingRounds(CS_TEAM_T, iRoundsLeft);
		
		g_flRoundStart = 0.0;
		printScore(0);
		
		if (g_iCurrentRound >= g_iRoundsToPlay)
		{
			mixCompleted();
		}
		else
		{
			if (bEarlyExit && g_bEarlyExitSetting)
			{
				mixCompleted();
			}
			else
			{
				g_iCurrentRound++;
				hns_switchTeams();
				serverRestartRound();
			}
		}
		
		new iForwardReturn;
		if (!ExecuteForward(g_iMixRoundCompletedForward, iForwardReturn, iWinningTeam))
		{
			log_amx("Could not execute round completed forward");
		}
	}
	else if (g_eMixState == DUEL_FIRST_PICK)
	{
		if (iWinningTeam == CS_TEAM_CT)
		{
			g_iStartPicker = g_iCaptainCT;
		}
		else
		{
			g_iStartPicker = g_iCaptainT;
		}
		
		g_eMixState = SELECT_PLAYER_T;
		changeState(PAUSED_MODE);
		getNextInitalizationMenu(g_iMixStartedBy);
	}
}

Float:maxSurvivalTimeRemainingRounds(const CsTeams:iTeam, const iRoundsLeft)
{
	new iRounds = iRoundsLeft / 2;
	
	if (iTeam == CS_TEAM_CT && (iRoundsLeft % 2))
	{
		iRounds++;
	}
	
	return g_flRoundTime * iRounds;
}

mixCompleted()
{
	changeState(PUBLIC_MODE);
	g_eMixState = MIX_INACTIVE;
	serverRestart();
	
	if (g_flSurvivedTimeTeamT == g_flSurvivedTimeTeamCT)
	{
		client_print_color(0, GREY, "%s Mix finished with a draw!", g_sPluginPrefix);
	}
	else
	{
		new CsTeams:iWinnerStartingTeam = g_flSurvivedTimeTeamT > g_flSurvivedTimeTeamCT ? CS_TEAM_T : CS_TEAM_CT;
		new CsTeams:iWinnerCurrentTeam = g_iCurrentRound % 2 ? iWinnerStartingTeam : reverseWinningTeam(iWinnerStartingTeam);
		
		new szMessageT[64], szMessageCT[64], szMessageSpec[64];
		
		formatex(szMessageT, charsmax(szMessageT), "%s %s!", g_sPluginPrefix, iWinnerCurrentTeam == CS_TEAM_T ? "^4YOU WON": "^3YOU LOST");
		formatex(szMessageCT, charsmax(szMessageCT), "%s %s!", g_sPluginPrefix, iWinnerCurrentTeam == CS_TEAM_CT  ? "^4YOU WON": "^3YOU LOST");
		formatex(szMessageSpec, charsmax(szMessageSpec), "%s Team starting as ^3%s ^1won", g_sPluginPrefix, iWinnerStartingTeam == CS_TEAM_T  ? "T" : "CT");
		
		static aPlayers[MAX_PLAYERS], iPlayerCount;
		get_players(aPlayers, iPlayerCount, "ch");
		
		for (new i; i < iPlayerCount; i++)
		{
			new playerId = aPlayers[i];
			switch (cs_get_user_team(playerId))
			{
				case CS_TEAM_T:
				{
					client_print_color(playerId, RED, szMessageT);
				}
				case CS_TEAM_CT:
				{
					client_print_color(playerId, BLUE, szMessageCT);
				}
				default:
				{
					client_print_color(playerId, getTeamColor(iWinnerStartingTeam), szMessageSpec);
				}
			}
		}

	}
	
	resetMixData();
}

CsTeams:reverseWinningTeam(const CsTeams:iTeam)
{
	switch (iTeam)
	{
		case CS_TEAM_T:
		{
			return CS_TEAM_CT;
		}
		case CS_TEAM_CT:
		{
			return CS_TEAM_T;
		}
	}
	
	return iTeam;
}

// ===============================================
// Team joining and player transfer
// ===============================================

public message_ShowMenu(const iMsgid, const iDest, const id)
{
	static szMenuCode[32];
	get_msg_arg_string(4, szMenuCode, charsmax(szMenuCode));
	
	if (mixIsActive() && TrieKeyExists(g_tBlockedTeamSelectMenus, szMenuCode))
	{
		delayedPlayerTransfer(id, CS_TEAM_SPECTATOR, iMsgid);
		return PLUGIN_HANDLED;
	}
	
	return PLUGIN_CONTINUE;
}

public message_VGUIMenu(const iMsgid, const iDest, const id)
{
	new iMenuType = get_msg_arg_int(1);
	
	if (mixIsActive())
	{
		if (iMenuType == g_iVGuiMenuTeamSelect)
		{
			delayedPlayerTransfer(id, CS_TEAM_SPECTATOR, 0);
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
	if (mixIsActive())
	{
		if (cs_get_user_team(id) == CS_TEAM_UNASSIGNED)
		{
			instantPlayerTransfer(id, CS_TEAM_SPECTATOR, 0);
		}
		
		return PLUGIN_HANDLED;
	}
	
	return PLUGIN_CONTINUE;
}

delayedPlayerTransfer(const id, const CsTeams:iTeam, const iMenuMsgId)
{
	if (!is_user_connected(id))
	{
		return;
	}
	
	new taskId = TASK_TRANSFER_PLAYER + id;
	remove_task(taskId);
	
	new Float:flTime = ((id % 4) + 1) / 10.0;
	
	new task_params[3];
	task_params[0] = id;
	task_params[1] = _:iTeam;
	task_params[2] = iMenuMsgId;
	
	set_task(flTime, "taskTransferPlayer", taskId, task_params, sizeof(task_params));
}

public taskTransferPlayer(const iParams[])
{
	new id = iParams[0];
	new CsTeams:iNewTeam = CsTeams:iParams[1];
	new iMenuMsgId = iParams[2];
	
	instantPlayerTransfer(id, iNewTeam, iMenuMsgId);
}

instantPlayerTransfer(const id, const CsTeams:iNewTeam, const iMenuMsgId)
{
	if (is_user_connected(id))
	{
		if (is_user_alive(id))
		{
			user_kill(id, 1);
		}
		
		new CsTeams:iCurrentTeam = cs_get_user_team(id);
		
		if (iCurrentTeam != iNewTeam)
		{
			resetHasChangedTeamThisRound(id);
			
			if (iMenuMsgId)
			{
				set_msg_block(iMenuMsgId, BLOCK_SET);
			}
			
			if (iCurrentTeam == CS_TEAM_UNASSIGNED && iNewTeam == CS_TEAM_SPECTATOR)
			{
				set_pdata_int(id, m_iNumRespawns, 1, EXTRAOFFSET_PLAYER);
				
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
			
			if (iMenuMsgId)
			{
				set_msg_block(iMenuMsgId, BLOCK_NOT);
			}
			
			resetHasChangedTeamThisRound(id);
		}
	}
}

resetHasChangedTeamThisRound(const id)
{
	set_pdata_int(id, m_bHasChangeTeamThisRound, get_pdata_int(id, m_bHasChangeTeamThisRound, EXTRAOFFSET_PLAYER) &~ (1 << 8), EXTRAOFFSET_PLAYER);
}

transferPlayersToSpectator()
{
	new aPlayers[32], iPlayerCount, i, playerId;
	get_players(aPlayers, iPlayerCount, "ch");
	
	for (; i < iPlayerCount; i++)
	{
		playerId = aPlayers[i];
		
		delayedPlayerTransfer(playerId, CS_TEAM_SPECTATOR, 0);
	}
}

displayTransferPlayerMenu(const id, const CsTeams:iNewTeam)
{
	if (!canTransferPlayers(id))
	{
		client_print_color(id, RED, "%s ^3Transfer menu is not available in the current state", g_sPluginPrefix);
		return;
	}
	
	static szMenuText[32];
	formatex(szMenuText, charsmax(szMenuText), "\rTransfer player to %s:", g_sTeamNames[_:iNewTeam]);
	
	new hMenu = menu_create(szMenuText, "transferPlayerMenuHandler");
	new disableCallBack = menu_makecallback("notPlayingMenuCallBack");
	
	formatex(szMenuText, charsmax(szMenuText), "\wTransfer to %s", g_sTeamNames[_:iNewTeam]);

	new szTeamItemSelection[2];
	szTeamItemSelection[0] = g_sTeamNames[_:iNewTeam][0];
	
	menu_additem(hMenu, szMenuText, szTeamItemSelection, 0);
	
	new aPlayers[MAX_PLAYERS], iPlayerCount;
	get_players(aPlayers, iPlayerCount, "ch");
	
	for (new i; i < iPlayerCount; i++)
	{
		static szUserName[48], szUserId[32];
		new playerId = aPlayers[i];
		new CsTeams:iCurrentTeam = cs_get_user_team(playerId);
		
		if (!isValidTeamTransfer(iCurrentTeam, iNewTeam))
		{
			continue;
		}
		
		get_user_name(playerId, szUserName, charsmax(szUserName));
		formatex(szUserName, charsmax(szUserName), "%s%s", szUserName, g_bNoPlay[playerId] ? g_sNotPlayingMenuItem : "");
		formatex(szUserId, charsmax(szUserId), "%d", get_user_userid(playerId));

		menu_additem(hMenu, szUserName, szUserId, 0, disableCallBack);
	}
	
	menu_display(id, hMenu, 0);
}

public transferPlayerMenuHandler(const id, const hMenu, const item)
{
	if (item == MENU_EXIT)
	{
		menu_destroy(hMenu);
		displayMainMenu(id);
		
		return PLUGIN_HANDLED;
	}
	
	new selectedPlayerId = getSelectedPlayerInMenu(hMenu, item);
	new selectedCharacter = getSelectedCharacter(hMenu, item);
	new CsTeams:iNewTeam;
	
	switch (getSelectedCharacter(hMenu, 0))
	{
		case 'T':
		{
			iNewTeam = CS_TEAM_T;
		}
		case 'C':
		{
			iNewTeam = CS_TEAM_CT;
		}
		default:
		{
			iNewTeam = CS_TEAM_SPECTATOR;
		}
	}
	
	menu_destroy(hMenu);
	
	if (!canTransferPlayers(id))
	{
		// Roundtrip back to the menu creation for error message...
	}
	else if (selectedPlayerId && isValidTeamTransfer(cs_get_user_team(selectedPlayerId), iNewTeam))
	{
		new szName[32];
		get_user_name(selectedPlayerId, szName, charsmax(szName));
		
		instantPlayerTransfer(selectedPlayerId, iNewTeam, 0);
		client_print_color(0, getTeamColor(iNewTeam), "%s ^3%s ^1was transfered to ^3%s", g_sPluginPrefix, szName, g_sTeamNames[_:iNewTeam]);
	}
	else if (selectedCharacter)
	{
		iNewTeam = getNextTransferMenuTeam(iNewTeam);
	}
	else
	{
		client_print_color(id, RED, "%s ^3Failed to transfer the selected player", g_sPluginPrefix);
	}
	
	displayTransferPlayerMenu(id, iNewTeam);
	
	return PLUGIN_HANDLED;
}

CsTeams:getNextTransferMenuTeam(const CsTeams:iCurrentTeam)
{
	switch (iCurrentTeam)
	{
		case CS_TEAM_T:
		{
			return CS_TEAM_CT;
		}
		case CS_TEAM_CT:
		{
			return CS_TEAM_SPECTATOR;
		}
	}
	
	return CS_TEAM_T;
}

getTeamColor(const CsTeams:iTeam)
{
	return iTeam == CS_TEAM_T ? RED : (iTeam == CS_TEAM_CT ? BLUE : GREY);
}

// ===============================================
// Commands
// ===============================================

public cmdTransferToT(const id)
{
	if (playerCanAdministrateMix(id))
	{	
		displayTransferPlayerMenu(id, CS_TEAM_T);
		return PLUGIN_HANDLED;
	}
	
	return PLUGIN_CONTINUE;
}

public cmdTransferToCT(const id)
{
	if (playerCanAdministrateMix(id))
	{	
		displayTransferPlayerMenu(id, CS_TEAM_CT);
		return PLUGIN_HANDLED;
	}
	
	return PLUGIN_CONTINUE;
}

public cmdTransferToSpec(const id)
{
	if (playerCanAdministrateMix(id))
	{	
		displayTransferPlayerMenu(id, CS_TEAM_SPECTATOR);
		return PLUGIN_HANDLED;
	}
	
	return PLUGIN_CONTINUE;
}

public cmdPickPlayer(const id)
{
	if (!isCaptain(id))
	{
		return PLUGIN_CONTINUE;
	}

	if (isPlayersTurnToPick(id))
	{
		displayPickPlayerMenu(id);
	}
	else
	{
		client_print_color(id, RED, "%s ^3It's currently not your turn to pick a player", g_sPluginPrefix);
	}
	
	return PLUGIN_HANDLED;
}

public cmdNoPlay(const id)
{
	if (!mixIsActive())
	{
		return PLUGIN_CONTINUE;
	}
	
	if (cs_get_user_team(id) != CS_TEAM_SPECTATOR)
	{
		client_print_color(id, RED, "%s ^3You must be a spectator to execute this command", g_sPluginPrefix);
	}
	else if (!g_bNoPlay[id])
	{
		new szName[32];
		get_user_name(id, szName, charsmax(szName));
		
		client_print_color(id, GREY, "%s ^3%s ^1is not available for playing", g_sPluginPrefix, szName);
		g_bNoPlay[id] = true;
	}
	
	return PLUGIN_HANDLED;
}

public cmdPlay(const id)
{
	if (!mixIsActive())
	{
		return PLUGIN_CONTINUE;
	}
	
	if (cs_get_user_team(id) != CS_TEAM_SPECTATOR)
	{
		client_print_color(id, RED, "%s ^3You must be a spectator to execute this command", g_sPluginPrefix);
	}
	else if (g_bNoPlay[id])
	{
		new szName[32];
		get_user_name(id, szName, charsmax(szName));
		
		client_print_color(0, GREY, "%s ^3%s ^1is available for playing", g_sPluginPrefix, szName);
		g_bNoPlay[id] = false;
	}
	
	return PLUGIN_HANDLED;
}

public cmdReplace(const id)
{
	if (!mixIsActive())
	{
		return PLUGIN_CONTINUE;
	}
	
	new Float:flGameTime = get_gametime();
	
	if (cs_get_user_team(id) == CS_TEAM_SPECTATOR)
	{
		client_print_color(id, RED, "%s ^3You can not execute this command as a spectator", g_sPluginPrefix);
	}
	else if (!canExecuteReplace(id))
	{
		client_print_color(id, RED, "%s ^3You must be dead or the game must be paused in order to replace", g_sPluginPrefix);
	}
	else if (g_flReplaceCooldown[id] && g_flReplaceCooldown[id] > flGameTime)
	{
		client_print_color(id, RED, "%s ^3You currently have a cooldown on this command. Time left: ^1%s", g_sPluginPrefix, getTimeAsText(g_flReplaceCooldown[id] - flGameTime));
	}
	else
	{
		displayReplaceMenu(id);
	}
	
	return PLUGIN_HANDLED;
}

public cmdShowScore(const id)
{
	if (g_iCurrentRound == 0)
	{
		return PLUGIN_CONTINUE;
	}
	
	printScore(id);
	
	return PLUGIN_HANDLED;
}

public cmdStartingTeam(const id)
{
	if (g_iCurrentRound == 0)
	{
		return PLUGIN_CONTINUE;
	}
	
	new bool:bEvenRound = g_iCurrentRound % 2 == 0;
	
	switch (cs_get_user_team(id))
	{
		case CS_TEAM_T:
		{
			client_print_color(id, bEvenRound ? BLUE : RED, "%s ^1Your team started out as ^3%s", g_sPluginPrefix, bEvenRound ? "CT" : "T");
		}
		case CS_TEAM_CT:
		{
			client_print_color(id, bEvenRound ? RED : BLUE, "%s ^1Your team started out as %s", g_sPluginPrefix, bEvenRound ? "T" : "CT");
		}
		default:
		{
			client_print_color(id, GREY, "%s ^1The current ^3%s team started out as ^3T", g_sPluginPrefix, bEvenRound ? "CT" : "T");
		}
	}
	
	return PLUGIN_HANDLED;
}

// ===============================================
// HNS Menu
// ===============================================

public cmdHnsMenu(const id)
{
	if (playerCanAdministrateMix(id))
	{	
		displayMainMenu(id);
		return PLUGIN_HANDLED;
	}
	
	return PLUGIN_CONTINUE;
}

displayMainMenu(const id)
{
	new hMenu = menu_create("\rHide and Seek menu:", "menuHandler");
	new disableCallBack = menu_makecallback("mainMenuDisableCallback");
	
	if (g_eMixState == MIX_INACTIVE)
	{
		menu_additem(hMenu, "\wStart mix", "1", 0, disableCallBack);
	}
	else
	{
		menu_additem(hMenu, "\wEnd mix", "2", 0, disableCallBack);
	}
	
	menu_addblank(hMenu, 0);
	
	if (g_eMixState != MIX_ONGOING && g_iCurrentRound == 0)
	{
		menu_additem(hMenu, "\wBegin mix", "3", 0, disableCallBack);
	}
	else if (g_eMixState != MIX_ONGOING)
	{
		menu_additem(hMenu, "\wResume mix", "4", 0, disableCallBack);
	}
	else
	{
		menu_additem(hMenu, "\wPause mix", "5", 0, disableCallBack);
	}
	
	menu_additem(hMenu, "\wRestart round", "6", 0, disableCallBack);
	
	menu_addblank(hMenu, 0);
	
	menu_additem(hMenu, "\wTransfer players", "7", 0, disableCallBack);
	menu_additem(hMenu, "\wGrant/Revoke mix admin", "8", 0, disableCallBack);
	
	menu_display(id, hMenu, 0);
}

public mainMenuDisableCallback(const id, const hMenu, const item)
{
	new bool:bEnableItem = true;
	
	switch (getSelectedInteger(hMenu, item))
	{
		case 3..6:
		{
			bEnableItem = g_eMixState != MIX_INACTIVE;
		}
		case 7:
		{
			bEnableItem = canTransferPlayers(id);
		}
		case 8:
		{
			bEnableItem = (get_user_flags(id) & PLUGIN_ACCESS_LEVEL) > 0;
		}
	}
	
	return bEnableItem ? ITEM_ENABLED : ITEM_DISABLED;
}

public menuHandler(const id, const hMenu, const item)
{
	if (item == MENU_EXIT || !playerCanAdministrateMix(id))
	{
		menu_destroy(hMenu);
		return PLUGIN_HANDLED;
	}
	
	new selectedItem = getSelectedInteger(hMenu, item);
	menu_destroy(hMenu);
	
	static szAdminName[32];
	get_user_name(id, szAdminName, charsmax(szAdminName));
	
	switch (selectedItem)
	{
		case 1:
		{
			if (g_eMixState != MIX_INACTIVE)
			{
				client_print_color(id, RED, "%s ^3There is already a mix in progress", g_sPluginPrefix);
			}
			else
			{
				changeState(PAUSED_MODE);
				client_print_color(0, RED, "%s ^3%s ^1started a new mix", g_sPluginPrefix, szAdminName);
				
				transferPlayersToSpectator();
				
				g_iMixStartedBy = id;
				getNextInitalizationMenu(id);
			}
		}
		case 2:
		{
			resetMixInitialization();
			resetMixData();
				
			changeState(PUBLIC_MODE);
			serverRestart();
			
			client_print_color(0, RED, "%s ^3%s ^1terminated the mix", g_sPluginPrefix, szAdminName);
		}
		case 3:
		{
			startMix();
		}
		case 4:
		{
			if (g_eMixState == MIX_PAUSED)
			{
				g_bStateChanged = true;
				g_eMixState = MIX_ONGOING;
				changeState(COMPETITIVE_MODE);
				
				serverRestartRound();
				
				client_print_color(0, RED, "%s ^3%s ^1resumed the mix", g_sPluginPrefix, szAdminName);
				set_task(1.0, "taskLiveMessage");
			}
		}
		case 5:
		{
			if (g_eMixState == MIX_ONGOING)
			{
				g_bStateChanged = true;
				g_eMixState = MIX_PAUSED;
				changeState(PAUSED_MODE);
				
				client_print_color(0, RED, "%s ^3%s ^1paused the mix", g_sPluginPrefix, szAdminName);
				
				set_dhudmessage(40, 163, 42, -1.0, 0.60, 0, 3.0, 5.5, 0.1, 1.0);
				show_dhudmessage(0, "PAUSING");
			}
		}
		case 6:
		{
			client_print_color(0, RED, "%s ^3%s ^1restarted the round", g_sPluginPrefix, szAdminName);
			serverRestartRound();
		}
		case 7:
		{
			displayTransferPlayerMenu(id, CS_TEAM_T);
		}
		case 8:
		{
			displayGiveMixAdminRightsMenu(id);
		}
	}
	
	return PLUGIN_HANDLED;
}

displayGiveMixAdminRightsMenu(const id)
{
	new hMenu = menu_create("\rGrant/Revoke mix admin:", "mixAdminRightsMenuHandler");
	
	new aPlayers[MAX_PLAYERS], iPlayerCount;
	get_players(aPlayers, iPlayerCount, "ch");
	
	for (new i; i < iPlayerCount; i++)
	{
		static szUserName[48], szUserId[32];
		new playerId = aPlayers[i];
		
		if (get_user_flags(playerId) & PLUGIN_ACCESS_LEVEL > 0)
		{
			continue;
		}
		
		get_user_name(playerId, szUserName, charsmax(szUserName));
		if (g_bTemporaryAdmin[playerId])
		{
			formatex(szUserName, charsmax(szUserName), "%s [TEMP ADMIN]", szUserName);
		}
		
		formatex(szUserId, charsmax(szUserId), "%d", get_user_userid(playerId));

		menu_additem(hMenu, szUserName, szUserId, 0);
	}
	
	menu_display(id, hMenu, 0);
}

public mixAdminRightsMenuHandler(const id, const hMenu, const item)
{
	if (item == MENU_EXIT)
	{
		menu_destroy(hMenu);
		return PLUGIN_HANDLED;
	}
	
	new selectedPlayerId = getSelectedPlayerInMenu(hMenu, item);
	menu_destroy(hMenu);
	
	if (!selectedPlayerId)
	{
		client_print_color(id, RED, "%s ^3Failed to perform the action on the selected player", g_sPluginPrefix);
	}
	else
	{
		g_bTemporaryAdmin[selectedPlayerId] = !g_bTemporaryAdmin[selectedPlayerId];
		
		static szAdminName[32], szPlayerName[32];
		
		get_user_name(id, szAdminName, charsmax(szAdminName));
		get_user_name(selectedPlayerId, szPlayerName, charsmax(szPlayerName));
		
		if (g_bTemporaryAdmin[selectedPlayerId])
		{
			client_print_color(0, GREY, "%s ^3%s ^1granted ^3%s ^1mix administration rights", g_sPluginPrefix, szAdminName, szPlayerName);
		}
		else
		{
			client_print_color(0, GREY, "%s ^3%s ^1revoked mix administration rights for ^3%s", g_sPluginPrefix, szAdminName, szPlayerName);
		}
	}
	
	return PLUGIN_HANDLED;
}

// ===============================================
// Mix initialization
// ===============================================

resetMixInitialization()
{
	g_eMixState = MIX_INACTIVE;
	g_iMixStartedBy = 0; 
	
	g_iPlayerCount = 0;
	g_iCaptainT = 0;
	g_iCaptainCT = 0;
	g_iStartPicker = 0;
}

getNextInitalizationMenu(const id)
{
	if (g_eMixState == SELECT_PLAYER_T || g_eMixState == SELECT_PLAYER_CT)
	{
		new iTs = getPlayerCount(CS_TEAM_T);
		new iCTs = getPlayerCount(CS_TEAM_CT);
		
		if (iTs == g_iPlayerCount && iCTs == g_iPlayerCount)
		{
			startMix();
			return;
		}
		else if (iTs < iCTs)
		{
			g_eMixState = SELECT_PLAYER_T;
		}
		else if (iTs > iCTs)
		{
			g_eMixState = SELECT_PLAYER_CT;
		}
		else if (g_iStartPicker == g_iCaptainT)
		{
			g_eMixState = SELECT_PLAYER_T;
		}
		else
		{
			g_eMixState = SELECT_PLAYER_CT;
		}
	}
	else
	{
		g_eMixState++;
	}
	
	switch (g_eMixState)
	{
		case SELECT_ROUNDS:
		{
			displayRoundsMenu(id);
		}
		case SELECT_ROUNDTIME:
		{
			displayRoundTimeMenu(id);
		}
		case SELECT_PLAYER_COUNT:
		{
			displayPlayerCountMenu(id);
		}
		case SELECT_CAPTAIN_T, SELECT_CAPTAIN_CT:
		{
			displayCaptainMenu(id);
		}
		case DUEL_FIRST_PICK:
		{
			changeState(KNIFE_MODE);
			serverRestart();
		}
		case SELECT_PLAYER_T:
		{
			displayPickPlayerMenu(g_iCaptainT);
		}
		case SELECT_PLAYER_CT:
		{
			displayPickPlayerMenu(g_iCaptainCT);
		}
	}
}

displayRoundsMenu(const id)
{
	new hMenu = menu_create("\rSelect rounds to play:", "roundsMenuHandler");
	
	for (new iRounds = 8; iRounds <= 20; iRounds += 4)
	{
		static szOptionText[11], szOptionValue[3];
		
		formatex(szOptionText, charsmax(szOptionText), "\w%d rounds", iRounds);
		num_to_str(iRounds, szOptionValue, charsmax(szOptionValue));
		
		menu_additem(hMenu, szOptionText, szOptionValue, 0);
	}
	
	menu_display(id, hMenu, 0);
}

public roundsMenuHandler(const id, const hMenu, const item)
{
	if (item == MENU_EXIT || g_iMixStartedBy != id)
	{
		menu_destroy(hMenu);
		return PLUGIN_HANDLED;
	}
	
	new iRounds = getSelectedInteger(hMenu, item);
	menu_destroy(hMenu);
	
	if (iRounds > 0)
	{
		g_iRoundsToPlay = iRounds;
		
		new iMinutes = floatround(iRounds * 1.8, floatround_ceil);
		
		client_print_color(0, GREY, "%s Rounds: ^3%d ^1- %d min. ^4Please don't leave! GL&HF!", g_sPluginPrefix, iRounds, iMinutes);
		
		getNextInitalizationMenu(id);
	}
	
	return PLUGIN_HANDLED;
}

displayRoundTimeMenu(const id)
{
	new hMenu = menu_create("\rSelect roundtime:", "roundTimeMenuHandler");
	
	new Float:flRoundTimes[] = { 2.0, 2.25, 2.5, 2.75 };
	
	for (new i = 0; i < sizeof flRoundTimes; i++)
	{
		static szOptionText[11], szOptionValue[6];
		
		formatex(szOptionText, charsmax(szOptionText), "\w%.2f", flRoundTimes[i]);
		float_to_str(flRoundTimes[i], szOptionValue, charsmax(szOptionValue));
		
		menu_additem(hMenu, szOptionText, szOptionValue, 0);
	}
	
	menu_display(id, hMenu, 0);
}

public roundTimeMenuHandler(const id, const hMenu, const item)
{
	if (item == MENU_EXIT || g_iMixStartedBy != id)
	{
		menu_destroy(hMenu);
		return PLUGIN_HANDLED;
	}
	
	new Float:flRoundTime = getSelectedFloat(hMenu, item);
	menu_destroy(hMenu);
	
	if (flRoundTime > 0)
	{
		set_pcvar_float(mp_roundtime, flRoundTime);
		client_print_color(0, GREY, "%s Roundtime: ^3%.2f", g_sPluginPrefix, flRoundTime);
		
		getNextInitalizationMenu(id);
	}
	
	return PLUGIN_HANDLED;
}

displayPlayerCountMenu(const id)
{
	new hMenu = menu_create("\rSelect players in each team:", "playerCountMenuHandler");
	
	for (new iPlayerCount = 1; iPlayerCount <= 5; iPlayerCount++)
	{
		static szOptionText[11], szOptionValue[3];
		
		formatex(szOptionText, charsmax(szOptionText), "\w%d vs %d", iPlayerCount, iPlayerCount);
		num_to_str(iPlayerCount, szOptionValue, charsmax(szOptionValue));
		
		menu_additem(hMenu, szOptionText, szOptionValue, 0);
	}
	
	menu_display(id, hMenu, 0);
}

public playerCountMenuHandler(const id, const hMenu, const item)
{
	if (item == MENU_EXIT || g_iMixStartedBy != id)
	{
		menu_destroy(hMenu);
		return PLUGIN_HANDLED;
	}
	
	new iPlayerCount = getSelectedInteger(hMenu, item);
	menu_destroy(hMenu);
	
	if (iPlayerCount > 0)
	{
		g_iPlayerCount = iPlayerCount;
		client_print_color(0, GREY, "%s ^3%d vs %d", g_sPluginPrefix, iPlayerCount, iPlayerCount);
		
		getNextInitalizationMenu(id);
	}
	
	return PLUGIN_HANDLED;
}

displayCaptainMenu(const id)
{
	new hMenu = menu_create("\rSelect a captain:", "captainMenuHandler");
	new disableCallBack = menu_makecallback("notPlayingMenuCallBack");
	
	menu_additem(hMenu, "Refresh menu", "R", 0, _);
	
	new aPlayers[MAX_PLAYERS], iPlayerCount;
	get_players(aPlayers, iPlayerCount, "ch");
	
	for (new i; i < iPlayerCount; i++)
	{
		static szUserName[48], szUserId[32];
		new playerId = aPlayers[i];
		
		if (cs_get_user_team(playerId) != CS_TEAM_SPECTATOR)
		{
			continue;
		}
		
		get_user_name(playerId, szUserName, charsmax(szUserName));
		formatex(szUserName, charsmax(szUserName), "%s%s", szUserName, g_bNoPlay[playerId] ? g_sNotPlayingMenuItem : "");
		formatex(szUserId, charsmax(szUserId), "%d", get_user_userid(playerId));

		menu_additem(hMenu, szUserName, szUserId, 0, disableCallBack);
	}
	
	menu_display(id, hMenu, 0);
}

public captainMenuHandler(const id, const hMenu, const item)
{
	if (item == MENU_EXIT || g_iMixStartedBy != id)
	{
		menu_destroy(hMenu);
		return PLUGIN_HANDLED;
	}
	
	new selectedPlayerId = getSelectedPlayerInMenu(hMenu, item);
	new selectedCharacter = getSelectedCharacter(hMenu, item);
	menu_destroy(hMenu);
	
	new CsTeams:iNewTeam = (g_eMixState == SELECT_CAPTAIN_T ? CS_TEAM_T : CS_TEAM_CT);
	
	if (selectedCharacter == 'R')
	{
	}
	else if (selectedPlayerId && isValidTeamTransfer(cs_get_user_team(selectedPlayerId), iNewTeam))
	{
		static szName[32];
		get_user_name(selectedPlayerId, szName, charsmax(szName));
		
		instantPlayerTransfer(selectedPlayerId, iNewTeam, 0);
		client_print_color(0, getTeamColor(iNewTeam), "%s ^3%s ^1was selected as a ^3captain", g_sPluginPrefix, szName);
		
		if (iNewTeam == CS_TEAM_T)
		{
			g_iCaptainT = selectedPlayerId;
		}
		else if (iNewTeam == CS_TEAM_CT)
		{
			g_iCaptainCT = selectedPlayerId;
		}
		
		getNextInitalizationMenu(id);
		
		return PLUGIN_HANDLED;
	}
	else
	{
		client_print_color(id, RED, "%s ^3Failed to transfer the selected player", g_sPluginPrefix);
	}
	
	displayCaptainMenu(id);
	
	return PLUGIN_HANDLED;
}

displayPickPlayerMenu(const id)
{
	new hMenu = menu_create("\rSelect a player for your team:", "pickPlayerMenuHandler");
	new disableCallBack = menu_makecallback("notPlayingMenuCallBack");
	menu_additem(hMenu, "Refresh menu", "R", 0, _);
	
	new aPlayers[MAX_PLAYERS], iPlayerCount;
	get_players(aPlayers, iPlayerCount, "ch");
	
	for (new i; i < iPlayerCount; i++)
	{
		static szUserName[48], szUserId[32];
		new playerId = aPlayers[i];
		
		if (cs_get_user_team(playerId) != CS_TEAM_SPECTATOR)
		{
			continue;
		}
		
		get_user_name(playerId, szUserName, charsmax(szUserName));
		formatex(szUserName, charsmax(szUserName), "%s%s", szUserName, g_bNoPlay[playerId] ? g_sNotPlayingMenuItem : "");
		formatex(szUserId, charsmax(szUserId), "%d", get_user_userid(playerId));

		menu_additem(hMenu, szUserName, szUserId, 0, disableCallBack);
	}
	
	menu_display(id, hMenu, 0);
}

public pickPlayerMenuHandler(const id, const hMenu, const item)
{
	if (item == MENU_EXIT || !isPlayersTurnToPick(id))
	{
		menu_destroy(hMenu);
		return PLUGIN_HANDLED;
	}
	
	new selectedPlayerId = getSelectedPlayerInMenu(hMenu, item);
	new selectedCharacter = getSelectedCharacter(hMenu, item);
	menu_destroy(hMenu);
	
	new CsTeams:iNewTeam = id == g_iCaptainT ? CS_TEAM_T : CS_TEAM_CT;
	
	if (selectedCharacter == 'R')
	{
	}
	else if (selectedPlayerId && isValidTeamTransfer(cs_get_user_team(selectedPlayerId), iNewTeam))
	{
		instantPlayerTransfer(selectedPlayerId, iNewTeam, 0);
		
		static szName[32];
		get_user_name(selectedPlayerId, szName, charsmax(szName));
		
		client_print_color(0, getTeamColor(iNewTeam), "%s ^3%s ^1was picked for ^3%s", g_sPluginPrefix, szName, g_sTeamNames[_:iNewTeam]);
		
		getNextInitalizationMenu(id);
		return PLUGIN_HANDLED;
	}
	else
	{
		client_print_color(id, RED, "%s ^3Failed to transfer the selected player", g_sPluginPrefix);
	}
	
	displayPickPlayerMenu(id);
	
	return PLUGIN_HANDLED;
}

// ===============================================
// Player utils
// ===============================================

displayReplaceMenu(const id)
{
	new hMenu = menu_create("\rSelect a player to replace with:", "replaceMenuHandler");
	new disableCallBack = menu_makecallback("replaceMenuCallBack");
	menu_additem(hMenu, "Refresh menu", "R", 0, _);
	
	new aPlayers[MAX_PLAYERS], iPlayerCount;
	get_players(aPlayers, iPlayerCount, "ch");
	
	new Float:flGameTime = get_gametime();
	
	for (new i; i < iPlayerCount; i++)
	{
		static szUserName[48], szUserId[32];
		new playerId = aPlayers[i];
		
		if (cs_get_user_team(playerId) != CS_TEAM_SPECTATOR)
		{
			continue;
		}
		
		get_user_name(playerId, szUserName, charsmax(szUserName));
		
		if (g_bNoPlay[playerId])
		{
			formatex(szUserName, charsmax(szUserName), "%s%s", szUserName, g_sNotPlayingMenuItem);
		}
		else if (g_flReplaceCooldown[playerId] > flGameTime)
		{
			formatex(szUserName, charsmax(szUserName), "%s [COOLDOWN]", szUserName);
		}
		
		formatex(szUserId, charsmax(szUserId), "%d", get_user_userid(playerId));

		menu_additem(hMenu, szUserName, szUserId, 0, disableCallBack);
	}
	
	menu_display(id, hMenu, 0);
}

public replaceMenuHandler(const id, const hMenu, const item)
{
	if (item == MENU_EXIT)
	{
		menu_destroy(hMenu);
		return PLUGIN_HANDLED;
	}
	
	new selectedPlayerId = getSelectedPlayerInMenu(hMenu, item);
	new selectedCharacter = getSelectedCharacter(hMenu, item);
	menu_destroy(hMenu);
	
	new CsTeams:iNewTeam = cs_get_user_team(id);
	
	if (iNewTeam == CS_TEAM_SPECTATOR || !canExecuteReplace(id))
	{
		static szName[32];
		get_user_name(id, szName, charsmax(szName));
		client_print_color(id, GREY, "%s Sent replace request to ^3%s", g_sPluginPrefix, szName);
		
		return PLUGIN_HANDLED;
	}
	
	if (selectedCharacter == 'R')
	{
	}
	else if (selectedPlayerId && isValidTeamTransfer(cs_get_user_team(selectedPlayerId), iNewTeam))
	{
		static szName[32];
		get_user_name(selectedPlayerId, szName, charsmax(szName));
		client_print_color(id, GREY, "%s Sent replace request to ^3%s", g_sPluginPrefix, szName);
		
		displayReplaceRequestMenu(selectedPlayerId, id);
		return PLUGIN_HANDLED;
	}
	else
	{
		client_print_color(id, RED, "%s ^3Can not replace with the selected player", g_sPluginPrefix);
	}
	
	displayReplaceMenu(id);
	
	return PLUGIN_HANDLED;
}

public replaceMenuCallBack(const id, const hMenu, const item)
{
	new selectedPlayer = getSelectedPlayerInMenu(hMenu, item);
	
	if (selectedPlayer && (g_bNoPlay[selectedPlayer] || g_flReplaceCooldown[selectedPlayer] > get_gametime()))
	{
		return ITEM_DISABLED;
	}
	
	return ITEM_ENABLED;
}

displayReplaceRequestMenu(const id, const replaceWithId)
{
	static szMenuTitle[32], szUserId[32];
	
	get_user_name(replaceWithId, szUserId, charsmax(szUserId));
	formatex(szMenuTitle, charsmax(szMenuTitle), "\rReplace %s?", szUserId);
	
	formatex(szUserId, charsmax(szUserId), "%d", get_user_userid(replaceWithId));
	
	new hMenu = menu_create(szMenuTitle, "replaceRequestMenuHandler");
	
	menu_additem(hMenu, "Accept", szUserId, 0);
	menu_additem(hMenu, "Reject", szUserId, 0);
	
	menu_display(id, hMenu, 0);
}

public replaceRequestMenuHandler(const id, const hMenu, const item)
{
	new selectedPlayerId = getSelectedPlayerInMenu(hMenu, item);
	menu_destroy(hMenu);
	
	if (item == MENU_EXIT || !selectedPlayerId)
	{
		return PLUGIN_HANDLED;
	}
	
	new CsTeams:iNewTeam = cs_get_user_team(selectedPlayerId);
	
	if (!isValidTeamTransfer(cs_get_user_team(id), iNewTeam) || !isValidTeamTransfer(iNewTeam, CS_TEAM_SPECTATOR) || !canExecuteReplace(selectedPlayer))
	{
		return PLUGIN_HANDLED;
	}
	else if (item == 1)
	{
		static szName[32];
		get_user_name(id, szName, charsmax(szName));
		client_print_color(selectedPlayerId, RED, "%s ^3%s rejected your replace request", g_sPluginPrefix, szName);
		
		return PLUGIN_HANDLED;
	}
	
	new Float:flCooldown = get_gametime() + 60.0 * 5;
	
	g_flReplaceCooldown[id] = flCooldown;
	g_flReplaceCooldown[selectedPlayerId] = flCooldown;
	
	instantPlayerTransfer(id, iNewTeam, 0);
	instantPlayerTransfer(selectedPlayerId, CS_TEAM_SPECTATOR, 0);
	
	new szName1[32], szName2[32];
	get_user_name(id, szName1, charsmax(szName1));
	get_user_name(selectedPlayerId, szName2, charsmax(szName2));
	
	client_print_color(0, getTeamColor(iNewTeam), "%s ^3%s ^1replaced ^3%s", g_sPluginPrefix, szName1, szName2);
	
	return PLUGIN_HANDLED;
}

// ===============================================
// Help methods
// ===============================================

getSelectedPlayerInMenu(const hMenu, const item)
{
	new selectedPlayerId = find_player("k", getSelectedInteger(hMenu, item));
	return selectedPlayerId && is_user_connected(selectedPlayerId) ? selectedPlayerId : 0;
}

getSelectedInteger(const hMenu, const item)
{
	static szData[6], szName[32];
	new _access, item_callback;
	menu_item_getinfo(hMenu, item, _access, szData, charsmax(szData), szName, charsmax(szName), item_callback);
	
	return str_to_num(szData);
}

Float:getSelectedFloat(const hMenu, const item)
{
	static szData[6], szName[32];
	new _access, item_callback;
	menu_item_getinfo(hMenu, item, _access, szData, charsmax(szData), szName, charsmax(szName), item_callback);
	
	return str_to_float(szData);
}

getSelectedCharacter(const hMenu, const item)
{
	static szData[2], szName[32];
	new _access, item_callback;
	menu_item_getinfo(hMenu, item, _access, szData, charsmax(szData), szName, charsmax(szName), item_callback);
	
	return szData[0];
}

public notPlayingMenuCallBack(const id, const hMenu, const item)
{
	new selectedPlayer = getSelectedPlayerInMenu(hMenu, item);
	
	if (selectedPlayer && g_bNoPlay[selectedPlayer])
	{
		return ITEM_DISABLED;
	}
	
	return ITEM_ENABLED;
}

changeState(const ePluginState:eNewState)
{
	hns_changeState(eNewState);
	g_bStateChanged = true;
	
	remove_task(TASK_COUNTDOWN);
}

printScore(const id)
{
	new Float:flTimeTeamT, Float:flTimeTeamCT;
	
	if (g_iCurrentRound % 2 == 1)
	{
		flTimeTeamT = g_flSurvivedTimeTeamT;
		flTimeTeamCT = g_flSurvivedTimeTeamCT;
	}
	else
	{
		flTimeTeamT = g_flSurvivedTimeTeamCT;
		flTimeTeamCT = g_flSurvivedTimeTeamT;
	}
	
	if (g_flRoundStart && g_eMixState == MIX_ONGOING && !g_bStateChanged)
	{
		new Float:flCurrentTime = get_gametime() - g_flRoundStart;
		flTimeTeamT += flCurrentTime;
	}
	
	static aPlayers[MAX_PLAYERS], iPlayerCount;
	
	if (id == 0)
	{
		get_players(aPlayers, iPlayerCount, "ch");
	}
	else
	{
		iPlayerCount = 1;
		aPlayers[0] = id;
	}
	
	static szMessageT[96], szMessageCT[96], szMessageSpec[96];
	
	formatex(szMessageT, charsmax(szMessageT), "%s [^4%s ^3T ^1| CT ^4%s^1] [R %d/%d]%s", g_sPluginPrefix,
	getTimeAsText(flTimeTeamT), getTimeAsText(flTimeTeamCT),
	g_iCurrentRound, g_iRoundsToPlay,
	g_eMixState == MIX_PAUSED ? " ^1[^4PAUSED^1]" : "");
	
	formatex(szMessageCT, charsmax(szMessageCT), "%s [^4%s ^1T | ^3CT ^4%s^1] [R %d/%d]%s", g_sPluginPrefix,
	getTimeAsText(flTimeTeamT), getTimeAsText(flTimeTeamCT),
	g_iCurrentRound, g_iRoundsToPlay,
	g_eMixState == MIX_PAUSED ? " ^1[^4PAUSED^1]" : "");
	
	formatex(szMessageSpec, charsmax(szMessageSpec), "%s [^4%s ^3T ^1| ^3CT ^4%s^1] [R %d/%d]%s", g_sPluginPrefix,
	getTimeAsText(flTimeTeamT), getTimeAsText(flTimeTeamCT),
	g_iCurrentRound, g_iRoundsToPlay,
	g_eMixState == MIX_PAUSED ? " ^1[^4PAUSED^1]" : "");
	
	for (new i; i < iPlayerCount; i++)
	{
		new playerId = aPlayers[i];
		
		switch (cs_get_user_team(playerId))
		{
			case CS_TEAM_T:
			{
				client_print_color(playerId, RED, szMessageT);
			}
			case CS_TEAM_CT:
			{
				client_print_color(playerId, BLUE, szMessageCT);
			}
			default:
			{
				client_print_color(playerId, GREY, szMessageSpec);
			}
		}
	}
}

getTimeAsText(const Float:flTime)
{
	static szTime[10];
	new iTime, iMinutes, iSeconds, iMilliSeconds;
	
	iTime = floatround(flTime, floatround_floor);
	iMinutes = iTime / 60;
	iSeconds = iTime - iMinutes * 60;
	iMilliSeconds = floatround((flTime - iTime) * 1000.0, floatround_floor);
	
	formatex(szTime, charsmax(szTime), "%s%d:%s%d.%s%s%d",
	(iMinutes < 10 ? "0" : ""), iMinutes,
	(iSeconds < 10 ? "0" : ""), iSeconds,
	(iMilliSeconds < 100 ? "0" : ""),
	(iMilliSeconds < 10 ? "0" : ""), iMilliSeconds);
	
	return szTime;
}

serverRestartRound()
{
	remove_task(TASK_COUNTDOWN);
	server_cmd("hns_restartround");
}

serverRestart()
{
	server_cmd("hns_restart");
}

resetMixData()
{
	g_iCurrentRound = 0;
	g_iRoundsToPlay = 0;
	
	g_flSurvivedTimeTeamT = 0.0;
	g_flSurvivedTimeTeamCT = 0.0;
	
	new iForwardReturn;
	if (!ExecuteForward(g_iMixEndedForward, iForwardReturn))
	{
		log_amx("Could not execute mix ended forward");
	}
}

startMix()
{
	g_iCurrentRound = 1;
	
	resetMixInitialization();
	g_eMixState = MIX_ONGOING;
	
	changeState(COMPETITIVE_MODE);
	serverRestart();
	
	new iForwardReturn;
	if (!ExecuteForward(g_iMixStartedForward, iForwardReturn, g_iRoundsToPlay))
	{
		log_amx("Could not execute mix started forward");
	}
	
	client_print_color(0, RED, "%s ^3LIVE! GL&HF!", g_sPluginPrefix);
	set_task(1.0, "taskLiveMessage");
}

public taskLiveMessage()
{
	set_dhudmessage(241, 58, 19, -1.0, 0.60, 0, 3.0, 5.5, 0.1, 1.0);
	show_dhudmessage(0, "LIVE LIVE LIVE");
}

public taskCountDown(const iParams[])
{
	new iSecond = iParams[0];
	
	if (iSecond)
	{
		static szSound[16], aPlayers[MAX_PLAYERS];
		num_to_word(iSecond, szSound, charsmax(szSound));
		
		new iPlayerCount;
		get_players(aPlayers, iPlayerCount, "ch");
		
		for (new i; i < iPlayerCount; i++)
		{
			client_cmd(aPlayers[i], "spk ^"vox/%s^"", szSound);
		}
		
		new task_params[1];
		task_params[0] = iParams[0] - 1;
	
		set_task(1.0, "taskCountDown", TASK_COUNTDOWN, task_params, sizeof(task_params));
	}
	else
	{
		new Float:flSurvivedTime = get_gametime() - g_flRoundStart;
		
		if (g_iCurrentRound % 2)
		{
			g_flSurvivedTimeTeamT += flSurvivedTime;
		}
		else
		{
			g_flSurvivedTimeTeamCT += flSurvivedTime;
		}
		
		mixCompleted();
	}
}

getPlayerCount(CsTeams:iTeam)
{
	new iPlayerCount = 0;
	
	static aPlayers[MAX_PLAYERS], iRetrievedCount;
	get_players(aPlayers, iRetrievedCount, "ch");
	
	for (new i; i < iRetrievedCount; i++)
	{
		if (cs_get_user_team(aPlayers[i]) == iTeam)
		{
			iPlayerCount++;
		}
	}
	
	return iPlayerCount;
}
