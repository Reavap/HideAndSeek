#if defined _newmenuextensions_included
  #endinput
#endif
#define _newmenuextensions_included

stock menu_selected_int(const menu, const item)
{
	static data[6], name[32];
	new _access, item_callback;
	menu_item_getinfo(menu, item, _access, data, charsmax(data), name, charsmax(name), item_callback);
	
	return str_to_num(data);
}

stock menu_selected_clientid(const menu, const item)
{
	new selectedPlayerId = find_player_ex(FindPlayer_MatchUserId, menu_selected_int(menu, item));
	return selectedPlayerId && is_user_connected(selectedPlayerId) ? selectedPlayerId : 0;
}