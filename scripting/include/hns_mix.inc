#if defined _hns_mix_included
  #endinput
#endif
#define _hns_mix_included

enum eHnsMixState:g_iMixStates (+= 1)
{
	MIXSTATE_INACTIVE = 0,
	MIXSTATE_SETUP,
	MIXSTATE_PAUSED,
	MIXSTATE_ONGOING
}

forward HNS_Mix_StateChanged(const eHnsMixState:eNewState);