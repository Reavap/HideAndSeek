#if defined _hns_mix_included
  #endinput
#endif
#define _hns_mix_included

#pragma reqlib "hns_mix"

enum HnsMixStates (+= 1)
{
	MixState_Inactive = 0,
	MixState_Setup,
	MixState_Paused,
	MixState_Ongoing
}

forward HNS_Mix_StateChanged(const HnsMixStates:newState);

stock getTeamColor(const CsTeams:team)
{
	switch (team)
	{
		case CS_TEAM_T:
			return print_team_red;

		case CS_TEAM_CT:
			return print_team_blue;

		case CS_TEAM_SPECTATOR:
			return print_team_grey;
	}

	return print_team_default;
}

stock getTimeAsText(const Float:time, const bool:includeMillseconds = false)
{
	static timeString[10];

	new totalSeconds = floatround(time, floatround_floor);
	new minutes = totalSeconds / 60;
	new seconds = totalSeconds - minutes * 60;
	
	formatex(timeString, charsmax(timeString), "%s%d:%s%d",
	(minutes < 10 ? "0" : ""), minutes,
	(seconds < 10 ? "0" : ""), seconds);
	
	if (includeMillseconds)
	{
		new milliseconds = floatround((time - totalSeconds) * 1000.0, floatround_floor);
		
		formatex(timeString, charsmax(timeString), "%s.%s%s%d",
		timeString,
		(milliseconds < 100 ? "0" : ""),
		(milliseconds < 10 ? "0" : ""),
		milliseconds);
	}

	return timeString;
}