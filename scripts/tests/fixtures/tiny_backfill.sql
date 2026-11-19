--
-- PostgreSQL database dump (hand-written fixture for test_parity.py)
--

SET statement_timeout = 0;

COPY public.team (abbr, name, nickname, conference, division, color) FROM stdin;
KC	Kansas City Chiefs	Chiefs	AFC	West	#E31837
\.

COPY public.game (id, season, week, game_type, kickoff_at, away_team, home_team, away_score, home_score, spread_line, total_line, overtime, status, recap) FROM stdin;
2025_01_KC_LAC	2025	1	REG	2025-09-06 00:00:00+00	KC	LAC	21	27	-3	46.5	f	final	\N
2025_19_LAC_KC	2025	19	WC	2026-01-10 21:30:00+00	LAC	KC	20	23	3.5	44	t	final_ot	Went to overtime.
2024_01_BAL_KC	2024	1	REG	2024-09-06 00:20:00+00	BAL	KC	20	27	3	46	f	final	\N
\.

COPY public.teamseasonstat (season, team, wins, losses, ties, points_for, points_against, sos, streak, form, power, playoff_seed) FROM stdin;
2025	LAC	1	0	0	27	21	0.5	W1	W	60.1	\N
2025	KC	0	1	0	21	27	0.5	L1	L	40.2	\N
2024	KC	1	0	0	27	20	0.5	W1	W	55	\N
\.

COPY public.playerseasonstat (season, player_id, team, "position", games, seasons_played, attempts, carries, targets, receptions, passing_yards, passing_tds, passing_epa, rushing_yards, rushing_tds, rushing_epa, receiving_yards, receiving_tds, receiving_epa) FROM stdin;
2025	00-0033873	KC	QB	1	2	35	3	0	0	258	1	4.2	20	0	0.5	0	0	0
2024	00-0033873	KC	QB	1	1	30	2	0	0	291	2	8.1	10	0	0.1	0	0	0
\.

--
-- PostgreSQL database dump complete
--
