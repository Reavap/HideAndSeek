#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <fakemeta>
#include <hns_main>
#include <hns_mix>
#include <hns_mixaccessories>
#include <hns_teamjoin>

#pragma semicolon				1

#define PLUGIN_NAME				"HNS_Mix"
#define PLUGIN_VERSION			"1.0.0"
#define PLUGIN_AUTHOR			"Reavap"

#define PLUGIN_ACCESS_LEVEL		ADMIN_LEVEL_A

#define TASK_COUNTDOWN			4000
#define TASK_TRANSFER_PLAYER	5000

#define playerCanAdministrateMix(%1) ((get_user_flags(%1) & PLUGIN_ACCESS_LEVEL) > 0)

#define canTransferPlayers(%1) (g_MixState == MixState_Paused && playerCanAdministrateMix(%1))
#define isValidTeamTransfer(%1,%2) ((%1 == CS_TEAM_CT || %1 == CS_TEAM_T) != (%2 == CS_TEAM_CT || %2 == CS_TEAM_T) && %1 != CS_TEAM_UNASSIGNED)

#define isCaptain(%1) (%1 == g_iCaptainT || %1 == g_iCaptainCT)
#define isPlayersTurnToPick(%1) ((%1 == g_iCaptainT && g_SetupState == SELECT_PLAYER_T) || (%1 == g_iCaptainCT && g_SetupState == SELECT_PLAYER_CT))

#define mixIsActive() (g_MixState != MixState_Inactive)

// Cvars
new mp_roundtime;

// Mix-Forwards (Events)
new g_MixStateChangedForward;
new g_iMixStartedForward;
new g_iMixEndedForward;
new g_iMixRoundCompletedForward;

// HNS States
new HnsMixStates:g_MixState;
new bool:g_bStateChanged;

new Float:g_flRoundTime;
new Float:g_flRoundStart;

new g_iCurrentRound;
new g_iRoundsToPlay;

new Float:g_flSurvivedTimeTeamT;
new Float:g_flSurvivedTimeTeamCT;

new bool:g_OptOutOfMixParticipation[MAX_PLAYERS + 1];

// Mix initialization
enum MixSetupStates (+= 1)
{
	SETUP_NONE = 0,
	SELECT_ROUNDS,
	SELECT_ROUNDTIME,
	SELECT_PLAYER_COUNT,
	SELECT_CAPTAIN_T,
	SELECT_CAPTAIN_CT,
	DUEL_FIRST_PICK,
	SELECT_PLAYER_T,
	SELECT_PLAYER_CT
};

new MixSetupStates:g_SetupState;
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

new const g_sPluginPrefix[] = "^1[^4HNS^1]";
new const g_sNotPlayingMenuItem[] = " [NOT PLAYING]";
new const GetPlayersFlags:g_GetPlayerFlags = GetPlayers_ExcludeBots | GetPlayers_ExcludeHLTV;

// Not currently in use
new const g_bEarlyExitSetting = false;

public plugin_init()
{
	register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
	register_cvar(PLUGIN_NAME, PLUGIN_VERSION, FCVAR_SERVER|FCVAR_SPONLY);
	
	mp_roundtime = get_cvar_pointer("mp_roundtime");
	
	register_event("HLTV", "eventNewRound", "a", "1=0", "2=0");
	register_logevent("eventRoundStart", 2, "1=Round_Start");
	register_logevent("eventHostage", 6, "3=Hostages_Not_Rescued");
	register_logevent("eventTwin", 6, "3=Terrorists_Win");
	register_logevent("eventCTwin", 6, "3=CTs_Win");
	
	register_clcmd("hnsmenu","cmdHnsMenu");
	register_clcmd("say /hnsmenu","cmdHnsMenu");
	
	register_clcmd("say /t", "cmdTransferToT");
	register_clcmd("say /ct", "cmdTransferToCT");
	register_clcmd("say /spec", "cmdTransferToSpec");
	register_clcmd("say /pick", "cmdPickPlayer");
	
	register_clcmd("say /s", "cmdShowScore");
	register_clcmd("say /score", "cmdShowScore");
	register_clcmd("say /time", "cmdShowScore");
	
	register_clcmd("say /st", "cmdStartingTeam");
	register_clcmd("say /startingteam", "cmdStartingTeam");
	
	initializeEventForwards();
}

