#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <engine>
#include <fakemeta>
#include <fun>
#include <hamsandwich>
#include <hns_main>

#pragma semicolon			1

#define PLUGIN_NAME			"HNS_Main"
#define PLUGIN_VERSION		"1.0.4"
#define PLUGIN_AUTHOR		"Reavap"

#define TASKID_BREAKABLES	1000
#define TASKID_HIDETIMER	2000

// CVars
new hns_flashbangs;
new hns_smokegrenades;
new hns_noflash;
new hns_hidetime;
new hns_semiclip;
new hns_removebreakables;
new hns_footsteps;
new mp_freezetime;

// Messages
new g_StatusTextMessageId;
new g_StatusValueMessageId;

// Forwards
new g_iHnsStateChangedForward;

// Players states
new CsTeams:g_Team[MAX_PLAYERS + 1];
new bool:g_Alive[MAX_PLAYERS + 1];

new bool:g_HideKnife[MAX_PLAYERS + 1];
new bool:g_HideTimeCountDownSound[MAX_PLAYERS + 1];

new bool:plrSolid[MAX_PLAYERS + 1];
new bool:plrRestore[MAX_PLAYERS + 1];

new Float:g_FlashTime[MAX_PLAYERS + 1];
new g_AimingAtPlayer[MAX_PLAYERS + 1];

// Constants
new const g_EntityClassesToRemove[][] =
{
	"func_bomb_target",
	"info_bomb_target",
	"func_hostage_rescue",
	"info_hostage_rescue",
	"info_vip_start",
	"func_vip_safetyzone",
	"func_escapezone",
	"func_buyzone",
	"armoury_entity",
	"hostage_entity",
	"monster_scientist"
};

new const g_ClassBasePlayerWeapon[] = "CBasePlayerWeapon";
new const g_MemberNextPrimaryAttack[] = "m_flNextPrimaryAttack";
new const g_MemberNextSecondaryAttack[] = "m_flNextSecondaryAttack";

new const g_WeaponKnife[] = "weapon_knife";
new const g_BreakableClass[] = "func_breakable";
new const g_KnifeModel_v[] = "models/v_knife.mdl";
new const g_EmptyString[] = "";

// HNS States
new g_HostageEntity;
new HnsPluginStates:g_PluginState;
new g_HideTimeCounter;

new Trie:g_RoundEndMessageLookup;
new g_SpawnEntityForward;

public plugin_natives()
{
	register_library("hns_main");
	
	register_native("hns_change_state", "nativeChangeState", 0);
	register_native("hns_switch_teams", "nativeSwitchTeams", 0);
	
	register_native("hns_set_hideknife", "nativeSetHideKnife", 0);
	register_native("hns_set_hidetimesound", "nativeSetHideTimeSound", 0);
}
	
public plugin_precache() 
{
	if (!cs_create_entity("func_buyzone"))
	{
		set_fail_state("Unable to create func_buyzone entity");
		return;
	}

	new const infoMapParametersClass[] = "info_map_parameters";
	new infoMapParamsEntity = cs_find_ent_by_class(MaxClients, infoMapParametersClass);
	
	if (!infoMapParamsEntity)
	{
		infoMapParamsEntity = cs_create_entity(infoMapParametersClass);
		
		if (!pev_valid(infoMapParamsEntity))
		{
			set_fail_state("Unable to create info_map_parameters entity");
			return;
		}
		else
		{
			DispatchSpawn(infoMapParamsEntity);
		}
	}
	
	if (infoMapParamsEntity)
	{
		DispatchKeyValue(infoMapParamsEntity, "buying", "3");
	}
	
	create_hostage();
	
	g_SpawnEntityForward = register_forward(FM_Spawn, "fwdSpawn", 1);
}

