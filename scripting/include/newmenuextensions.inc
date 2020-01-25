#if defined _newmenuextensions_included
  #endinput
#endif
#define _newmenuextensions_included

stock menu_selected_int(const hMenu, const item)
{
	static szData[6], szName[32];
	new _access, item_callback;
	menu_item_getinfo(hMenu, item, _access, szData, charsmax(szData), szName, charsmax(szName), item_callback);
	
	return str_to_num(szData);
}

stock menu_selected_clientid(const hMenu, const item)
{
	new selectedPlayerId = find_player_ex(FindPlayer_MatchUserId, menu_selected_int(hMenu, item));
	return selectedPlayerId && is_user_connected(selectedPlayerId) ? selectedPlayerId : 0;
}