initializeEventForwards()
{
	new pluginId = find_plugin_byfile("hns_mixstats.amxx");
	
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

	g_MixStateChangedForward = CreateMultiForward("HNS_Mix_StateChanged", ET_IGNORE, FP_CELL);

	if (g_MixStateChangedForward < 0)
	{
		log_amx("Mix state changed forward could not be created.");
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

	DestroyForward(g_MixStateChangedForward);
	g_MixStateChangedForward = 0;
}

public client_disconnected(id)
{
	if (id == g_iCaptainT)
	{
		client_print_color(0, print_team_red, "%s Captain for team ^3T ^1disconnected!", g_sPluginPrefix);
		g_iCaptainT = 0;
	}
	
	if (id == g_iCaptainCT)
	{
		client_print_color(0, print_team_blue, "%s Captain for team ^3CT ^1disconnected!", g_sPluginPrefix);
		g_iCaptainCT = 0;
	}
	
	if (id == g_iMixStartedBy)
	{
		resetMixInitialization();
		
		changeState(MixState_Inactive);
		serverRestart();
	}
}

public HNS_Mix_ParticipationChanged(const id, const bool:optOut)
{
	g_OptOutOfMixParticipation[id] = optOut;
}

// ===============================================
// Round start/end events
// ===============================================

public eventNewRound()
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
	
	if (!g_bStateChanged && g_MixState == MixState_Ongoing && flTimeDif <= g_flRoundTime && g_bEarlyExitSetting)
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
	if (g_MixState == MixState_Ongoing)
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
	
	if (g_MixState == MixState_Ongoing)
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
				hns_switch_teams();
				serverRestartRound();
			}
		}
		
		new iForwardReturn;
		if (!ExecuteForward(g_iMixRoundCompletedForward, iForwardReturn, iWinningTeam))
		{
			log_amx("Could not execute round completed forward");
		}
	}
	else if (g_SetupState == DUEL_FIRST_PICK)
	{
		if (iWinningTeam == CS_TEAM_CT)
		{
			g_iStartPicker = g_iCaptainCT;
		}
		else
		{
			g_iStartPicker = g_iCaptainT;
		}
		
		g_SetupState = SELECT_PLAYER_T;
		hns_change_state(HnsState_Custom);
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
	changeState(MixState_Inactive);
	serverRestart();
	
	if (g_flSurvivedTimeTeamT == g_flSurvivedTimeTeamCT)
	{
		client_print_color(0, print_team_grey, "%s Mix finished with a draw!", g_sPluginPrefix);
	}
	else
	{
		new CsTeams:iWinnerStartingTeam = g_flSurvivedTimeTeamT > g_flSurvivedTimeTeamCT ? CS_TEAM_T : CS_TEAM_CT;
		new CsTeams:iWinnerCurrentTeam = g_iCurrentRound % 2 ? iWinnerStartingTeam : reverseWinningTeam(iWinnerStartingTeam);
		
		new szMessageT[64], szMessageCT[64], szMessageSpec[64];
		
		formatex(szMessageT, charsmax(szMessageT), "%s %s!", g_sPluginPrefix, iWinnerCurrentTeam == CS_TEAM_T ? "^4YOU WON": "^3YOU LOST");
		formatex(szMessageCT, charsmax(szMessageCT), "%s %s!", g_sPluginPrefix, iWinnerCurrentTeam == CS_TEAM_CT ? "^4YOU WON": "^3YOU LOST");
		formatex(szMessageSpec, charsmax(szMessageSpec), "%s Team starting as ^3%s ^1won", g_sPluginPrefix, iWinnerStartingTeam == CS_TEAM_T ? "T" : "CT");
		
		static aPlayers[MAX_PLAYERS], iPlayerCount;
		get_players(aPlayers, iPlayerCount, "ch");
		
		for (new i; i < iPlayerCount; i++)
		{
			new playerId = aPlayers[i];
			switch (cs_get_user_team(playerId))
			{
				case CS_TEAM_T:
				{
					client_print_color(playerId, print_team_red, szMessageT);
				}
				case CS_TEAM_CT:
				{
					client_print_color(playerId, print_team_blue, szMessageCT);
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
// Player transfer
// ===============================================

displayTransferPlayerMenu(const id, const CsTeams:iNewTeam)
{
	if (!canTransferPlayers(id))
	{
		client_print_color(id, print_team_red, "%s ^3Transfer menu is not available in the current state", g_sPluginPrefix);
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

		if (g_OptOutOfMixParticipation[playerId])
		{
			formatex(szUserName, charsmax(szUserName), "%s%s", szUserName, g_sNotPlayingMenuItem);
		}

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
		
		hns_transfer_player(selectedPlayerId, iNewTeam);
		client_print_color(0, getTeamColor(iNewTeam), "%s ^3%s ^1was transfered to ^3%s", g_sPluginPrefix, szName, g_sTeamNames[_:iNewTeam]);
	}
	else if (selectedCharacter)
	{
		iNewTeam = getNextTransferMenuTeam(iNewTeam);
	}
	else
	{
		client_print_color(id, print_team_red, "%s ^3Failed to transfer the selected player", g_sPluginPrefix);
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
		client_print_color(id, print_team_red, "%s ^3It's currently not your turn to pick a player", g_sPluginPrefix);
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
			client_print_color(id, bEvenRound ? print_team_blue : print_team_red, "%s ^1Your team started out as ^3%s", g_sPluginPrefix, bEvenRound ? "CT" : "T");
		}
		case CS_TEAM_CT:
		{
			client_print_color(id, bEvenRound ? print_team_red : print_team_blue, "%s ^1Your team started out as %s", g_sPluginPrefix, bEvenRound ? "T" : "CT");
		}
		default:
		{
			client_print_color(id, print_team_grey, "%s ^1The current ^3%s team started out as ^3T", g_sPluginPrefix, bEvenRound ? "CT" : "T");
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
	
	if (g_MixState == MixState_Inactive)
	{
		menu_additem(hMenu, "\wStart mix", "1", 0, disableCallBack);
	}
	else
	{
		menu_additem(hMenu, "\wEnd mix", "2", 0, disableCallBack);
	}
	
	menu_addblank(hMenu, 0);
	
	if (g_MixState != MixState_Ongoing && g_iCurrentRound == 0)
	{
		menu_additem(hMenu, "\wBegin mix", "3", 0, disableCallBack);
	}
	else if (g_MixState != MixState_Ongoing)
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
	
	menu_display(id, hMenu, 0);
}

public mainMenuDisableCallback(const id, const hMenu, const item)
{
	new bool:bEnableItem = true;
	
	switch (getSelectedInteger(hMenu, item))
	{
		case 3..6:
		{
			bEnableItem = g_MixState != MixState_Inactive;
		}
		case 7:
		{
			bEnableItem = canTransferPlayers(id);
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
			if (g_MixState != MixState_Inactive)
			{
				client_print_color(id, print_team_red, "%s ^3There is already a mix in progress", g_sPluginPrefix);
			}
			else
			{
				changeState(MixState_Setup);
				client_print_color(0, print_team_red, "%s ^3%s ^1started a new mix", g_sPluginPrefix, szAdminName);
				
				hns_transfer_all_players(CS_TEAM_SPECTATOR);
				
				g_iMixStartedBy = id;
				getNextInitalizationMenu(id);
			}
		}
		case 2:
		{
			resetMixInitialization();
			resetMixData();
				
			changeState(MixState_Inactive);
			serverRestart();
			
			client_print_color(0, print_team_red, "%s ^3%s ^1terminated the mix", g_sPluginPrefix, szAdminName);
		}
		case 3:
		{
			startMix();
		}
		case 4:
		{
			if (g_MixState == MixState_Paused)
			{
				changeState(MixState_Ongoing);
				
				serverRestartRound();
				
				client_print_color(0, print_team_red, "%s ^3%s ^1resumed the mix", g_sPluginPrefix, szAdminName);
				set_task(1.0, "taskLiveMessage");
			}
		}
		case 5:
		{
			if (g_MixState == MixState_Ongoing)
			{
				changeState(MixState_Paused);
				
				client_print_color(0, print_team_red, "%s ^3%s ^1paused the mix", g_sPluginPrefix, szAdminName);
				
				set_dhudmessage(40, 163, 42, -1.0, 0.60, 0, 3.0, 5.5, 0.1, 1.0);
				show_dhudmessage(0, "PAUSING");
			}
		}
		case 6:
		{
			client_print_color(0, print_team_red, "%s ^3%s ^1restarted the round", g_sPluginPrefix, szAdminName);
			serverRestartRound();
		}
		case 7:
		{
			displayTransferPlayerMenu(id, CS_TEAM_T);
		}
	}
	
	return PLUGIN_HANDLED;
}

// ===============================================
// Mix initialization
// ===============================================

resetMixInitialization()
{
	g_SetupState = SETUP_NONE;
	g_iMixStartedBy = 0;
	
	g_iPlayerCount = 0;
	g_iCaptainT = 0;
	g_iCaptainCT = 0;
	g_iStartPicker = 0;
}

getNextInitalizationMenu(const id)
{
	if (g_SetupState == SELECT_PLAYER_T || g_SetupState == SELECT_PLAYER_CT)
	{
		new iTs = get_playersnum_ex(g_GetPlayerFlags | GetPlayers_MatchTeam, "TERRORIST");
		new iCTs = get_playersnum_ex(g_GetPlayerFlags | GetPlayers_MatchTeam, "CT");
		
		if (iTs == g_iPlayerCount && iCTs == g_iPlayerCount)
		{
			startMix();
			return;
		}
		else if (iTs < iCTs)
		{
			g_SetupState = SELECT_PLAYER_T;
		}
		else if (iTs > iCTs)
		{
			g_SetupState = SELECT_PLAYER_CT;
		}
		else if (g_iStartPicker == g_iCaptainT)
		{
			g_SetupState = SELECT_PLAYER_T;
		}
		else
		{
			g_SetupState = SELECT_PLAYER_CT;
		}
	}
	else
	{
		g_SetupState++;
	}
	
	switch (g_SetupState)
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
			hns_change_state(HnsState_Knife);
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
		
		client_print_color(0, print_team_grey, "%s Rounds: ^3%d ^1- %d min. ^4Please don't leave! GL&HF!", g_sPluginPrefix, iRounds, iMinutes);
		
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
		client_print_color(0, print_team_grey, "%s Roundtime: ^3%.2f", g_sPluginPrefix, flRoundTime);
		
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
		client_print_color(0, print_team_grey, "%s ^3%d vs %d", g_sPluginPrefix, iPlayerCount, iPlayerCount);
		
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

		if (g_OptOutOfMixParticipation[playerId])
		{
			formatex(szUserName, charsmax(szUserName), "%s%s", szUserName, g_sNotPlayingMenuItem);
		}

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
	
	new CsTeams:iNewTeam = (g_SetupState == SELECT_CAPTAIN_T ? CS_TEAM_T : CS_TEAM_CT);
	
	if (selectedCharacter == 'R')
	{
	}
	else if (selectedPlayerId && isValidTeamTransfer(cs_get_user_team(selectedPlayerId), iNewTeam))
	{
		static szName[32];
		get_user_name(selectedPlayerId, szName, charsmax(szName));
		
		hns_transfer_player(selectedPlayerId, iNewTeam);
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
		client_print_color(id, print_team_red, "%s ^3Failed to transfer the selected player", g_sPluginPrefix);
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

		if (g_OptOutOfMixParticipation[playerId])
		{
			formatex(szUserName, charsmax(szUserName), "%s%s", szUserName, g_sNotPlayingMenuItem);
		}

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
		hns_transfer_player(selectedPlayerId, iNewTeam);
		
		static szName[32];
		get_user_name(selectedPlayerId, szName, charsmax(szName));
		
		client_print_color(0, getTeamColor(iNewTeam), "%s ^3%s ^1was picked for ^3%s", g_sPluginPrefix, szName, g_sTeamNames[_:iNewTeam]);
		
		getNextInitalizationMenu(id);
		return PLUGIN_HANDLED;
	}
	else
	{
		client_print_color(id, print_team_red, "%s ^3Failed to transfer the selected player", g_sPluginPrefix);
	}
	
	displayPickPlayerMenu(id);
	
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
	
	if (selectedPlayer && g_OptOutOfMixParticipation[selectedPlayer])
	{
		return ITEM_DISABLED;
	}
	
	return ITEM_ENABLED;
}

changeState(const HnsMixStates:newState)
{
	if (g_MixState == newState)
	{
		return;
	}

	if (g_MixState == MixState_Inactive)
	{
		hns_change_state(HnsState_Custom);
	}
	else if (newState == MixState_Inactive)
	{
		hns_change_state(HnsState_Public);
	}

	g_bStateChanged = true;
	g_MixState = newState;
	remove_task(TASK_COUNTDOWN);

	if (!ExecuteForward(g_MixStateChangedForward, _, newState))
	{
		log_amx("Could not execute mix state changed forward");
	}
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
	
	if (g_flRoundStart && g_MixState == MixState_Ongoing && !g_bStateChanged)
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
	getTimeAsText(flTimeTeamT, true), getTimeAsText(flTimeTeamCT, true),
	g_iCurrentRound, g_iRoundsToPlay,
	g_MixState == MixState_Paused ? " ^1[^4PAUSED^1]" : "");
	
	formatex(szMessageCT, charsmax(szMessageCT), "%s [^4%s ^1T | ^3CT ^4%s^1] [R %d/%d]%s", g_sPluginPrefix,
	getTimeAsText(flTimeTeamT, true), getTimeAsText(flTimeTeamCT, true),
	g_iCurrentRound, g_iRoundsToPlay,
	g_MixState == MixState_Paused ? " ^1[^4PAUSED^1]" : "");
	
	formatex(szMessageSpec, charsmax(szMessageSpec), "%s [^4%s ^3T ^1| ^3CT ^4%s^1] [R %d/%d]%s", g_sPluginPrefix,
	getTimeAsText(flTimeTeamT, true), getTimeAsText(flTimeTeamCT, true),
	g_iCurrentRound, g_iRoundsToPlay,
	g_MixState == MixState_Paused ? " ^1[^4PAUSED^1]" : "");
	
	for (new i; i < iPlayerCount; i++)
	{
		new playerId = aPlayers[i];
		
		switch (cs_get_user_team(playerId))
		{
			case CS_TEAM_T:
			{
				client_print_color(playerId, print_team_red, szMessageT);
			}
			case CS_TEAM_CT:
			{
				client_print_color(playerId, print_team_blue, szMessageCT);
			}
			default:
			{
				client_print_color(playerId, print_team_grey, szMessageSpec);
			}
		}
	}
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
	changeState(MixState_Ongoing);
	serverRestart();
	
	new iForwardReturn;
	if (!ExecuteForward(g_iMixStartedForward, iForwardReturn, g_iRoundsToPlay))
	{
		log_amx("Could not execute mix started forward");
	}
	
	client_print_color(0, print_team_red, "%s ^3LIVE! GL&HF!", g_sPluginPrefix);
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