public plugin_init()
{
	register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
	register_cvar(PLUGIN_NAME, PLUGIN_VERSION, FCVAR_SERVER|FCVAR_SPONLY);
	
	if (g_SpawnEntityForward)
	{
		unregister_forward(FM_Spawn, g_SpawnEntityForward, 1);
		g_SpawnEntityForward = 0;
	}
	
	g_StatusTextMessageId = get_user_msgid("StatusText");
	g_StatusValueMessageId = get_user_msgid("StatusValue");
	
	register_message(get_user_msgid("ScreenFade"), "messageScreenFade");
	register_message(get_user_msgid("TextMsg"), "messageTextMsg");
	
	new const playerClass[] = "player";
	RegisterHam(Ham_Spawn, playerClass, "fwdHamSpawn", 1);
	RegisterHam(Ham_Killed, playerClass, "fwdHamKilled", 0);
	RegisterHam(Ham_CS_Player_ResetMaxSpeed, playerClass, "fwdHamResetMaxSpeed", 1);
	RegisterHam(Ham_Weapon_PrimaryAttack, g_WeaponKnife, "fwdHamKnifeSlash");
	RegisterHam(Ham_Item_Deploy, g_WeaponKnife, "fwdHamDeployKnife", 1);
	
	g_iHnsStateChangedForward = CreateMultiForward("HNS_StateChanged", ET_IGNORE, FP_CELL);
	
	register_forward(FM_EmitSound, "fwdEmitSound", 0);
	register_forward(FM_GetGameDescription, "fwdGetGameDescription", 0);
	register_forward(FM_ClientKill, "fwdClientKill", 0);
	register_forward(FM_SetClientMaxspeed, "fwdSetClientMaxSpeed", 1);
	
	register_event("TeamInfo", "eventTeamInfo", "a");
	register_event("HLTV", "eventNewRound", "a", "1=0", "2=0");
	register_logevent("eventRoundStart", 2, "1=Round_Start");
	register_logevent("eventCTwin", 6, "3=CTs_Win");
	
	hns_flashbangs = register_cvar("hns_flashbangs", "2");
	hns_smokegrenades = register_cvar("hns_smokegrenades", "1");
	hns_noflash = register_cvar("hns_noflash", "1");
	hns_hidetime = register_cvar("hns_hidetime", "10");
	hns_semiclip = register_cvar("hns_semiclip", "1");
	hns_removebreakables = register_cvar("hns_removebreakables", "0");
	hns_footsteps = register_cvar("hns_footsteps", "1");
	mp_freezetime = get_cvar_pointer("mp_freezetime");
	
	register_clcmd("say /knife", "cmdHideKnife");
	register_clcmd("say /showknife", "cmdHideKnife");
	register_clcmd("say /hideknife", "cmdHideKnife");
	register_clcmd("say /HNSTimerSound", "cmdHideTimeSound");
	
	setSemiclip();
	g_PluginState = HnsState_Public;
	
	new const hidersWinMessage[] = "Hiders Win";
	g_RoundEndMessageLookup = TrieCreate();
	TrieSetString(g_RoundEndMessageLookup, "#Hostages_Not_Rescued", hidersWinMessage);
	TrieSetString(g_RoundEndMessageLookup, "#Terrorists_Win", hidersWinMessage);
	TrieSetString(g_RoundEndMessageLookup, "#CTs_Win", "Seekers Win");

	if (g_iHnsStateChangedForward < 0)
	{
		g_iHnsStateChangedForward = 0;
		log_amx("State change forward could not be created.");
	}
}

public plugin_end()
{
	g_PluginState = HnsState_Public;
	setFreezeTime(0);
	
	DestroyForward(g_iHnsStateChangedForward);
	g_iHnsStateChangedForward = 0;
}

public client_disconnected(id)
{
	g_Alive[id] = false;
	g_Team[id] = CS_TEAM_UNASSIGNED;
	
	g_HideKnife[id] = false;
	g_HideTimeCountDownSound[id] = false;
}

public fwdSpawn(entity)
{
	if (!pev_valid(entity))
	{
		return FMRES_IGNORED;
	}

	static classname[32];
	pev(entity, pev_classname, classname, charsmax(classname));

	for (new i = 0; i < sizeof g_EntityClassesToRemove; i++) 		
	{
		if (equal(classname, g_EntityClassesToRemove[i]))			
		{
			engfunc(EngFunc_RemoveEntity, entity);
			break;
		}
	}

	return FMRES_IGNORED;
}

