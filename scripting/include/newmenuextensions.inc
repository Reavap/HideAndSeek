#if defined _newmenuextensions_included
  #endinput
#endif
#define _newmenuextensions_included

stock menu_selected_int(const menu, const item)
{
	static data[6];
	menu_item_getinfo(menu, item, _, data, charsmax(data));
	
	return str_to_num(data);
}

stock menu_selected_clientid(const menu, const item)
{
	new selectedPlayerId = find_player_ex(FindPlayer_MatchUserId, menu_selected_int(menu, item));
	return selectedPlayerId && is_user_connected(selectedPlayerId) ? selectedPlayerId : 0;
}

stock menu_selected_char(const menu, const item)
{
	static data[2];
	menu_item_getinfo(menu, item, _, data, charsmax(data));
	
	return data[0];
}