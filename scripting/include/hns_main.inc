#if defined _hns_main_included
  #endinput
#endif
#define _hns_main_included

#pragma reqlib "hns_main"

enum HnsPluginStates (+= 1)
{
	HnsState_Public = 0,
	HnsState_Knife,
	HnsState_DeathMatch,
	HnsState_Custom
}

native hns_switch_teams();
native hns_change_state(HnsPluginStates:newState);

native hns_set_hideknife(id, bool:value);
native hns_set_hidetimesound(id, bool:value);