public fwdEmitSound(entity, channel, const sample[], Float:volume, Float:attenuation, flags, pitch)
{
	if (1 <= entity <= MaxClients && g_Team[entity] == CS_TEAM_T && g_PluginState != HnsState_Knife && sample[0] == 'w' && equali(sample, "weapons/knife_deploy1.wav"))
	{
		return FMRES_SUPERCEDE;
	}
	
	return FMRES_IGNORED;
}

public fwdGetGameDescription()
{
	forward_return(FMV_STRING, "Hide-N-Seek");
	return FMRES_SUPERCEDE;
}

public fwdClientKill(id)
{
	return FMRES_SUPERCEDE;
}

public fwdHamSpawn(id)
{
	if (!is_user_alive(id))
	{
		return HAM_IGNORED;
	}

	g_Alive[id] = true;
	g_Team[id] = cs_get_user_team(id);
	
	g_FlashTime[id] = 0.0;
	g_AimingAtPlayer[id] = -1;
	
	strip_user_weapons(id);
	give_item(id, g_WeaponKnife);
	
	if (g_Team[id] == CS_TEAM_T && g_PluginState != HnsState_Knife)
	{
		new const flashbangs = get_pcvar_num(hns_flashbangs);
		new const smokegrenades = get_pcvar_num(hns_smokegrenades);
		
		if (flashbangs > 0)
		{
			give_item(id, "weapon_flashbang");
			cs_set_user_bpammo(id, CSW_FLASHBANG, flashbangs);
		}
		if (smokegrenades > 0)
		{
			give_item(id, "weapon_smokegrenade");
			cs_set_user_bpammo(id, CSW_SMOKEGRENADE, smokegrenades);
		}
	}
	
	setUserFootsteps(id);
	
	return HAM_IGNORED;
}

setUserFootsteps(const id)
{
	set_user_footsteps(id, CsTeams:get_pcvar_num(hns_footsteps) & g_Team[id] && g_PluginState != HnsState_Knife);
}

public fwdHamKilled(victim, attacker, shouldGib)
{
	g_Alive[victim] = false;
	return HAM_IGNORED;
}

public fwdHamResetMaxSpeed(id)
{
	new Float:maxspeed;
	pev(id, pev_maxspeed, maxspeed);
	
	fwdSetClientMaxSpeed(id, maxspeed);
	
	return HAM_IGNORED;
}

public fwdSetClientMaxSpeed(id, Float:maxspeed)
{
	if (g_HideTimeCounter && maxspeed == 1.0 && g_Team[id] == CS_TEAM_T)
	{
		set_pev(id, pev_maxspeed, 250.0);
		return FMRES_HANDLED;
	}
	
	return FMRES_IGNORED;
}

public fwdHamKnifeSlash(id)
{
	ExecuteHam(Ham_Weapon_SecondaryAttack, id);
	return HAM_SUPERCEDE;
}

public fwdHamDeployKnife(entity)
{
	if (g_PluginState != HnsState_Knife)
	{
		new client = get_ent_data_entity(entity, "CBasePlayerItem", "m_pPlayer");
		updateKnifeWeapon(client, entity);
	}
	
	return HAM_IGNORED;
}

updateKnifeWeapon(const client, const weaponEntity)
{
	if (g_Team[client] == CS_TEAM_CT && get_ent_data_float(weaponEntity, g_ClassBasePlayerWeapon, g_MemberNextPrimaryAttack) > 60.0)
	{
		set_ent_data_float(weaponEntity, g_ClassBasePlayerWeapon, g_MemberNextPrimaryAttack, 0.0);
		set_ent_data_float(weaponEntity, g_ClassBasePlayerWeapon, g_MemberNextSecondaryAttack, 0.0);
	}
	else if (g_Team[client] == CS_TEAM_T)
	{
		if (g_HideKnife[client])
		{
			set_pev(client, pev_viewmodel2, g_EmptyString);
		}
		
		set_ent_data_float(weaponEntity, g_ClassBasePlayerWeapon, g_MemberNextPrimaryAttack, 9999.0);
		set_ent_data_float(weaponEntity, g_ClassBasePlayerWeapon, g_MemberNextSecondaryAttack, 9999.0);
	}
}

