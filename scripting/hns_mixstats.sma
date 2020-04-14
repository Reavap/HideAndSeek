#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <hamsandwich>

#pragma semicolon			1

#define PLUGIN_NAME			"HNS_MixStats"
#define PLUGIN_VERSION		"1.0.0"
#define PLUGIN_AUTHOR		"Reavap"

#define STEAMID_LEN			33
#define USERNAME_LEN		33
#define ASSIST_SLOTS		3

new g_iCompletedRounds;
new g_iRoundsToPlay;

new bool:g_bFreezeTime;
new bool:g_bRoundHasEnded;

new Float:g_fRoundStart;
new Float:g_fRoundTime;

new CsTeams:g_iTeam[MAX_PLAYERS + 1];
new bool:g_bAlive[MAX_PLAYERS + 1];

new bool:g_bSpawnedThisRound[MAX_PLAYERS + 1];
new bool:g_bAuthorizeNextRound[MAX_PLAYERS + 1];

new g_iKills[MAX_PLAYERS + 1];
new g_iAssists[MAX_PLAYERS + 1];
new Float:g_fSurvivedTime[MAX_PLAYERS + 1];

new g_iAttackers[MAX_PLAYERS + 1][ASSIST_SLOTS];
new g_sSteamID[MAX_PLAYERS + 1][STEAMID_LEN];

enum _:ePlayerStats
{
	Kills,
	Assists,
	Float:SurvTime,
	CTRounds,
	TRounds,
	CTRank,
	bool:TiedCTRank,
	TRank,
	bool:TiedTRank
};

new Trie:g_tStats;
new Trie:g_tUsernameLookup;

new Array:g_aSeekerTop;
new Array:g_aHiderTop;

new const g_iTopListLength = 5;
new const g_sPluginPrefix[] = "^1[^4Mix Stats^1]";

public plugin_init()
{
	register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
	register_cvar(PLUGIN_NAME, PLUGIN_VERSION, FCVAR_SERVER|FCVAR_SPONLY);
	
	new sPlayer[] = "player";
	RegisterHam(Ham_Spawn, sPlayer, "fwdHamSpawn", 1);
	RegisterHam(Ham_Killed, sPlayer, "fwdHamKilled", 0);
	RegisterHam(Ham_TakeDamage, sPlayer, "fwdHamTakeDamage", 0);
	
	register_event("HLTV", "eventNewRound", "a", "1=0", "2=0");
	register_logevent("eventRoundStart", 2, "1=Round_Start");
	
	register_clcmd("say /ps", "cmdPersonalStats");
	register_clcmd("say /mixtop", "cmdMixTop");
	
	g_tStats = TrieCreate();
	g_tUsernameLookup = TrieCreate();
	g_aSeekerTop = ArrayCreate(STEAMID_LEN);
	g_aHiderTop = ArrayCreate(STEAMID_LEN);
}

public client_authorized(id)
{
	if (g_bSpawnedThisRound[id])
	{
		// Perform authorization later to avoid overwriting stats of a disconnected player
		g_bAuthorizeNextRound[id] = true;
	}
	else
	{
		get_user_authid(id, g_sSteamID[id], charsmax(g_sSteamID[]));
	}
}

public client_disconnected(id)
{
	if (g_bSpawnedThisRound[id])
	{
		if (g_bAlive[id] && !g_bRoundHasEnded && g_iTeam[id] == CS_TEAM_T)
		{
			g_fSurvivedTime[id] = (!g_bFreezeTime ? (get_gametime() - g_fRoundStart) : 0.0);
		}
		
		cacheUsername(id);
	}
	
	g_bAlive[id] = false;
	g_bAuthorizeNextRound[id] = false;
}

public HNS_Mix_Started(const iRoundsToPlay)
{
	g_iRoundsToPlay = iRoundsToPlay;
	
	TrieClear(g_tStats);
	TrieClear(g_tUsernameLookup);
	
	ArrayClear(g_aSeekerTop);
	ArrayClear(g_aHiderTop);
}

