#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <hamsandwich>

#pragma semicolon			1

#define PLUGIN_NAME			"HNS_MixStats"
#define PLUGIN_VERSION		"1.0.0"
#define PLUGIN_AUTHOR		"Reavap"

#define STEAMID_LEN			33
#define ASSIST_SLOTS		3

new g_CompletedRounds;
new g_RoundsToPlay;

new bool:g_FreezeTime;
new bool:g_RoundHasEnded;

new Float:g_RoundStart;
new Float:g_RoundTime;

new CsTeams:g_Team[MAX_PLAYERS + 1];
new bool:g_Alive[MAX_PLAYERS + 1];

new bool:g_SpawnedThisRound[MAX_PLAYERS + 1];
new bool:g_AuthorizeNextRound[MAX_PLAYERS + 1];

new g_Kills[MAX_PLAYERS + 1];
new g_Assists[MAX_PLAYERS + 1];
new Float:g_SurvivedTime[MAX_PLAYERS + 1];

new g_Attackers[MAX_PLAYERS + 1][ASSIST_SLOTS];
new g_SteamID[MAX_PLAYERS + 1][STEAMID_LEN];

enum _:MixPlayerStats
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

new Trie:g_Stats;
new Trie:g_UsernameLookup;

new Array:g_SeekerToplist;
new Array:g_HiderToplist;

new const g_ToplistLength = 5;

public plugin_init()
{
	register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
	register_cvar(PLUGIN_NAME, PLUGIN_VERSION, FCVAR_SERVER|FCVAR_SPONLY);
	
	new playerEntityClass[] = "player";
	RegisterHam(Ham_Spawn, playerEntityClass, "fwdHamSpawn", 1);
	RegisterHam(Ham_Killed, playerEntityClass, "fwdHamKilled", 0);
	RegisterHam(Ham_TakeDamage, playerEntityClass, "fwdHamTakeDamage", 0);
	
	register_event("HLTV", "eventNewRound", "a", "1=0", "2=0");
	register_logevent("eventRoundStart", 2, "1=Round_Start");
	
	register_clcmd("say /ps", "cmdPersonalStats");
	register_clcmd("say /mixtop", "cmdMixTop");
	
	g_Stats = TrieCreate();
	g_UsernameLookup = TrieCreate();
	g_SeekerToplist = ArrayCreate(STEAMID_LEN);
	g_HiderToplist = ArrayCreate(STEAMID_LEN);
}

public client_authorized(id)
{
	if (g_SpawnedThisRound[id])
	{
		// Perform authorization later to avoid overwriting stats of a disconnected player
		g_AuthorizeNextRound[id] = true;
	}
	else
	{
		get_user_authid(id, g_SteamID[id], charsmax(g_SteamID[]));
	}
}

public client_disconnected(id)
{
	if (g_SpawnedThisRound[id])
	{
		if (g_Alive[id] && !g_RoundHasEnded && g_Team[id] == CS_TEAM_T)
		{
			g_SurvivedTime[id] = (!g_FreezeTime ? (get_gametime() - g_RoundStart) : 0.0);
		}
		
		cacheUsername(id);
	}
	
	g_Alive[id] = false;
	g_AuthorizeNextRound[id] = false;
}

public HNS_Mix_Started(const roundsToPlay)
{
	g_RoundsToPlay = roundsToPlay;
	
	TrieClear(g_Stats);
	TrieClear(g_UsernameLookup);
	
	ArrayClear(g_SeekerToplist);
	ArrayClear(g_HiderToplist);
}

public HNS_Mix_Ended()
{
	g_RoundsToPlay = 0;
	g_CompletedRounds = 0;
}

public HNS_Mix_RoundCompleted(const CsTeams:winner)
{
	g_RoundHasEnded = true;
	g_CompletedRounds++;
	
	if (winner == CS_TEAM_T)
	{
		new Float:actualRoundTime = (!g_FreezeTime ? (get_gametime() - g_RoundStart) : 0.0);

		for (new i = 1; i <= MaxClients; i++)
		{
			if (!g_SpawnedThisRound[i] || g_Team[i] != CS_TEAM_T)
			{
				continue;
			}

			if (g_Alive[i])
			{
				g_SurvivedTime[i] = g_RoundTime;
			}	
			else
			{
				g_SurvivedTime[i] += (g_RoundTime - actualRoundTime);
			}
		}
	}
	
	commitRoundStats();
}

public eventNewRound()
{
	resetRoundStats();
	
	g_FreezeTime = true;
	g_RoundHasEnded = false;
}

