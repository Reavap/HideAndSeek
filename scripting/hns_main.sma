#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <engine>
#include <fakemeta>
#include <fun>
#include <hamsandwich>
#include <hns_common>

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
new g_iStatusText;
new g_iStatusValue;

// Forwards
new g_iHnsStateChangedForward;
new g_iHnsNewRoundForward;

// Players states
new g_iMaxPlayers;
new CsTeams:g_iTeam[MAX_PLAYERS + 1];
new bool:g_bAlive[MAX_PLAYERS + 1];

new bool:g_bHideKnife[MAX_PLAYERS + 1];
new bool:g_bHideTimeSound[MAX_PLAYERS + 1];

new bool:plrSolid[MAX_PLAYERS + 1];
new bool:plrRestore[MAX_PLAYERS + 1];

new Float:g_flFlashTime[MAX_PLAYERS + 1];
new g_iAimingAtPlayer[MAX_PLAYERS + 1];

// Constants
new const g_sEntitiesToRemove[][] =
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

new const g_sClassBasePlayerWeapon[] = "CBasePlayerWeapon";
new const g_sMemberNextPrimaryAttack[] = "m_flNextPrimaryAttack";
new const g_sMemberNextSecondaryAttack[] = "m_flNextSecondaryAttack";

new const g_sWeaponKnife[] = "weapon_knife";
new const g_sClassBreakable[] = "func_breakable";
new const g_sKnifeModel_v[] = "models/v_knife.mdl";
new const g_sBlank[] = "";

// HNS States
new g_iHostageEnt;
new ePluginState:g_eState;
new g_iHideTimer;
new bool:g_bFreezeTime;

new Trie:g_tRoundEndMessages;
new g_iRegisterSpawn;

public plugin_natives()
{
	register_library("hns_main");
	
	register_native("hns_changeState","nativeChangeState", 1);
	register_native("hns_switchTeams","nativeSwitchTeams", 1);
	
	register_native("hns_setHideKnife","nativeSetHideKnife", 1);
	register_native("hns_setHideTimeSound", "nativeSetHideTimeSound", 1);
}
	
public plugin_precache() 
{
	if (!engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "func_buyzone")))
	{
		set_fail_state("Unable to create buyzone");
	}
	
	new sInfoMapParametersEntityClass[] = "info_map_parameters";
	new iEntity = engfunc(EngFunc_FindEntityByString, -1, "classname", sInfoMapParametersEntityClass);
	
	if (!iEntity)
	{
		iEntity = create_entity(sInfoMapParametersEntityClass);
		
		if (!pev_valid(iEntity))
		{
			set_fail_state("Unable to disable buying");
		}
		else
		{
			DispatchSpawn(iEntity);
		}
	}
	
	if (iEntity)
	{
		DispatchKeyValue(iEntity, "buying", "3");
	}
	
	create_hostage();
	
	g_iRegisterSpawn = register_forward(FM_Spawn, "fwdSpawn", 1);
}

public plugin_init()
{
	register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
	register_cvar(PLUGIN_NAME, PLUGIN_VERSION, FCVAR_SERVER|FCVAR_SPONLY);
	
	if (g_iRegisterSpawn)
	{
		unregister_forward(FM_Spawn, g_iRegisterSpawn, 1);
	}
	
	g_iStatusText = get_user_msgid("StatusText");
	g_iStatusValue = get_user_msgid("StatusValue");
	
	register_message(get_user_msgid("ScreenFade"), "messageScreenFade");
	register_message(get_user_msgid("TextMsg"), "messageTextMsg");
	
	new const sPlayer[] = "player";
	RegisterHam(Ham_Spawn, sPlayer, "fwdHamSpawn", 1);
	RegisterHam(Ham_Killed, sPlayer, "fwdHamKilled", 0);
	RegisterHam(Ham_CS_Player_ResetMaxSpeed, sPlayer, "fwdHamResetMaxSpeed", 1);
	RegisterHam(Ham_Weapon_PrimaryAttack, g_sWeaponKnife, "fwdHamKnifeSlash");
	RegisterHam(Ham_Item_Deploy, g_sWeaponKnife, "fwdHamDeployKnife", 1);
	
	g_iHnsStateChangedForward = CreateMultiForward("HNS_StateChanged", ET_IGNORE, FP_CELL);
	g_iHnsNewRoundForward = CreateMultiForward("HNS_NewRound", ET_IGNORE);
	
	if (g_iHnsStateChangedForward < 0)
	{
		g_iHnsStateChangedForward = 0;
		log_amx("State change forward could not be created.");
	}
	
	if (g_iHnsNewRoundForward < 0)
	{
		g_iHnsNewRoundForward = 0;
		log_amx("New round forward could not be created.");
	}
	
	register_forward(FM_Sys_Error,"fwdSysError");
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
	g_eState = PUBLIC_MODE;
	g_iMaxPlayers = get_maxplayers();
	
	new const sHidersWinMessage[] = "Hiders Win";
	g_tRoundEndMessages = TrieCreate();
	TrieSetString(g_tRoundEndMessages, "#Hostages_Not_Rescued", sHidersWinMessage);
	TrieSetString(g_tRoundEndMessages, "#Terrorists_Win", sHidersWinMessage);
	TrieSetString(g_tRoundEndMessages, "#CTs_Win", "Seekers Win");
}