FirstThink()
{
	for (new i = 1; i <= MaxClients; i++)
	{
		if (!g_Alive[i])
		{
			plrSolid[i] = false;
			continue;
		}

		plrSolid[i] = pev(i, pev_solid) == SOLID_SLIDEBOX ? true : false;
	}
}

public fwdPlayerPreThink(const id)
{
	static i, LastThink;
	
	if (LastThink > id)
	{
		FirstThink();
	}
	
	LastThink = id;
	
	if (!plrSolid[id])
	{
		return FMRES_IGNORED;
	}
	
	static targetId, body;
	get_user_aiming(id, targetId, body);
	
	if (targetId <= 0 || targetId > MaxClients || !g_Alive[targetId] || get_gametime() < g_FlashTime[id] + 1.5 || (g_HideTimeCounter && g_Team[id] == CS_TEAM_CT))
	{
		targetId = 0;
	}
	
	if (g_AimingAtPlayer[id] != targetId)
	{
		static statusText[64];
		
		if (!targetId)
		{
			printStatusText(id, 0, g_EmptyString);
		}
		else
		{
			formatex(statusText, charsmax(statusText), "%%c1: %%p2");
			printStatusText(id, targetId, statusText);
		}
		
		g_AimingAtPlayer[id] = targetId;
	}
	
	for (i = 1; i <= MaxClients; i++)
	{
		if (!plrSolid[i] || id == i)
		{
			continue;
		}
		
		if (g_Team[i] == g_Team[id])
		{
			set_pev(i, pev_solid, SOLID_NOT);
			plrRestore[i] = true;
		}
	}

	return FMRES_IGNORED;
}

public fwdPlayerPostThink(id)
{
	static i;
	
	for (i = 1; i <= MaxClients; i++)
	{
		if (plrRestore[i])
		{
			set_pev(i, pev_solid, SOLID_SLIDEBOX);
			plrRestore[i] = false;
		}
	}
	
	return FMRES_IGNORED;
}

public fwdAddToFullPackPost(es, e, ent, host, hostflags, player, pSet)
{
	if (player && g_Alive[host] && g_Alive[ent])
	{
		static Float:flDistance;
		flDistance = entity_range(host, ent);
		
		if (plrSolid[host] && plrSolid[ent] && g_Team[host] == g_Team[ent] && flDistance < 512.0)
		{
			set_es(es, ES_Solid, SOLID_NOT);
			set_es(es, ES_RenderMode, kRenderTransAlpha);
			set_es(es, ES_RenderAmt, floatround(flDistance) / 1);
		}
	}
	
	return FMRES_IGNORED;
}

public fwdAddToFullPackPre(es, e, ent, host, hostflags, player, pSet)
{
	if (player && g_Alive[host] && g_Team[host] == CS_TEAM_CT && g_Team[ent] == CS_TEAM_T)
	{
		forward_return(FMV_CELL, 0);
		return FMRES_SUPERCEDE;
	}
	
	return FMRES_IGNORED;
}

printStatusText(id, targetId, const message[])
{
	message_begin(MSG_ONE_UNRELIABLE, g_StatusTextMessageId, _, id);
	write_byte(0);
	write_string(message);
	message_end();
	
	if (targetId != 0)
	{
		message_begin(MSG_ONE_UNRELIABLE, g_StatusValueMessageId, _, id);
		write_byte(1);
		write_short(g_Team[id] == g_Team[targetId] ? 1 : 2);
		message_end();
		
		message_begin(MSG_ONE_UNRELIABLE, g_StatusValueMessageId, _, id);
		write_byte(2);
		write_short(targetId);
		message_end();
	}
}

public messageScreenFade(messageid, messageDest, receiver)
{
	if (!get_pcvar_num(hns_noflash) || g_Team[receiver] == CS_TEAM_CT)
	{
		g_FlashTime[receiver] = (get_msg_arg_int(2) / 4096.0) + get_gametime();
		return PLUGIN_CONTINUE;
	}
	
	if (get_msg_arg_int(4) == 255 && get_msg_arg_int(5) == 255 && get_msg_arg_int(6) == 255)
	{
		if (g_Alive[receiver] || cs_get_user_team(pev(receiver, pev_iuser2)) == CS_TEAM_T)
		{
			return PLUGIN_HANDLED;
		}
	}
	
	return PLUGIN_CONTINUE;
}