public eventRoundStart()
{
	g_FreezeTime = false;
	g_RoundHasEnded = false;
	
	g_RoundStart = get_gametime();
	g_RoundTime = floatclamp(get_cvar_float("mp_roundtime"), 1.0, 9.0) * 60.0;
}

public fwdHamSpawn(id)
{
	if (!is_user_alive(id))
	{
		return HAM_IGNORED;
	}
	
	g_Alive[id] = true;
	g_Team[id] = cs_get_user_team(id);
	g_SpawnedThisRound[id] = g_RoundsToPlay > 0;
	
	return HAM_IGNORED;
}

public fwdHamKilled(victim, attacker, shouldGib)
{
	g_Alive[victim] = false;
	
	if (!g_RoundHasEnded && g_Team[victim] == CS_TEAM_T)
	{
		g_SurvivedTime[victim] = !g_FreezeTime ? (get_gametime() - g_RoundStart) : 0.0;
		
		new id;
		
		for (new i = 0; i < ASSIST_SLOTS; i++)
		{
			id = g_Attackers[victim][i];
			
			if (!id)
			{
				return HAM_IGNORED;
			}
			else if (id == attacker)
			{
				g_Kills[attacker]++;
			}
			else
			{
				g_Assists[id]++;
			}
		}
	}
	
	return HAM_IGNORED;
}

public fwdHamTakeDamage(victim, inflictor, attacker, Float:damage, damageBits)
{
	if (attacker < 1 || attacker > MaxClients || damage < 1.0 || g_RoundHasEnded)
	{
		return HAM_IGNORED;
	}
	
	new i;
	
	for (i = 0; i < ASSIST_SLOTS; i++)
	{
		if (g_Attackers[victim][i] == attacker)
		{
			if (i < ASSIST_SLOTS - 1 && g_Attackers[victim][i + 1])
			{
				g_Attackers[victim][i] = g_Attackers[victim][i + 1];
				g_Attackers[victim][i + 1] = attacker;
			}
			else
			{
				return HAM_IGNORED;
			}
		}
		else if (!g_Attackers[victim][i])
		{
			g_Attackers[victim][i] = attacker;
			return HAM_IGNORED;
		}
	}
	
	for (i = 1; i < ASSIST_SLOTS; i++)
	{
		g_Attackers[victim][i - 1] = g_Attackers[victim][i];
	}
	
	g_Attackers[victim][ASSIST_SLOTS - 1] = attacker;
	
	return HAM_IGNORED;
}

resetRoundStats()
{
	new j;
	
	for (new i = 1; i <= MaxClients; i++)
	{
		g_SpawnedThisRound[i] = false;
		g_Kills[i] = 0;
		g_Assists[i] = 0;
		g_SurvivedTime[i] = 0.0;
		
		if (g_AuthorizeNextRound[i])
		{
			g_AuthorizeNextRound[i] = false;
			get_user_authid(i, g_SteamID[i], charsmax(g_SteamID[]));
		}
		
		for (j = 0; j < ASSIST_SLOTS; j++)
		{
			g_Attackers[i][j] = 0;
		}
	}
}

commitRoundStats()
{
	static stats[MixPlayerStats], trieKey[STEAMID_LEN];
	
	for (new i = 1; i <= MaxClients; i++)
	{
		if (!g_SpawnedThisRound[i])
		{
			continue;
		}
		
		trieKey = g_SteamID[i];
		
		if (!TrieKeyExists(g_Stats, trieKey))
		{
			new defaultStats[MixPlayerStats];
			TrieSetArray(g_Stats, trieKey, defaultStats, MixPlayerStats);
			ArrayPushString(g_SeekerToplist, trieKey);
			ArrayPushString(g_HiderToplist, trieKey);
			
			cacheUsername(i);
		}

		TrieGetArray(g_Stats, trieKey, stats, MixPlayerStats);
		
		stats[Kills] += g_Kills[i];
		stats[Assists] += g_Assists[i];
		stats[SurvTime] += g_SurvivedTime[i];

		if (g_Team[i] == CS_TEAM_T)
		{
			stats[TRounds]++;
		}
		else
		{
			stats[CTRounds]++;
		}

		TrieSetArray(g_Stats, trieKey, stats, MixPlayerStats);
	}
	
	constructTopLists();
}