public plugin_end()
{
	g_eState = PUBLIC_MODE;
	setFreezeTime(0);
	
	DestroyForward(g_iHnsStateChangedForward);
	g_iHnsStateChangedForward = 0;
	
	DestroyForward(g_iHnsNewRoundForward);
	g_iHnsNewRoundForward = 0;
}

public client_disconnected(id)
{
	g_bAlive[id] = false;
	g_iTeam[id] = CS_TEAM_UNASSIGNED;
	
	g_bHideKnife[id] = false;
	g_bHideTimeSound[id] = false;
}

public fwdSysError()
{
	plugin_end();
}

public fwdSpawn(iEntity)
{
	if (pev_valid(iEntity))
	{
		static szClassName[32];
		pev(iEntity, pev_classname, szClassName, charsmax(szClassName));
		
		for (new i = 0; i < sizeof g_sEntitiesToRemove; i++) 		
		{
			if (equal(szClassName, g_sEntitiesToRemove[i]))			
			{
				engfunc(EngFunc_RemoveEntity, iEntity);
				break;
			}
		}
	}
}

public fwdEmitSound(iEntity, iChannel, const sSample[], Float:fVolume, Float:fAttenuation, iFlags, iPitch)
{
	if (1 <= iEntity <= 32 && g_iTeam[iEntity] == CS_TEAM_T && g_eState != KNIFE_MODE && sSample[0] == 'w' && equali(sSample, "weapons/knife_deploy1.wav"))
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

	g_bAlive[id] = true;
	g_iTeam[id] = cs_get_user_team(id);
	
	g_flFlashTime[id] = 0.0;
	g_iAimingAtPlayer[id] = 0;
	
	strip_user_weapons(id);
	give_item(id, g_sWeaponKnife);
	
	if (g_iTeam[id] == CS_TEAM_T && g_eState != KNIFE_MODE)
	{
		new iFlashBangs = get_pcvar_num(hns_flashbangs);
		new iSmokeGrenades = get_pcvar_num(hns_smokegrenades);
		
		if (iFlashBangs > 0)
		{
			give_item(id, "weapon_flashbang");
			cs_set_user_bpammo(id, CSW_FLASHBANG, iFlashBangs);
		}
		if (iSmokeGrenades > 0)
		{
			give_item(id, "weapon_smokegrenade");
			cs_set_user_bpammo(id, CSW_SMOKEGRENADE, iSmokeGrenades);
		}
	}
	
	set_user_footsteps(id, CsTeams:get_pcvar_num(hns_footsteps) & g_iTeam[id] && g_eState != KNIFE_MODE);
	
	return HAM_IGNORED;
}

public fwdHamKilled(iVictim, iAttacker, bShouldGib)
{
	g_bAlive[iVictim] = false;
	return HAM_IGNORED;
}

public fwdHamResetMaxSpeed(id)
{
	new Float:flMaxSpeed;
	pev(id, pev_maxspeed, flMaxSpeed);
	
	fwdSetClientMaxSpeed(id, flMaxSpeed);
	
	return HAM_IGNORED;
}