public messageTextMsg(messageid, messageDest, receiver)
{
	if (g_PluginState == HnsState_Knife)
	{
		return PLUGIN_HANDLED;
	}
	
	if (g_PluginState == HnsState_Public)
	{
		static receivedMessage[64], newMessage[64];
		get_msg_arg_string(2, receivedMessage, charsmax(receivedMessage));
		
		if (TrieGetString(g_RoundEndMessageLookup, receivedMessage, newMessage, charsmax(newMessage)))
		{
			client_print(receiver, print_center, newMessage);
			return PLUGIN_HANDLED;
		}
	}
	
	return PLUGIN_CONTINUE;
}

public cmdHideKnife(id)
{	
	setHideKnife(id, !g_HideKnife[id]);
	client_print(id, print_chat, "[HNS] Hide knife %s.", g_HideKnife[id] ? "enabled" : "disabled");
	
	return PLUGIN_HANDLED;
}

public cmdHideTimeSound(id)
{
	nativeSetHideTimeSound(id, !g_HideTimeCountDownSound[id]);
	client_print(id, print_chat, "[HNS] Hide time sound %s.", g_HideTimeCountDownSound[id] ? "enabled" : "disabled");
	
	return PLUGIN_HANDLED;
}

setHideKnife(const id, const bool:value)
{
	g_HideKnife[id] = value;
	
	if (g_Alive[id] && cs_get_user_weapon(id) == CSW_KNIFE)
	{
		if (g_HideKnife[id] && g_Team[id] == CS_TEAM_T)
		{
			set_pev(id, pev_viewmodel2, g_EmptyString);
		}
		else
		{
			set_pev(id, pev_viewmodel2, g_KnifeModel_v);
		}
	}
}

setHideTimeSound(const id, const bool:value)
{
	g_HideTimeCountDownSound[id] = value;
}

public eventTeamInfo()
{
	new id = read_data(1);
	
	if (!g_Alive[id])
	{
		return;
	}
	
	new teamMessageParameter[2];
	read_data(2, teamMessageParameter, charsmax(teamMessageParameter));
	
	new CsTeams:newTeam;
	
	switch(teamMessageParameter[0])
	{
		case 'C':
		{
			newTeam = CS_TEAM_CT;
		}
		case 'T':
		{
			newTeam = CS_TEAM_T;
		}
		case 'S':
		{
			newTeam = CS_TEAM_SPECTATOR;
		}
		default:
		{
			newTeam = CS_TEAM_UNASSIGNED;
		}
	}
	
	if (newTeam != g_Team[id])
	{
		if (g_AimingAtPlayer[id])
		{
			// Trick prethink into sending Status update
			g_AimingAtPlayer[id] = -1;
		}
		
		g_Team[id] = newTeam;
		
		setUserFootsteps(id);
		new weaponEntity = cs_get_user_weapon_entity(id);
		
		if (cs_get_weapon_id(weaponEntity) == CSW_KNIFE)
		{
			updateKnifeWeapon(id, weaponEntity);
		}
	}
}

public eventNewRound()
{
	new const seekerCount = get_playersnum_ex(GetPlayers_ExcludeHLTV | GetPlayers_MatchTeam, "CT");
	new const hiderCount = get_playersnum_ex(GetPlayers_ExcludeHLTV | GetPlayers_MatchTeam, "TERRORIST");

	g_HideTimeCounter = clamp(get_pcvar_num(hns_hidetime), 0, 60);
	
	new const bool:validModeForHideTime = g_PluginState == HnsState_Public || g_PluginState == HnsState_Custom;
	remove_task(TASKID_HIDETIMER);

	if (g_HideTimeCounter && validModeForHideTime && seekerCount && hiderCount)
	{
		setFreezeTime(g_HideTimeCounter);
		set_task_ex(1.0, "taskHideTimer", TASKID_HIDETIMER, _, _, SetTask_RepeatTimes, g_HideTimeCounter - 1);
	}
	else
	{
		g_HideTimeCounter = 0;
		setFreezeTime(0);
	}
	
	setHideTimeRenderForward();
	setSemiclip();
	
	remove_task(TASKID_BREAKABLES);
	set_task(0.1, "taskRemoveBreakableEntites", TASKID_BREAKABLES);
}