constructTopLists()
{
	ArraySort(g_SeekerToplist, "compareSeekerStats");
	ArraySort(g_HiderToplist, "compareHiderStats");
	
	static stats[MixPlayerStats], trieKey[STEAMID_LEN];
	
	new playerCount = ArraySize(g_SeekerToplist);
	new seekerRank = 1, hiderRank = 1;
	
	for (new i = 0; i < playerCount; i++)
	{
		if (i > 0)
		{
			if (compareSeekerStats(g_SeekerToplist, i - 1, i))
			{
				seekerRank = i + 1;
			}
			else
			{
				ArrayGetString(g_SeekerToplist, i - 1, trieKey, charsmax(trieKey));
				TrieGetArray(g_Stats, trieKey, stats, MixPlayerStats);
				
				stats[TiedCTRank] = true;
				TrieSetArray(g_Stats, trieKey, stats, MixPlayerStats);
			}
			if (compareHiderStats(g_HiderToplist, i - 1, i))
			{
				hiderRank = i + 1;
			}
			else
			{
				ArrayGetString(g_HiderToplist, i - 1, trieKey, charsmax(trieKey));
				TrieGetArray(g_Stats, trieKey, stats, MixPlayerStats);
				
				stats[TiedTRank] = true;
				TrieSetArray(g_Stats, trieKey, stats, MixPlayerStats);
			}
		}
		
		ArrayGetString(g_SeekerToplist, i, trieKey, charsmax(trieKey));
		TrieGetArray(g_Stats, trieKey, stats, MixPlayerStats);
		
		stats[CTRank] = stats[CTRounds] > 0 ? seekerRank : 0;
		stats[TiedCTRank] = i > 0 && i >= seekerRank;
		TrieSetArray(g_Stats, trieKey, stats, MixPlayerStats);
		
		ArrayGetString(g_HiderToplist, i, trieKey, charsmax(trieKey));
		TrieGetArray(g_Stats, trieKey, stats, MixPlayerStats);
		
		stats[TRank] = stats[TRounds] > 0 ? hiderRank : 0;
		stats[TiedTRank] = i > 0 && i >= hiderRank;
		TrieSetArray(g_Stats, trieKey, stats, MixPlayerStats);
	}
}

cacheUsername(const id)
{
	static username[MAX_NAME_LENGTH ];
	get_user_name(id, username, charsmax(username));
	TrieSetString(g_UsernameLookup, g_SteamID[id], username);
}

public cmdPersonalStats(const id)
{
	static trieKey[STEAMID_LEN], stats[MixPlayerStats], hiderText[33], seekerText[33];
	trieKey = g_SteamID[id];
	
	if (g_AuthorizeNextRound[id] || !TrieKeyExists(g_Stats, trieKey))
	{
		client_print_color(id, print_team_grey, "There exists no saved stats for you yet");
		return PLUGIN_HANDLED;
	}
	
	TrieGetArray(g_Stats, trieKey, stats, MixPlayerStats);
	
	if (stats[TRounds] > 0)
	{
		formatex(hiderText, charsmax(hiderText), "^3%s ^1(Rank ^4%s%d^1)", survivalTimeAsText(stats[SurvTime]), (stats[TiedTRank] ? "T" : ""), stats[TRank]);
	}
	else
	{
		formatex(hiderText, charsmax(hiderText), "^3N/A^1");
	}
	
	if (stats[CTRounds] > 0)
	{
		formatex(seekerText, charsmax(hiderText), "^3%d^1/^3%d ^1(Rank ^4%s%d^1)", stats[Kills], stats[Assists], (stats[TiedCTRank] ? "T" : ""), stats[CTRank]);
	}
	else
	{
		formatex(seekerText, charsmax(hiderText), "^3N/A^1");
	}
	
	client_print_color(id, print_team_grey, "Survived time: %s | Kills/Assists: %s", hiderText, seekerText);
	
	return PLUGIN_HANDLED;
}

public cmdMixTop(const id)
{
	static trieKey[STEAMID_LEN], stats[MixPlayerStats], username[MAX_NAME_LENGTH ];
	
	new iArraySize = ArraySize(g_HiderToplist);
	client_print(id, print_console, "===== Top %d Hiders (Survived time) =====", g_ToplistLength);
	
	for (new i = 0; i < g_ToplistLength; i++)
	{
		if (i >= iArraySize)
		{
			client_print(id, print_console, "%d. - N/A", i + 1);
			continue;
		}
		
		ArrayGetString(g_HiderToplist, i, trieKey, charsmax(trieKey));
		TrieGetString(g_UsernameLookup, trieKey, username, charsmax(username));
		TrieGetArray(g_Stats, trieKey, stats, MixPlayerStats);
		
		if (stats[TRounds] == 0)
		{
			client_print(id, print_console, "%d. - N/A", i + 1);
		}
		else
		{
			client_print(id, print_console, "%s%d. - %s - %s", (stats[TiedTRank] ? "T" : ""), stats[TRank], username, survivalTimeAsText(stats[SurvTime]));
		}
	}
	
	iArraySize = ArraySize(g_SeekerToplist);
	client_print(id, print_console, "===== Top %d Seekers (Kills/Assists) =====", g_ToplistLength);
	
	for (new i = 0; i < g_ToplistLength; i++)
	{
		if (i >= iArraySize)
		{
			client_print(id, print_console, "%d. - N/A", i + 1);
			continue;
		}
		
		ArrayGetString(g_SeekerToplist, i, trieKey, charsmax(trieKey));
		TrieGetString(g_UsernameLookup, trieKey, username, charsmax(username));
		TrieGetArray(g_Stats, trieKey, stats, MixPlayerStats);
		
		if (stats[CTRounds] == 0)
		{
			client_print(id, print_console, "%d. - N/A", i + 1);
		}
		else
		{
			client_print(id, print_console, "%s%d. - %s - %d/%d", (stats[TiedCTRank] ? "T" : ""), stats[CTRank], username, stats[Kills], stats[Assists]);
		}
	}
	
	client_print_color(id, print_team_grey, "Top list has been printed in your console");
	
	return PLUGIN_HANDLED;
}