public fwdSetClientMaxSpeed(id, Float:flMaxSpeed)
{
	if (g_bFreezeTime && flMaxSpeed == 1.0 && g_iTeam[id] == CS_TEAM_T)
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

public fwdHamDeployKnife(iEntity)
{
	if (g_eState != KNIFE_MODE)
	{
		new iClient = get_ent_data_entity(iEntity, "CBasePlayerItem", "m_pPlayer");
		updateKnifeWeapon(iClient, iEntity);
	}
	
	return HAM_IGNORED;
}

updateKnifeWeapon(const iClient, const iWeaponEntity)
{
	if (g_iTeam[iClient] == CS_TEAM_CT && get_ent_data_float(iWeaponEntity, g_sClassBasePlayerWeapon, g_sMemberNextPrimaryAttack) > 60.0)
	{
		set_ent_data_float(iWeaponEntity, g_sClassBasePlayerWeapon, g_sMemberNextPrimaryAttack, 0.0);
		set_ent_data_float(iWeaponEntity, g_sClassBasePlayerWeapon, g_sMemberNextSecondaryAttack, 0.0);
	}
	else if (g_iTeam[iClient] == CS_TEAM_T)
	{
		if (g_bHideKnife[iClient])
		{
			set_pev(iClient, pev_viewmodel2, g_sBlank);
		}
		
		set_ent_data_float(iWeaponEntity, g_sClassBasePlayerWeapon, g_sMemberNextPrimaryAttack, 9999.0);
		set_ent_data_float(iWeaponEntity, g_sClassBasePlayerWeapon, g_sMemberNextSecondaryAttack, 9999.0);
	}
}

FirstThink()
{
	for (new i = 1; i <= g_iMaxPlayers; i++)
	{
		if (!g_bAlive[i])
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
	
	if (targetId <= 0 || targetId > g_iMaxPlayers || !g_bAlive[targetId] || get_gametime() < g_flFlashTime[id] + 1.5 || (g_bFreezeTime && g_iTeam[id] == CS_TEAM_CT))
	{
		targetId = 0;
	}
	
	if (g_iAimingAtPlayer[id] != targetId)
	{
		static szMsg[64];
		
		if (!targetId)
		{
			printStatusText(id, 0, g_sBlank);
		}
		else
		{
			formatex(szMsg, charsmax(szMsg), "%%c1: %%p2");
			printStatusText(id, targetId, szMsg);
		}
		
		g_iAimingAtPlayer[id] = targetId;
	}
	
	for (i = 1; i <= g_iMaxPlayers; i++)
	{
		if (!plrSolid[i] || id == i)
		{
			continue;
		}
		
		if (g_iTeam[i] == g_iTeam[id])
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
	
	for (i = 1; i <= g_iMaxPlayers; i++)
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
	if (player && g_bAlive[host] && g_bAlive[ent])
	{
		static Float:flDistance;
		flDistance = entity_range(host, ent);
		
		if (plrSolid[host] && plrSolid[ent] && g_iTeam[host] == g_iTeam[ent] && flDistance < 512.0)
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
	if (player && g_bAlive[host] && g_iTeam[host] == CS_TEAM_CT && g_iTeam[ent] == CS_TEAM_T)
	{
		forward_return(FMV_CELL, 0);
		return FMRES_SUPERCEDE;
	}
	
	return FMRES_IGNORED;
}

printStatusText(id, targetId, const sMsg[])
{
	message_begin(MSG_ONE_UNRELIABLE, g_iStatusText, _, id);
	write_byte(0);
	write_string(sMsg);
	message_end();
	
	if (targetId != 0)
	{
		message_begin(MSG_ONE_UNRELIABLE, g_iStatusValue, _, id);
		write_byte(1);
		write_short(g_iTeam[id] == g_iTeam[targetId] ? 1 : 2);
		message_end();
		
		message_begin(MSG_ONE_UNRELIABLE, g_iStatusValue, _, id);
		write_byte(2);
		write_short(targetId);
		message_end();
	}
}

public messageScreenFade(iMsgId, iMsgDest, iReceiver)
{
	if (!get_pcvar_num(hns_noflash) || g_iTeam[iReceiver] == CS_TEAM_CT)
	{
		g_flFlashTime[iReceiver] = (get_msg_arg_int(2) / 4096.0) + get_gametime();
		return PLUGIN_CONTINUE;
	}
	
	if (get_msg_arg_int(4) == 255 && get_msg_arg_int(5) == 255 && get_msg_arg_int(6) == 255)
	{
		if (g_bAlive[iReceiver] || cs_get_user_team(pev(iReceiver, pev_iuser2)) == CS_TEAM_T)
		{
			return PLUGIN_HANDLED;
		}
	}
	
	return PLUGIN_CONTINUE;
}

public messageTextMsg(iMessage, iDest, id)
{
	if (g_eState == KNIFE_MODE)
	{
		return PLUGIN_HANDLED;
	}
	
	if (g_eState == PUBLIC_MODE)
	{
		static szMessage[64], szNewMessage[64];
		get_msg_arg_string(2, szMessage, charsmax(szMessage));
		
		if (TrieKeyExists(g_tRoundEndMessages, szMessage))
		{
			TrieGetString(g_tRoundEndMessages, szMessage, szNewMessage, charsmax(szNewMessage));
			client_print(id, print_center, szNewMessage);
			
			return PLUGIN_HANDLED;
		}
	}
	
	return PLUGIN_CONTINUE;
}

public cmdHideKnife(id)
{	
	nativeSetHideKnife(id, !g_bHideKnife[id]);
	client_print(id, print_chat, "[HNS] Hide knife %s.", g_bHideKnife[id] ? "enabled" : "disabled");
	
	return PLUGIN_HANDLED;
}

public cmdHideTimeSound(id)
{
	nativeSetHideTimeSound(id, !g_bHideTimeSound[id]);
	client_print(id, print_chat, "[HNS] Hide time sound %s.", g_bHideTimeSound[id] ? "enabled" : "disabled");
	
	return PLUGIN_HANDLED;
}

public eventTeamInfo()
{
	new id = read_data(1);
	
	if (!g_bAlive[id])
	{
		return;
	}
	
	new szTeam[2];
	read_data(2, szTeam, charsmax(szTeam));
	
	new CsTeams:iNewTeam;
	
	switch(szTeam[0])
	{
		case 'C':
		{
			iNewTeam = CS_TEAM_CT;
		}
		case 'T':
		{
			iNewTeam = CS_TEAM_T;
		}
		case 'S':
		{
			iNewTeam = CS_TEAM_SPECTATOR;
		}
		default:
		{
			iNewTeam = CS_TEAM_UNASSIGNED;
		}
	}
	
	if (iNewTeam != g_iTeam[id])
	{
		if (g_iAimingAtPlayer[id])
		{
			// Trick prethink into sending Status update
			g_iAimingAtPlayer[id] = -1;
		}
		
		g_iTeam[id] = iNewTeam;
		
		set_user_footsteps(id, CsTeams:get_pcvar_num(hns_footsteps) & iNewTeam && g_eState != KNIFE_MODE);
		new iWeaponEntity = cs_get_user_weapon_entity(id);
		
		if (cs_get_weapon_id(iWeaponEntity) == CSW_KNIFE)
		{
			updateKnifeWeapon(id, iWeaponEntity);
		}
	}
}

public eventNewRound()
{
	new iReturn;
	if (!ExecuteForward(g_iHnsNewRoundForward, iReturn))
	{
		log_amx("Could not execute new round forward");
	}
	
	remove_task(TASKID_HIDETIMER);
	
	new aPlayers[MAX_PLAYERS], iPlayerCount, i, playerId, bool:bSeekersHavePlayer, bool:bHidersHavePlayer;
	get_players(aPlayers, iPlayerCount, "h");
	
	for (; i < iPlayerCount; i++)
	{
		playerId = aPlayers[i];
		
		switch (cs_get_user_team(playerId))
		{
			case CS_TEAM_CT:
			{
				bSeekersHavePlayer = true;
			}
			case CS_TEAM_T:
			{
				bHidersHavePlayer = true;
			}
		}
	}
	
	g_iHideTimer = clamp(get_pcvar_num(hns_hidetime), 0, 60);
	new bool:bValidModeForHideTime;
	
	bValidModeForHideTime = g_eState == PUBLIC_MODE || g_eState == COMPETITIVE_MODE;
	
	if (g_iHideTimer && bValidModeForHideTime && bSeekersHavePlayer && bHidersHavePlayer)
	{
		g_bFreezeTime = true;
		setFreezeTime(g_iHideTimer);
		set_task(1.0, "taskHideTimer", TASKID_HIDETIMER, _, _, "a", g_iHideTimer - 1);
	}
	else
	{
		g_iHideTimer = 0;
		g_bFreezeTime = false;
		setFreezeTime(0);
	}
	
	setHideTimeRenderForward();
	setSemiclip();
	
	remove_task(TASKID_BREAKABLES);
	set_task(0.1, "taskRemoveBreakableEntites", TASKID_BREAKABLES);
}

public eventRoundStart()
{
	g_bFreezeTime = false;
	setHideTimeRenderForward();
}

public eventCTwin()
{
	if (g_eState == PUBLIC_MODE)
	{
		switchTeams();
	}
}

setFreezeTime(iSeconds)
{
	if (get_pcvar_num(mp_freezetime) != iSeconds)
	{
		set_pcvar_num(mp_freezetime, iSeconds);
	}
}

switchTeams()
{
	new aPlayers[MAX_PLAYERS], iPlayerCount, i, playerId;
	get_players(aPlayers, iPlayerCount);
	
	for (; i < iPlayerCount; i++)
	{
		playerId = aPlayers[i];
		
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
	static iAddToFullPackForwardPre;
	
	if (g_bFreezeTime && !iAddToFullPackForwardPre)
	{
		iAddToFullPackForwardPre = register_forward(FM_AddToFullPack, "fwdAddToFullPackPre");
	}
	else if (!g_bFreezeTime && iAddToFullPackForwardPre)
	{
		if (unregister_forward(FM_AddToFullPack, iAddToFullPackForwardPre))
		{
			iAddToFullPackForwardPre = 0;
		}
	}
}

setSemiclip()
{
	static bool:bPreviousCvarValue, iPlayerPreThinkForward, iPlayerPostThinkForward, iAddToFullPackForward;
	new bool:bNewCvarValue = get_pcvar_num(hns_semiclip) == 1;
	
	if (bPreviousCvarValue && !bNewCvarValue)
	{
		if (unregister_forward(FM_PlayerPreThink, iPlayerPreThinkForward))
		{
			iPlayerPreThinkForward = 0;
		}
		if (unregister_forward(FM_PlayerPostThink, iPlayerPostThinkForward))
		{
			iPlayerPostThinkForward = 0;
		}
		if (unregister_forward(FM_AddToFullPack, iAddToFullPackForward, 1))
		{
			iAddToFullPackForward = 0;
		}
		
		set_msg_block(g_iStatusText, BLOCK_NOT);
		set_msg_block(g_iStatusValue, BLOCK_NOT);
	}
	else if (!bPreviousCvarValue && bNewCvarValue)
	{
		iPlayerPreThinkForward = register_forward(FM_PlayerPreThink, "fwdPlayerPreThink");
		iPlayerPostThinkForward = register_forward(FM_PlayerPostThink, "fwdPlayerPostThink");
		iAddToFullPackForward = register_forward(FM_AddToFullPack, "fwdAddToFullPackPost", 1);
		
		set_msg_block(g_iStatusText, BLOCK_SET);
		set_msg_block(g_iStatusValue, BLOCK_SET);
	}
	
	bPreviousCvarValue = bNewCvarValue;
}

public taskHideTimer()
{
	g_iHideTimer--;
	
	if (g_iHideTimer > 10)
	{
		return;
	}
	
	static szSound[16];
	num_to_word(g_iHideTimer, szSound, charsmax(szSound));
	
	new aPlayers[MAX_PLAYERS], iPlayerCount, i, playerId;
	get_players(aPlayers, iPlayerCount, "ach");
	
	for (; i < iPlayerCount; i++)
	{
		playerId = aPlayers[i];
		
		if (g_bHideTimeSound[playerId])
		{
			client_cmd(playerId, "spk ^"vox/%s^"", szSound);
		}
	}
}

public taskRemoveBreakableEntites()
{
	static bool:bPreviousCvarValue;
	new bool:bNewCvarValue = get_pcvar_num(hns_removebreakables) == 1;
	
	if (bNewCvarValue)
	{
		remove_breakables(bNewCvarValue != bPreviousCvarValue);
	}
	else if (!bNewCvarValue && bPreviousCvarValue)
	{
		restore_breakables();
	}
	
	bPreviousCvarValue = bNewCvarValue;
}

remove_breakables(bool:bInitialRemove)
{
	new iEntity = g_iMaxPlayers, Float:fRenderAmt, szProperties[32];
	
	while ((iEntity = engfunc(EngFunc_FindEntityByString, iEntity, "classname", g_sClassBreakable)))
	{
		if (!entity_get_float(iEntity , EV_FL_takedamage))
		{
			continue;
		}
		
		if (bInitialRemove)
		{
			pev(iEntity, pev_renderamt, fRenderAmt);
			
			formatex(szProperties, charsmax(szProperties), "^"%d^" ^"%f^" ^"%d^"", pev(iEntity, pev_rendermode), fRenderAmt, pev(iEntity, pev_solid));
			set_pev(iEntity, pev_message, szProperties);
			set_pev(iEntity, pev_rendermode, kRenderTransAlpha);
			set_pev(iEntity, pev_renderamt, 0.0);
		}
		
		// Solid state reset every round
		set_pev(iEntity, pev_solid, SOLID_NOT);
	}
}

restore_breakables()
{
	new iEntity = g_iMaxPlayers, szProperties[32], szRenderMode[4], szRenderAmt[16], szSolid[4];
	
	while ((iEntity = engfunc(EngFunc_FindEntityByString, iEntity, "classname", g_sClassBreakable)))
	{
		if (!entity_get_float(iEntity , EV_FL_takedamage))
		{
			continue;
		}
		
		pev(iEntity, pev_message, szProperties, charsmax(szProperties));
		
		parse(szProperties,\
		szRenderMode, charsmax(szRenderMode),\
		szRenderAmt, charsmax(szRenderAmt),\
		szSolid, charsmax(szSolid));
		
		set_pev(iEntity, pev_rendermode, str_to_num(szRenderMode));
		set_pev(iEntity, pev_renderamt, str_to_float(szRenderAmt));
		set_pev(iEntity, pev_solid, str_to_num(szSolid));
		set_pev(iEntity, pev_message, g_sBlank);
	}
}

create_hostage()
{
	g_iHostageEnt = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "hostage_entity"));
	
	if (!pev_valid(g_iHostageEnt))
	{
		set_fail_state("Unable to create hostage");
	}
	
	engfunc(EngFunc_SetOrigin, g_iHostageEnt, Float:{ 0.0, 0.0, -55000.0 });
	engfunc(EngFunc_SetSize, g_iHostageEnt, Float:{ -1.0, -1.0, -1.0 }, Float:{ 1.0, 1.0, 1.0 });
	dllfunc(DLLFunc_Spawn, g_iHostageEnt);
}

remove_hostage()
{
	if (pev_valid(g_iHostageEnt))
	{
		engfunc(EngFunc_RemoveEntity, g_iHostageEnt);
		g_iHostageEnt = 0;
	}
}

public nativeChangeState(ePluginState:eNewState)
{
	if (g_eState == eNewState)
	{
		return PLUGIN_HANDLED;
	}
	
	if (eNewState == DEATHMATCH_MODE)
	{
		remove_hostage();
	}
	else if (g_eState == DEATHMATCH_MODE)
	{
		create_hostage();
	}
	
	g_eState = eNewState;
	
	
	new iReturn;
	if (!ExecuteForward(g_iHnsStateChangedForward, iReturn, eNewState))
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

public nativeSetHideKnife(id, bool:bValue)
{
	g_bHideKnife[id] = bValue;
	
	if (g_bAlive[id] && get_user_weapon(id) == CSW_KNIFE)
	{
		if (g_bHideKnife[id] && g_iTeam[id] == CS_TEAM_T)
		{
			set_pev(id, pev_viewmodel2, g_sBlank);
		}
		else
		{
			set_pev(id, pev_viewmodel2, g_sKnifeModel_v);
		}
	}
	
	return PLUGIN_HANDLED;
}

public nativeSetHideTimeSound(id, bool:bValue)
{
	g_bHideTimeSound[id] = bValue;
}