public eventRoundStart()
{
	g_HideTimeCounter = 0;
	setHideTimeRenderForward();
}

public eventCTwin()
{
	if (g_PluginState == HnsState_Public)
	{
		switchTeams();
	}
}

setFreezeTime(const seconds)
{
	if (get_pcvar_num(mp_freezetime) != seconds)
	{
		set_pcvar_num(mp_freezetime, seconds);
	}
}

switchTeams()
{
	new players[MAX_PLAYERS], playerCount, playerId;
	get_players(players, playerCount);
	
	for (new i = 0; i < playerCount; i++)
	{
		playerId = players[i];
		
		switch (cs_get_user_team(playerId))
		{
			case CS_TEAM_T:
			{
				cs_set_user_team(playerId, CS_TEAM_CT);
			}
			case CS_TEAM_CT:
			{
				cs_set_user_team(playerId, CS_TEAM_T);
			}
		}
	}
}

setHideTimeRenderForward()
{
	static forwardAddToFullPackPre;
	
	if (g_HideTimeCounter && !forwardAddToFullPackPre)
	{
		forwardAddToFullPackPre = register_forward(FM_AddToFullPack, "fwdAddToFullPackPre");
	}
	else if (!g_HideTimeCounter && forwardAddToFullPackPre)
	{
		if (unregister_forward(FM_AddToFullPack, forwardAddToFullPackPre))
		{
			forwardAddToFullPackPre = 0;
		}
	}
}

setSemiclip()
{
	static forwardPlayerPreThink, forwardPlayerPostThink, forwardAddToFullPackPost;

	static bool:previousCvarValue;
	new const bool:newCvarValue = get_pcvar_bool(hns_semiclip);
	
	if (previousCvarValue && !newCvarValue)
	{
		unregister_forward(FM_PlayerPreThink, forwardPlayerPreThink);
		unregister_forward(FM_PlayerPostThink, forwardPlayerPostThink);
		unregister_forward(FM_AddToFullPack, forwardAddToFullPackPost, 1);

		forwardPlayerPreThink = 0;
		forwardPlayerPostThink = 0;
		forwardAddToFullPackPost = 0;
		
		set_msg_block(g_StatusTextMessageId, BLOCK_NOT);
		set_msg_block(g_StatusValueMessageId, BLOCK_NOT);
	}
	else if (!previousCvarValue && newCvarValue)
	{
		forwardPlayerPreThink = register_forward(FM_PlayerPreThink, "fwdPlayerPreThink");
		forwardPlayerPostThink = register_forward(FM_PlayerPostThink, "fwdPlayerPostThink");
		forwardAddToFullPackPost = register_forward(FM_AddToFullPack, "fwdAddToFullPackPost", 1);
		
		set_msg_block(g_StatusTextMessageId, BLOCK_SET);
		set_msg_block(g_StatusValueMessageId, BLOCK_SET);
	}
	
	previousCvarValue = newCvarValue;
}

public taskHideTimer()
{
	if (--g_HideTimeCounter > 10)
	{
		return;
	}
	
	static sound[16];
	num_to_word(g_HideTimeCounter, sound, charsmax(sound));
	
	new players[MAX_PLAYERS], playercount, playerId;
	get_players_ex(players, playercount, GetPlayers_ExcludeBots | GetPlayers_ExcludeHLTV | GetPlayers_ExcludeDead);
	
	for (new i = 0; i < playercount; i++)
	{
		playerId = players[i];

		if (g_HideTimeCountDownSound[playerId])
		{
			client_cmd(playerId, "spk ^"vox/%s^"", sound);
		}
	}
}

public taskRemoveBreakableEntites()
{
	static bool:previousCvarValue;
	new const bool:newCvarValue = get_pcvar_bool(hns_removebreakables);
	
	if (newCvarValue)
	{
		remove_breakables(newCvarValue != previousCvarValue);
	}
	else if (!newCvarValue && previousCvarValue)
	{
		restore_breakables();
	}
	
	previousCvarValue = newCvarValue;
}

