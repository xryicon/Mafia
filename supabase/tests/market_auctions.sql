begin;
-- All fixtures and economic changes are rolled back after this suite.
do $
#variable_conflict use_variable
declare a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();c uuid:=gen_random_uuid();
 s uuid:=game_private.current_season();r jsonb;q jsonb;id uuid;other_id uuid;denied boolean;before_cash bigint;deadline timestamptz;score_before numeric;
begin
 insert into auth.users(id,raw_user_meta_data) values
 (a,jsonb_build_object('username','MktA'||left(replace(a::text,'-',''),10))),
 (b,jsonb_build_object('username','MktB'||left(replace(b::text,'-',''),10))),
 (c,jsonb_build_object('username','MktC'||left(replace(c::text,'-',''),10)));
 perform set_config('request.jwt.claim.sub',a::text,true);perform public.game_state();
 perform set_config('request.jwt.claim.sub',b::text,true);perform public.game_state();
 perform set_config('request.jwt.claim.sub',c::text,true);perform public.game_state();
 perform set_config('game.reason','Rollback-only auction test funding',true);
 update public.game_players set cash=10000 where id in(a,b,c);
 update public.game_settings set value=5 where key='market_fee_percent';
 perform set_config('request.jwt.claim.sub',a::text,true);
 select score into score_before from game_private.season_scores(s,'net_worth') where player_id=a;
 q:=jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'good_id','whiskey','quantity',3,'starting_bid',200,'duration_minutes',5,'seller_id',b,'price',1);
 r:=public.market_auction_action('create',q);if r?'error' then raise exception 'Create failed %',r;end if;id:=(r->>'auction_id')::uuid;
 if (select seller_id from public.game_market_auctions where game_market_auctions.id=id)<>a then raise exception 'Trusted client seller ID';end if;
 if (select quantity from public.game_inventory where season_id=s and player_id=a and good_id='whiskey')<>2 then raise exception 'Stock not reserved';end if;
 if (select score from game_private.season_scores(s,'net_worth') where player_id=a)<>score_before then raise exception 'Reserved stock missing from net worth';end if;
 r:=public.market_auction_action('create',q);if (r->>'auction_id')::uuid<>id or (select count(*) from public.game_market_auctions where seller_id=a)<>1 then raise exception 'Create retry duplicated stock';end if;
 r:=public.market_auction_action('create',q||'{"quantity":4}');if not(r?'error') then raise exception 'Changed retry accepted';end if;
 r:=public.market_auction_action('create',q||jsonb_build_object('request_id',gen_random_uuid(),'quantity',4));if not(r?'error') then raise exception 'Overselling accepted';end if;
 r:=public.market_auction_action('bid',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'auction_id',id,'amount',200));if not(r?'error') then raise exception 'Self bidding accepted';end if;
 perform set_config('request.jwt.claim.sub',b::text,true);
 r:=public.market_auction_action('cancel',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'auction_id',id));if not(r?'error') then raise exception 'Other player cancelled';end if;
 q:=jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'auction_id',id,'amount',200);
 r:=public.market_auction_action('bid',q);if r?'error' then raise exception 'Bid failed %',r;end if;
 r:=public.market_auction_action('bid',q);if r?'error' or (select bid_count from public.game_market_auctions where game_market_auctions.id=id)<>1 then raise exception 'Bid retry duplicated';end if;
 if (select cash from public.game_players where game_players.id=b)<>9800 then raise exception 'First reserve incorrect';end if;
 r:=public.market_auction_action('bid',q||jsonb_build_object('request_id',gen_random_uuid(),'amount',210));if r?'error' then raise exception 'Own increase failed %',r;end if;
 if (select cash from public.game_players where game_players.id=b)<>9790 then raise exception 'Own increase charged full bid twice';end if;
 perform set_config('request.jwt.claim.sub',c::text,true);
 r:=public.market_auction_action('bid',q||jsonb_build_object('request_id',gen_random_uuid(),'amount',211));if not(r?'error') then raise exception 'Increment bypass';end if;
 update public.game_market_auctions set ends_at=clock_timestamp()+interval '10 seconds' where game_market_auctions.id=id;
 r:=public.market_auction_action('bid',q||jsonb_build_object('request_id',gen_random_uuid(),'amount',220));if r?'error' then raise exception 'Outbid failed %',r;end if;
 if (select ends_at from public.game_market_auctions where game_market_auctions.id=id)<clock_timestamp()+interval '55 seconds' then raise exception 'Late bid did not extend';end if;
 if (select cash from public.game_players where game_players.id=b)<>10000 or (select cash from public.game_players where game_players.id=c)<>9780 then raise exception 'Outbid refund incorrect';end if;
 r:=public.market_auction_action('bid',q||jsonb_build_object('request_id',gen_random_uuid(),'amount',10001));if not(r?'error') then raise exception 'Insufficient balance accepted';end if;
 if (select sum(cash) from public.game_players where game_players.id in(a,b,c))+(select escrow from public.game_market_auctions where game_market_auctions.id=id)<>30000 then raise exception 'Bid conservation failed';end if;
 perform set_config('request.jwt.claim.sub',a::text,true);
 r:=public.market_auction_action('cancel',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'auction_id',id));if not(r?'error') then raise exception 'Seller cancelled a funded auction';end if;
 update public.game_market_auctions set ends_at=clock_timestamp()-interval '1 second' where game_market_auctions.id=id;
 perform set_config('request.jwt.claim.sub',b::text,true);
 r:=public.market_auction_action('bid',q||jsonb_build_object('request_id',gen_random_uuid(),'amount',230));if not(r?'error') then raise exception 'Late bid accepted';end if;
 r:=public.market_state();
 if (select status from public.game_market_auctions where game_market_auctions.id=id)<>'sold' then raise exception 'Automatic settlement failed';end if;
 if (select cash from public.game_players where game_players.id=a)<>10209 or (select quantity from public.game_inventory where season_id=s and player_id=c and good_id='whiskey')<>8 then raise exception 'Winner goods / seller fee incorrect';end if;
 if (select count(*) from public.game_ledger where player_id=a and reason='Auction sale: '||id)<>1 then raise exception 'Missing or duplicate sale ledger';end if;
 r:=public.market_auction_action('settle',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'auction_id',id));
 if (select cash from public.game_players where game_players.id=a)<>10209 then raise exception 'Repeated settlement duplicated money';end if;
 if has_table_privilege('authenticated','public.game_market_auctions','UPDATE') or has_table_privilege('authenticated','public.game_market_bids','INSERT') or has_function_privilege('authenticated','game_private.market_close_due(boolean)','EXECUTE') or has_function_privilege('anon','public.market_state()','EXECUTE') then raise exception 'Auction permission exposure';end if;
 if not exists(select 1 from public.game_audit where after_data->>'id'=id::text) then raise exception 'Auction history not audited';end if;
 denied:=false;begin delete from public.game_market_bids where auction_id=id;exception when others then denied:=true;end;if not denied then raise exception 'Bid history deletion allowed';end if;
 perform set_config('request.jwt.claim.sub',a::text,true);
 q:=jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'good_id','whiskey','quantity',2,'starting_bid',300,'duration_minutes',5);
 r:=public.market_auction_action('create',q);if r?'error' then raise exception 'Unsold fixture failed %',r;end if;other_id:=(r->>'auction_id')::uuid;
 update public.game_market_auctions set ends_at=clock_timestamp()-interval '1 second' where game_market_auctions.id=other_id;
 perform public.market_state();
 if (select quantity from public.game_inventory where season_id=s and player_id=a and good_id='whiskey')<>2 then raise exception 'Unsold stock not returned';end if;
 r:=public.market_auction_action('create',q||jsonb_build_object('request_id',gen_random_uuid()));other_id:=(r->>'auction_id')::uuid;
 r:=public.market_auction_action('cancel',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'auction_id',other_id));if r?'error' then raise exception 'No-bid cancellation failed %',r;end if;
 -- A pause freezes auctions; final snapshot refunds before computing cash rankings.
 r:=public.market_auction_action('create',q||jsonb_build_object('request_id',gen_random_uuid()));other_id:=(r->>'auction_id')::uuid;
 perform set_config('request.jwt.claim.sub',b::text,true);
 r:=public.market_auction_action('bid',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'auction_id',other_id,'amount',300));if r?'error' then raise exception 'Snapshot fixture bid failed';end if;
 perform set_config('request.jwt.claim.sub',a::text,true);
 update public.game_user_roles set role_id='owner' where player_id=a;
 r:=public.season_action('lock',jsonb_build_object('season_id',s,'reason','Rollback auction pause test'));if r?'error' then raise exception 'Lock failed %',r;end if;
 select ends_at into deadline from public.game_market_auctions where game_market_auctions.id=other_id;
 r:=public.market_auction_action('bid',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'auction_id',other_id,'amount',400));if not(r?'error') then raise exception 'Closed season accepted bid';end if;
 update public.game_seasons set locked_at=clock_timestamp()-interval '60 seconds' where game_seasons.id=s;
 r:=public.season_action('open',jsonb_build_object('season_id',s,'reason','Rollback auction resume test'));if r?'error' then raise exception 'Reopen failed %',r;end if;
 if (select ends_at from public.game_market_auctions where game_market_auctions.id=other_id)<deadline+interval '55 seconds' then raise exception 'Pause duration not preserved';end if;
 perform public.season_action('lock',jsonb_build_object('season_id',s,'reason','Rollback auction snapshot test'));
 r:=public.season_action('snapshot',jsonb_build_object('season_id',s,'reason','Rollback auction final results'));if r?'error' then raise exception 'Snapshot failed %',r;end if;
 if (select cash from public.game_players where game_players.id=b)<>10000 or (select quantity from public.game_inventory where season_id=s and player_id=a and good_id='whiskey')<>2 then raise exception 'Final snapshot failed to release reserves';end if;
 if (select score from public.game_season_results where season_id=s and player_id=b and metric='cash')<>10000 then raise exception 'Snapshot used cash before refund';end if;
 if exists(select 1 from public.game_market_auctions where season_id=s and status='open') then raise exception 'Outstanding auction after snapshot';end if;
 if exists(select 1 from public.game_players p where p.id in(a,b,c) and p.cash<>(select sum(l.delta) from public.game_ledger l where l.player_id=p.id)) then raise exception 'Wallet ledger does not reconcile';end if;
end $$;
select 'PASS: goods reservation, idempotency, self/late bids, increment, refunds, anti-sniping, fees, settlement, permissions, history, seasons and ledger conservation';
rollback;