public HNS_Mix_Ended()
{
	g_iRoundsToPlay = 0;
	g_iCompletedRounds = 0;
}

public HNS_Mix_RoundCompleted(const CsTeams:iWinner)
{
	g_bRoundHasEnded = true;
	g_iCompletedRounds++;
	
	if (iWinner == CS_TEAM_T)
	{
		new Float:fActualRoundTime = (!g_bFreezeTime ? (get_gametime() - g_fRoundStart) : 0.0);

		for (new i = 1; i <= MAX_PLAYERS; i++)
		{
			if (!g_bSpawnedThisRound[i] || g_iTeam[i] != CS_TEAM_T)
			{
				continue;
			}

			if (g_bAlive[i])
			{
				g_fSurvivedTime[i] = g_fRoundTime;
			}	
			else
			{
				g_fSurvivedTime[i] += (g_fRoundTime - fActualRoundTime);
			}
		}
	}
	
	commitRoundStats();
}

public eventNewRound()
{
	resetRoundStats();
	
	g_bFreezeTime = true;
	g_bRoundHasEnded = false;
}

public eventRoundStart()
{
	g_bFreezeTime = false;
	g_bRoundHasEnded = false;
	
	g_fRoundStart = get_gametime();
	g_fRoundTime = floatclamp(get_cvar_float("mp_roundtime"), 1.0, 9.0) * 60.0;
}

public fwdHamSpawn(id)
{
	if (!is_user_alive(id))
	{
		return HAM_IGNORED;
	}
	
	g_bAlive[id] = true;
	g_iTeam[id] = cs_get_user_team(id);
	g_bSpawnedThisRound[id] = g_iRoundsToPlay > 0;
	
	return HAM_IGNORED;
}

public fwdHamKilled(iVictim, iAttacker, bShouldGib)
{
	g_bAlive[iVictim] = false;
	
	if (!g_bRoundHasEnded && g_iTeam[iVictim] == CS_TEAM_T)
	{
		g_fSurvivedTime[iVictim] = !g_bFreezeTime ? (get_gametime() - g_fRoundStart) : 0.0;
		
		static id;
		
		for (new i = 0; i < ASSIST_SLOTS; i++)
		{
			id = g_iAttackers[iVictim][i];
			
			if (!id)
			{
				return HAM_IGNORED;
			}
			else if (id == iAttacker)
			{
				g_iKills[iAttacker]++;
			}
			else
			{
				g_iAssists[id]++;
			}
		}
	}
	
	return HAM_IGNORED;
}

public fwdHamTakeDamage(iVictim, inflictor, iAttacker, Float:fDamage, damageBits)
{
	if (iAttacker < 1 || iAttacker > MAX_PLAYERS || fDamage < 1.0 || g_bRoundHasEnded)
	{
		return HAM_IGNORED;
	}
	
	new i;
	
	for (i = 0; i < ASSIST_SLOTS; i++)
	{
		if (g_iAttackers[iVictim][i] == iAttacker)
		{
			if (i < ASSIST_SLOTS - 1 && g_iAttackers[iVictim][i + 1])
			{
				g_iAttackers[iVictim][i] = g_iAttackers[iVictim][i + 1];
				g_iAttackers[iVictim][i + 1] = iAttacker;
			}
			else
			{
				return HAM_IGNORED;
			}
		}
		else if (!g_iAttackers[iVictim][i])
		{
			g_iAttackers[iVictim][i] = iAttacker;
			return HAM_IGNORED;
		}
	}
	
	for (i = 1; i < ASSIST_SLOTS; i++)
	{
		g_iAttackers[iVictim][i - 1] = g_iAttackers[iVictim][i];
	}
	
	g_iAttackers[iVictim][ASSIST_SLOTS - 1] = iAttacker;
	
	return HAM_IGNORED;
}