remove_breakables(const bool:initialRemove)
{
	new entity = MaxClients, Float:renderAmt, properties[32];
	
	while ((entity = engfunc(EngFunc_FindEntityByString, entity, "classname", g_BreakableClass)))
	{
		if (!entity_get_float(entity , EV_FL_takedamage))
		{
			continue;
		}
		
		if (initialRemove)
		{
			pev(entity, pev_renderamt, renderAmt);
			
			formatex(properties, charsmax(properties), "^"%d^" ^"%f^" ^"%d^"", pev(entity, pev_rendermode), renderAmt, pev(entity, pev_solid));
			set_pev(entity, pev_message, properties);
			set_pev(entity, pev_rendermode, kRenderTransAlpha);
			set_pev(entity, pev_renderamt, 0.0);
		}
		
		// Solid state reset every round
		set_pev(entity, pev_solid, SOLID_NOT);
	}
}

restore_breakables()
{
	new entity = MaxClients, properties[32], rendermode[4], renderAmt[16], solid[4];
	
	while ((entity = engfunc(EngFunc_FindEntityByString, entity, "classname", g_BreakableClass)))
	{
		if (!entity_get_float(entity , EV_FL_takedamage))
		{
			continue;
		}
		
		pev(entity, pev_message, properties, charsmax(properties));
		
		parse(properties,\
		rendermode, charsmax(rendermode),\
		renderAmt, charsmax(renderAmt),\
		solid, charsmax(solid));
		
		set_pev(entity, pev_rendermode, str_to_num(rendermode));
		set_pev(entity, pev_renderamt, str_to_float(renderAmt));
		set_pev(entity, pev_solid, str_to_num(solid));
		set_pev(entity, pev_message, g_EmptyString);
	}
}

create_hostage()
{
	g_HostageEntity = cs_create_entity("hostage_entity");
	
	if (!is_valid_ent(g_HostageEntity))
	{
		set_fail_state("Unable to create hostage");
		return;
	}	

	engfunc(EngFunc_SetOrigin, g_HostageEntity, Float:{ 0.0, 0.0, -55000.0 });
	engfunc(EngFunc_SetSize, g_HostageEntity, Float:{ -1.0, -1.0, -1.0 }, Float:{ 1.0, 1.0, 1.0 });
	dllfunc(DLLFunc_Spawn, g_HostageEntity);
}

remove_hostage()
{
	if (is_valid_ent(g_HostageEntity))
	{
		engfunc(EngFunc_RemoveEntity, g_HostageEntity);
		g_HostageEntity = 0;
	}
}

public nativeChangeState(const plugin, const params)
{
	if (params != 1)
	{
		return PLUGIN_CONTINUE;
	}

	new const HnsPluginStates:newState = HnsPluginStates:get_param(1);

	if (g_PluginState == newState)
	{
		return PLUGIN_HANDLED;
	}
	
	if (newState == HnsState_DeathMatch)
	{
		remove_hostage();
	}
	else if (g_PluginState == HnsState_DeathMatch)
	{
		create_hostage();
	}
	
	g_PluginState = newState;
	
	if (!ExecuteForward(g_iHnsStateChangedForward, _, newState))
	{
		log_amx("Could not execute state change forward");
	}
	
	return PLUGIN_HANDLED;
}

public nativeSwitchTeams()
{
	switchTeams();
	return PLUGIN_HANDLED;
}

public nativeSetHideKnife(const plugin, const params)
{
	if (params != 2)
	{
		return PLUGIN_CONTINUE;
	}

	new id = get_param(1);
	new bool:value = bool:get_param(2);

	setHideKnife(id, value);
	return PLUGIN_HANDLED;
}

public nativeSetHideTimeSound(const plugin, const params)
{
	if (params != 2)
	{
		return PLUGIN_CONTINUE;
	}

	new id = get_param(1);
	new bool:value = bool:get_param(2);

	setHideTimeSound(id, value);
	return PLUGIN_HANDLED;
}