survivalTimeAsText(const Float:time)
{
	static timeString[10];
	new totalSeconds = floatround(time, floatround_floor);

	new minutes = totalSeconds / 60;
	new seconds = totalSeconds - minutes * 60;
	new milliseconds = floatround((time - totalSeconds) * 1000.0, floatround_floor);
	
	formatex(timeString, charsmax(timeString), "%s%d:%s%d.%s%s%d",
	(minutes < 10 ? "0" : ""), minutes,
	(seconds < 10 ? "0" : ""), seconds,
	(milliseconds < 100 ? "0" : ""),
	(milliseconds < 10 ? "0" : ""), milliseconds);
	
	return timeString;
}

public compareSeekerStats(Array:array, item1, item2)
{
	static stats1[MixPlayerStats], stats2[MixPlayerStats];
	static trieKey[STEAMID_LEN];
	
	ArrayGetString(array, item1, trieKey, charsmax(trieKey));
	TrieGetArray(g_Stats, trieKey, stats1, MixPlayerStats);
	
	ArrayGetString(array, item2, trieKey, charsmax(trieKey));
	TrieGetArray(g_Stats, trieKey, stats2, MixPlayerStats);
	
	new kills1 = stats1[Kills];
	new kills2 = stats2[Kills];
	
	new killAssists1 = kills1 + stats1[Assists];
	new killAssists2 = kills2 + stats2[Assists];
	
	if (killAssists1 > killAssists2)
	{
		return -1;
	}
	if (killAssists1 < killAssists2)
	{
		return 1;
	}
	
	if (kills1 > kills2)
	{
		return -1;
	}
	if (kills1 < kills2)
	{
		return 1;
	}
	
	new roundsPlayed1 = stats1[CTRounds];
	new roundsPlayed2 = stats2[CTRounds];
	
	if (roundsPlayed1 > 0 && roundsPlayed2 == 0)
	{
		return -1;
	}
	if (roundsPlayed1 == 0 && roundsPlayed2 > 0)
	{
		return 1;
	}
	
	if (roundsPlayed1 < roundsPlayed2)
	{
		return -1;
	}
	if (roundsPlayed1 > roundsPlayed2)
	{
		return 1;
	}
	
	return 0;
}

public compareHiderStats(Array:array, item1, item2)
{
	static stats1[MixPlayerStats], stats2[MixPlayerStats];
	static trieKey[STEAMID_LEN];
	
	ArrayGetString(array, item1, trieKey, charsmax(trieKey));
	TrieGetArray(g_Stats, trieKey, stats1, MixPlayerStats);
	
	ArrayGetString(array, item2, trieKey, charsmax(trieKey));
	TrieGetArray(g_Stats, trieKey, stats2, MixPlayerStats);

	new Float:survivalTime1 = stats1[SurvTime];
	new Float:survivalTime2 = stats2[SurvTime];
	
	if (survivalTime1 > survivalTime2)
	{
		return -1;
	}
	
	if (survivalTime1 < survivalTime2)
	{
		return 1;
	}
	
	new roundsPlayed1 = stats1[TRounds];
	new roundsPlayed2 = stats2[TRounds];
	
	if (roundsPlayed1 > 0 && roundsPlayed2 == 0)
	{
		return -1;
	}
	if (roundsPlayed1 == 0 && roundsPlayed2 > 0)
	{
		return 1;
	}
	
	if (roundsPlayed1 < roundsPlayed2)
	{
		return -1;
	}
	if (roundsPlayed1 > roundsPlayed2)
	{
		return 1;
	}
	
	return 0;
}