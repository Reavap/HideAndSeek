#if defined _hns_common_included
  #endinput
#endif
#define _hns_common_included

enum ePluginState: g_iHideAndSeekStates ( += 1 )
{
	PUBLIC_MODE = 0,
	KNIFE_MODE,
	DEATHMATCH_MODE,
	PAUSED_MODE,
	COMPETITIVE_MODE
};

native hns_switchTeams();
native hns_changeState(ePluginState:eNewState);

native hns_setHideKnife(id, bool:bValue);
native hns_setHideTimeSound(id, bool:bValue);