resetRoundStats()
{
	for (new i = 1; i <= MAX_PLAYERS; i++)
	{
		g_bSpawnedThisRound[i] = false;
		g_iKills[i] = 0;
		g_iAssists[i] = 0;
		g_fSurvivedTime[i] = 0.0;
		
		if (g_bAuthorizeNextRound[i])
		{
			g_bAuthorizeNextRound[i] = false;
			get_user_authid(i, g_sSteamID[i], charsmax(g_sSteamID[]));
		}
		
		for (new j = 0; j < ASSIST_SLOTS; j++)
		{
			g_iAttackers[i][j] = 0;
		}
	}
}

commitRoundStats()
{
	static eStats[ePlayerStats], szTrieKey[STEAMID_LEN];
	
	for (new i = 1; i <= MAX_PLAYERS; i++)
	{
		if (!g_bSpawnedThisRound[i])
		{
			continue;
		}
		
		szTrieKey = g_sSteamID[i];
		
		if (!TrieKeyExists(g_tStats, szTrieKey))
		{
			new eDefaultStats[ePlayerStats];
			TrieSetArray(g_tStats, szTrieKey, eDefaultStats, ePlayerStats);
			ArrayPushString(g_aSeekerTop, szTrieKey);
			ArrayPushString(g_aHiderTop, szTrieKey);
			
			cacheUsername(i);
		}

		TrieGetArray(g_tStats, szTrieKey, eStats, ePlayerStats);
		
		eStats[Kills] += g_iKills[i];
		eStats[Assists] += g_iAssists[i];
		eStats[SurvTime] += g_fSurvivedTime[i];

		if (g_iTeam[i] == CS_TEAM_T)
		{
			eStats[TRounds]++;
		}
		else
		{
			eStats[CTRounds]++;
		}

		TrieSetArray(g_tStats, szTrieKey, eStats, ePlayerStats);
	}
	
	constructTopLists();
}

constructTopLists()
{
	ArraySort(g_aSeekerTop, "compareSeekerStats");
	ArraySort(g_aHiderTop, "compareHiderStats");
	
	static eStats[ePlayerStats], szTrieKey[STEAMID_LEN];
	
	new iPlayerCount = ArraySize(g_aSeekerTop);
	new iLastSeekerRank = 1, iLastHiderRank = 1;
	
	for (new i = 0; i < iPlayerCount; i++)
	{
		if (i > 0)
		{
			if (compareSeekerStats(g_aSeekerTop, i - 1, i))
			{
				iLastSeekerRank = i + 1;
			}
			else
			{
				ArrayGetString(g_aSeekerTop, i - 1, szTrieKey, charsmax(szTrieKey));
				TrieGetArray(g_tStats, szTrieKey, eStats, ePlayerStats);
				
				eStats[TiedCTRank] = true;
				TrieSetArray(g_tStats, szTrieKey, eStats, ePlayerStats);
			}
			if (compareHiderStats(g_aHiderTop, i - 1, i))
			{
				iLastHiderRank = i + 1;
			}
			else
			{
				ArrayGetString(g_aHiderTop, i - 1, szTrieKey, charsmax(szTrieKey));
				TrieGetArray(g_tStats, szTrieKey, eStats, ePlayerStats);
				
				eStats[TiedTRank] = true;
				TrieSetArray(g_tStats, szTrieKey, eStats, ePlayerStats);
			}
		}
		
		ArrayGetString(g_aSeekerTop, i, szTrieKey, charsmax(szTrieKey));
		TrieGetArray(g_tStats, szTrieKey, eStats, ePlayerStats);
		
		eStats[CTRank] = eStats[CTRounds] > 0 ? iLastSeekerRank : 0;
		eStats[TiedCTRank] = i > 0 && i >= iLastSeekerRank;
		TrieSetArray(g_tStats, szTrieKey, eStats, ePlayerStats);
		
		ArrayGetString(g_aHiderTop, i, szTrieKey, charsmax(szTrieKey));
		TrieGetArray(g_tStats, szTrieKey, eStats, ePlayerStats);
		
		eStats[TRank] = eStats[TRounds] > 0 ? iLastHiderRank : 0;
		eStats[TiedTRank] = i > 0 && i >= iLastHiderRank;
		TrieSetArray(g_tStats, szTrieKey, eStats, ePlayerStats);
	}
}

