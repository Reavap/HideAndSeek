#if defined _hns_teamjoin_included
  #endinput
#endif
#define _hns_teamjoin_included

#pragma reqlib "hns_teamjoin"

native hns_transfer_all_players(CsTeams:team);
native hns_transfer_player(id, CsTeams:team);
native hns_swap_players(player1, player2);