cacheUsername(const id)
{
	static szUsername[USERNAME_LEN];
	get_user_name(id, szUsername, charsmax(szUsername));
	TrieSetString(g_tUsernameLookup, g_sSteamID[id], szUsername);
}

public cmdPersonalStats(const id)
{
	static szTrieKey[STEAMID_LEN], eStats[ePlayerStats], szHiderText[33], szSeekerText[33];
	szTrieKey = g_sSteamID[id];
	
	if (g_bAuthorizeNextRound[id] || !TrieKeyExists(g_tStats, szTrieKey))
	{
		client_print_color(id, print_team_grey, "%s There exists no saved stats for you yet.", g_sPluginPrefix);
		return PLUGIN_HANDLED;
	}
	
	TrieGetArray(g_tStats, szTrieKey, eStats, ePlayerStats);
	
	if (eStats[TRounds] > 0)
	{
		formatex(szHiderText, charsmax(szHiderText), "^3%s ^1(Rank ^4%s%d^1)", survivalTimeAsText(eStats[SurvTime]), (eStats[TiedTRank] ? "T" : ""), eStats[TRank]);
	}
	else
	{
		formatex(szHiderText, charsmax(szHiderText), "^3N/A^1");
	}
	
	if (eStats[CTRounds] > 0)
	{
		formatex(szSeekerText, charsmax(szHiderText), "^3%d^1/^3%d ^1(Rank ^4%s%d^1)", eStats[Kills], eStats[Assists], (eStats[TiedCTRank] ? "T" : ""), eStats[CTRank]);
	}
	else
	{
		formatex(szSeekerText, charsmax(szHiderText), "^3N/A^1");
	}
	
	client_print_color(id, print_team_grey, "%s Survived time: %s | Kills/Assists: %s", g_sPluginPrefix, szHiderText, szSeekerText);
	
	return PLUGIN_HANDLED;
}

public cmdMixTop(const id)
{
	static szTrieKey[STEAMID_LEN], eStats[ePlayerStats], szUsername[USERNAME_LEN];
	
	new iArraySize = ArraySize(g_aHiderTop);
	client_print(id, print_console, "===== Top %d Hiders (Survived time) =====", g_iTopListLength);
	
	for (new i = 0; i < g_iTopListLength; i++)
	{
		if (i >= iArraySize)
		{
			client_print(id, print_console, "%d. - N/A", i + 1);
			continue;
		}
		
		ArrayGetString(g_aHiderTop, i, szTrieKey, charsmax(szTrieKey));
		TrieGetString(g_tUsernameLookup, szTrieKey, szUsername, charsmax(szUsername));
		TrieGetArray(g_tStats, szTrieKey, eStats, ePlayerStats);
		
		if (eStats[TRounds] == 0)
		{
			client_print(id, print_console, "%d. - N/A", i + 1);
		}
		else
		{
			client_print(id, print_console, "%s%d. - %s - %s", (eStats[TiedTRank] ? "T" : ""), eStats[TRank], szUsername, survivalTimeAsText(eStats[SurvTime]));
		}
	}
	
	iArraySize = ArraySize(g_aSeekerTop);
	client_print(id, print_console, "===== Top %d Seekers (Kills/Assists) =====", g_iTopListLength);
	
	for (new i = 0; i < g_iTopListLength; i++)
	{
		if (i >= iArraySize)
		{
			client_print(id, print_console, "%d. - N/A", i + 1);
			continue;
		}
		
		ArrayGetString(g_aSeekerTop, i, szTrieKey, charsmax(szTrieKey));
		TrieGetString(g_tUsernameLookup, szTrieKey, szUsername, charsmax(szUsername));
		TrieGetArray(g_tStats, szTrieKey, eStats, ePlayerStats);
		
		if (eStats[CTRounds] == 0)
		{
			client_print(id, print_console, "%d. - N/A", i + 1);
		}
		else
		{
			client_print(id, print_console, "%s%d. - %s - %d/%d", (eStats[TiedCTRank] ? "T" : ""), eStats[CTRank], szUsername, eStats[Kills], eStats[Assists]);
		}
	}
	
	client_print_color(id, print_team_grey, "%s Top list has been printed in your console.", g_sPluginPrefix);
	
	return PLUGIN_HANDLED;
}

survivalTimeAsText(const Float:flTime)
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

public compareSeekerStats(Array:array, item1, item2)
{
	static eStats1[ePlayerStats], eStats2[ePlayerStats];
	static szTrieKey[STEAMID_LEN];
	
	ArrayGetString(array, item1, szTrieKey, charsmax(szTrieKey));
	TrieGetArray(g_tStats, szTrieKey, eStats1, ePlayerStats);
	
	ArrayGetString(array, item2, szTrieKey, charsmax(szTrieKey));
	TrieGetArray(g_tStats, szTrieKey, eStats2, ePlayerStats);
	
	new iKills1 = eStats1[Kills];
	new iKills2 = eStats2[Kills];
	
	new iKA1 = iKills1 + eStats1[Assists];
	new iKA2 = iKills2 + eStats2[Assists];
	
	if (iKA1 > iKA2)
	{
		return -1;
	}
	if (iKA1 < iKA2)
	{
		return 1;
	}
	
	if (iKills1 > iKills2)
	{
		return -1;
	}
	if (iKills1 < iKills2)
	{
		return 1;
	}
	
	new iRoundsPlayed1 = eStats1[CTRounds];
	new iRoundsPlayed2 = eStats2[CTRounds];
	
	if (iRoundsPlayed1 > 0 && iRoundsPlayed2 == 0)
	{
		return -1;
	}
	if (iRoundsPlayed1 == 0 && iRoundsPlayed2 > 0)
	{
		return 1;
	}
	
	if (iRoundsPlayed1 < iRoundsPlayed2)
	{
		return -1;
	}
	if (iRoundsPlayed1 > iRoundsPlayed2)
	{
		return 1;
	}
	
	return 0;
}

public compareHiderStats(Array:array, item1, item2)
{
	static eStats1[ePlayerStats], eStats2[ePlayerStats];
	static szTrieKey[STEAMID_LEN];
	
	ArrayGetString(array, item1, szTrieKey, charsmax(szTrieKey));
	TrieGetArray(g_tStats, szTrieKey, eStats1, ePlayerStats);
	
	ArrayGetString(array, item2, szTrieKey, charsmax(szTrieKey));
	TrieGetArray(g_tStats, szTrieKey, eStats2, ePlayerStats);

	new Float:flSurvivalTime1 = eStats1[SurvTime];
	new Float:flSurvivalTime2 = eStats2[SurvTime];
	
	if (flSurvivalTime1 > flSurvivalTime2)
	{
		return -1;
	}
	
	if (flSurvivalTime1 < flSurvivalTime2)
	{
		return 1;
	}
	
	new iRoundsPlayed1 = eStats1[TRounds];
	new iRoundsPlayed2 = eStats2[TRounds];
	
	if (iRoundsPlayed1 > 0 && iRoundsPlayed2 == 0)
	{
		return -1;
	}
	if (iRoundsPlayed1 == 0 && iRoundsPlayed2 > 0)
	{
		return 1;
	}
	
	if (iRoundsPlayed1 < iRoundsPlayed2)
	{
		return -1;
	}
	if (iRoundsPlayed1 > iRoundsPlayed2)
	{
		return 1;
	}
	
	return 0;
}