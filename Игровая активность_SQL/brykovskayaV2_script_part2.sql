/* Проект «Секреты Тёмнолесья»
 * Цель проекта: изучить влияние характеристик игроков и их игровых персонажей 
 * на покупку внутриигровой валюты «райские лепестки», а также оценить 
 * активность игроков при совершении внутриигровых покупок
 * 
 * Автор: Брыковская Наталья
 * Дата: 24  .09.2024
*/

-- Часть 1. Исследовательский анализ данных
-- Задача 1. Исследование доли платящих игроков

-- 1.1. Доля платящих пользователей по всем данным:
-- Напишите ваш запрос здесь
WITH 
cte AS (
	SELECT 
		(SELECT 
			COUNT(payer) 
			FROM fantasy.users) AS total_users,                      --общее количество игроков в игре
		(SELECT 
			COUNT(payer) 
			FROM fantasy.users
			WHERE payer = 1) AS payer_users                          -- общее количество платящих игроков в игре
)
SELECT 
	*,
	payer_users::NUMERIC / total_users AS part_payer_users           -- доля платящих игроков
FROM  
	cte;
-- 1.2. Доля платящих пользователей в разрезе расы персонажа:
WITH 
stat1 AS (
	SELECT 
		r.race,
		SUM(payer) OVER (PARTITION BY u.race_id) AS payer_race,      -- кол-во платящих игроков расы
		COUNT(payer) OVER (PARTITION BY u.race_id) AS all_race_user, -- кол-во всех игроков расы
		AVG(payer) OVER (PARTITION BY u.race_id) AS part_payer_race  -- доля платящих игроков расы
	FROM fantasy.users AS u
	LEFT JOIN fantasy.race AS r ON u.race_id=r.race_id
			)
SELECT *
FROM 
	stat1
GROUP BY 
	race, 
	payer_race, 
	all_race_user, 
	part_payer_race
ORDER BY 
	part_payer_race DESC;

-- Задача 2. Исследование внутриигровых покупок

-- 2.1. Статистические показатели по полю amount:
SELECT 
	COUNT(amount) AS total_count, 					       				  -- общее кол-во покупок
	SUM(amount) AS total_amount,  						  				  -- сумма всех покупок
	MIN(amount) AS min_amount,    						  				  -- мин. сумма покупки
	MAX(amount) AS max_amount,     						  				  -- макс.сумма покупки 
	ROUND(AVG(amount)::NUMERIC,2) AS avg_amount,						  -- средняя сумма покупки
	PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY amount) AS median_amount, -- медиана суммы покупки
	ROUND(STDDEV(amount)::NUMERIC, 2) AS stand_dev_amount				  -- станд.отклонение		
FROM 
	fantasy.events;

-- 2.2: Аномальные нулевые покупки:
WITH 
cte AS (
	SELECT 
		COUNT(amount) AS total_count, 		               -- общее кол-во покупок
		(SELECT 
			COUNT(amount)
			FROM 
				fantasy.events
			WHERE 
				amount=0 OR amount IS NULL
		) AS zero_amount 					               -- покупки с нулевой стоимостью
	FROM fantasy.events
	)
SELECT
	zero_amount,
	zero_amount::NUMERIC / total_count AS part_zero_amount -- доля покупок с нулевой стоимостью
FROM 
	cte;

-- 2.3: Сравнительный анализ активности платящих и неплатящих игроков:
WITH 
cte AS (
	SELECT
		e.id,
		u.payer, 									  					 -- группа игрока: платящий/неплатящий
		COUNT(amount) AS total_purchase_per_user, 	 					 -- общее кол-во покупок на игрока
		SUM(amount) AS total_amount_per_user							 -- сумма всех покупок на уникального игрока
	FROM 
		fantasy.events AS e 
	JOIN 
		fantasy.users AS u ON u.id=e.id 
	WHERE 
		amount <> 0 												     -- исключаем покупки с нулевой стоимостью
	GROUP BY 
		payer, e.id  
	)
SELECT
	CASE
		WHEN payer = 0
			THEN 'неплатящий'
		WHEN payer = 1
			THEN 'платящий'
	END AS payer_type, 														   -- группа игроков: платящий/неплатящий
	COUNT(id) AS total_users,                 					               -- общее кол-во игроков
	SUM(total_purchase_per_user) AS total_purchase,  					       -- кол-во покупок
	ROUND(SUM(total_purchase_per_user)::NUMERIC / COUNT(id)) AS avg_purchase,  -- ср.кол-во покупок на игрока
	ROUND(SUM(total_amount_per_user)::NUMERIC / COUNT(user),2) AS avg_amount   -- ср.ст-ть покупки на игрока
FROM 
	cte
GROUP BY 
	payer;

-- 2.4: Популярные эпические предметы:

--/считаем статистику по эпическим предметам/
WITH 
cte AS (
	SELECT 
		item_code AS item_code,		            -- эпический предмет
	    COUNT(DISTINCT id) AS users_per_item,   -- кол-во уник.игроков, купивших хотябы раз
	    COUNT(item_code) AS purchase_per_item   -- сколько раз предмет был куплен
	FROM 
		fantasy.events
	WHERE 
		amount <> 0                             -- исключаем покупки с нулевой стоимостью
	GROUP BY 
		item_code 
		),
--/считаем общую статистику/--
cte1 AS (
	SELECT 
		COUNT(transaction_id) AS total_purchase,                                               -- общее кол-во покупок
		COUNT(DISTINCT id) AS total_users                                                      -- общее кол-во покупателей
	FROM 
		fantasy.events
	WHERE 
		amount <> 0                           												   -- исключаем покупки с нулевой стоимостью
		)
--/основной запрос/--
SELECT 
	game_items, 																			   -- эпический предмет(название)
	purchase_per_item,
	purchase_per_item::NUMERIC / (SELECT total_purchase FROM cte1) AS part_of_total_purschase, -- доля среди всех покупок
	users_per_item::NUMERIC / (SELECT total_users FROM cte1) AS part_of_total_users            -- доля среди хоть раз купивших игроков
FROM 
	cte
JOIN 
	fantasy.items AS i ON i.item_code=cte.item_code 
ORDER BY 
	part_of_total_users DESC;

-- Часть 2. Решение ad hoc-задач
-- Задача 1. Зависимость активности игроков от расы персонажа:
--/формируем нужные поля в одну таблицу,считаем общие показатели/--
WITH tab1 AS(SELECT 
	e.id,
	payer,
	amount,
	race_id,
	race,
	reg_users,
	reg_users_race
FROM 
	fantasy.events e 
LEFT OUTER JOIN 
	(  -- подзапрос - подсчитаем зарегистрированных пользователей всего и в разрезе расы
		SELECT race_id,
			payer,
			id,
			COUNT(id) OVER () AS reg_users, -- кол-во всех зарегистр пользователей
			COUNT(id) OVER (PARTITION BY race_id) AS reg_users_race -- кол-во всех зарегистр пользователей по расе
		FROM fantasy.users 
	) AS u USING(id)	
LEFT OUTER JOIN 
	fantasy.race AS r USING(race_id)
WHERE amount <> 0                             -- исключаем покупки с нулевой стоимостью
),
tab2 AS 
( 
SELECT *,
COUNT(amount) OVER (PARTITION BY id) AS count_purch_id,    -- кол-во покупок пользователя
COUNT(amount) OVER (PARTITION BY race) AS count_purch_race,-- кол-во покупок по расе персонажа
SUM(amount) OVER (PARTITION BY race) AS total_amount_race  -- сумма покупок по расе
FROM tab1
),
tab3 AS (
	SELECT
		id, 
		payer, 
		race, 
		count_purch_race, 
		total_amount_race,
		count_purch_id,
		reg_users,
	reg_users_race
FROM tab2
	GROUP BY 
		id, 
		payer, 
		race,
		count_purch_race,
		total_amount_race,
		count_purch_id,
		reg_users,
	reg_users_race
ORDER BY race
),
tab4 AS
(
		SELECT 
		payer, 
		race, 
		count_purch_race, 
		total_amount_race,
		reg_users,
	reg_users_race,
		COUNT(id) OVER () AS active_users,                   -- всего купивших эпические предметы по всем расам
	COUNT(id) OVER (PARTITION BY race) AS active_users_race, -- кол-во купивших эпические предметы(за деньги и без денег) по расам
	COUNT(id) OVER (PARTITION BY race, payer) AS active_users_race_payer -- кол-во купивших (за деньги и без денег) по расам и виду покупки(за деньги без денег)
FROM tab3
GROUP BY payer, race, count_purch_race, total_amount_race, id, count_purch_id, reg_users,
	reg_users_race
)
SELECT 
	race,
	reg_users_race,                                                       -- общее кол-во зарегистрированных игроков по каждой расе
	active_users_race,                                                    -- общее кол-во активных игроков по каждой расе(покупающих за деньги и без)
	ROUND(active_users_race::NUMERIC/reg_users_race, 4) AS part_active_users_race,               -- доля активных игроков расы от зарег. игроков расы
	ROUND(active_users_race_payer::NUMERIC/active_users_race, 4) AS part_active_users_race_payer,-- доля платящих игроков каждой расы от активных игроков каждой расы
	ROUND(count_purch_race::NUMERIC / active_users_race) AS avg_purchase,         -- среднее кол-во покупок на одного активного игрока каждой расе
	ROUND(total_amount_race::NUMERIC / count_purch_race, 2) AS avg_amount,        --средняя стоимость одной покупки 
	ROUND(total_amount_race::NUMERIC / active_users_race, 2) AS avg_total_amount  --средняя суммарная стоимость всех покупок на одного игрока
FROM tab4
WHERE 
	payer = 1 -- оставляем в таблице информацию только по доле платящих деньгами, убираем остальные дублирующиеся данные
GROUP BY 
	race, 
	reg_users_race, 
	active_users_race, 
	part_active_users_race,  
	part_active_users_race_payer, 
	avg_purchase, avg_amount, 
	avg_total_amount
ORDER BY 
reg_users_race DESC;

-- Задача 2: Частота покупок
--/ШАГ1 используем данные из таблиц events + users--
--посчитаем количество заказов для каждого пользователя.
--исключим игроков у которых менее 25 покупок и покупки с нулевой стоимостью, согласно условиям ТЗ
--в подзапросе найдем дату сл.покупки и в основном запросе добавим столбец с информацией о кол-ве дней между покупками игрока/--
WITH 
main_tab AS 
( 
	SELECT 
		transaction_id,								-- идентификатор покупки
		tab.id,										-- идентификатор игрока
		session_next - session_start AS days_befor, -- кол-во дней между предыдущей и текущей покупкой
		payer, 										-- код игрока:платящий реальные деньги игрок -1, не платящий - 0.
		purchase 									-- общее кол-во покупок каждого игрока
	FROM (
		SELECT 
			transaction_id,					
			id,							
			date::date AS session_start,															  -- дата покупки
			amount, 						
			COUNT(transaction_id) OVER (PARTITION BY fantasy.events.id) AS purchase,                  
			LEAD(date::date,1, date::date) OVER (PARTITION BY id ORDER BY date::date) AS session_next --  дата следующей покупки
		FROM fantasy.events 
		WHERE 
			amount <> 0
		ORDER BY date::date
		) AS tab
	LEFT JOIN fantasy.users AS u ON tab.id=u.id	
	WHERE purchase >=25
	ORDER BY purchase
),
--/ШАГ 2  используем данные из СТЕ main_tab
-- найдем среднее кол-во дней с предыдущей покупке для каждого игрока в подзапросе. 
--не округляем, т.к. далее будем находить среднее от среднего.
-- сгруппируем информацию по каждому игроку
stats_tab AS 
(
	SELECT 
		id,						-- идентификатор игрока
		avg_days,  				-- среднее кол-во дней между покупками у каждого игрока
		payer, 					-- код игрока:платящий реальные деньги игрок -1, не платящий - 0.
		purchase 				-- общее кол-во покупок каждого игрока
	FROM (
		SELECT 
			*,
			AVG(days_befor) OVER (PARTITION BY id) AS avg_days -- среднее кол-во дней между покупками у каждого игрока
		FROM 
			main_tab
		) AS st_t
	GROUP BY 
		id,						
		avg_days,  				
		payer, 					
		purchase
	ORDER BY avg_days DESC
),
--/ШАГ3. Используем данные из СТЕ stats_tab
--в подзапросе проранжируем уникальных игроков на 3 группы
--в запросе каждой группе присвоим название с помощью условного оператора case 
--где 1- низкая частота, 2- умеренная частота, 3 - высокая частота.
-- добавим информацию о количестве игроков в каждой группе, 
--а также о количестве игроков по payer для каждой группе, где 1 платящий, 0- не платящий,
--а также найдем среднее число дней между покупками в каждой группе. дни округлим до целого.
--а также найдем среднее кол-во покупок для каждой группы. округлим до целого.
group_tab AS 
(
	SELECT 
		*,
		CASE
			WHEN rank_id = 1 
				THEN 'высокая частота'
			WHEN rank_id = 2 
				THEN 'умеренная частота'
			WHEN rank_id = 3 
				THEN 'низкая частота'	
		END	AS frequency, 													-- частота покупок
		COUNT(id) OVER (PARTITION BY rank_id) AS users_gr,                  -- кол-во игроков совершивших покупки в группе
		COUNT(id) OVER (PARTITION BY rank_id, payer) AS users_gr_money,     -- кол-во платящих игроков совершивших покупки в группе
		ROUND(AVG(avg_days) OVER (PARTITION BY rank_id)) AS avg_days_gr,    -- среднее кол-во дней между покупками на одного игрока в группе
		ROUND(AVG(purchase) OVER (PARTITION BY rank_id)) AS avg_purchase_gr -- среднее кол-во покупок на одного игрока в группе
	FROM 
		(
		SELECT *,
		NTILE(3) OVER (ORDER BY avg_days) AS rank_id 						-- ранг игрока по частоте покупок		
		FROM stats_tab
		) AS gr_t
),
--ШАГ4. Используем данные из СТЕ  group_tab
--посчитаем долю платящих игроков деньгами и неплатящих и сгруппируем все данные
stats_group AS
( 
	SELECT 
		rank_id,
		frequency,
		payer,
		users_gr, 														 
		users_gr_money,                                                   
		ROUND(users_gr_money::NUMERIC / users_gr, 3) AS part_payer_users,  -- доля платящих/неплатящих от общего числа игроков в группе
		avg_days_gr, 
		avg_purchase_gr 
	FROM group_tab
	GROUP BY
		rank_id,
		frequency,
		payer,
		users_gr, 
		users_gr_money, 
		avg_days_gr, 
		avg_purchase_gr 
)
--ШАГ5. Используем данные из СТЕ  stats_group 
--ОСНОВОЙ ЗАПРОС
--выведем все необходимые показатели, отфильтруем таблицу по столбцу payer - 
--чтобы показать долю только платящих деньгами игроков и убрать остальные дублирующие значения одинаковые для группы игроков.
SELECT 
	frequency,        -- частота покупок
	users_gr,         -- кол-во игроков, совершивших покупки
	users_gr_money,   -- кол-во платящих деньгами игроков в группе
	part_payer_users, -- доля платящих деньгами игроков в группе(от числа игроков группы)
	avg_days_gr, 	  -- среднее количество дней между покупками на одного игрока в группе
	avg_purchase_gr   -- среднее количество покупок на одного игрока в группе
FROM stats_group
WHERE payer = 1;      -- отфильтруем итоговую таблицу по платящим деньгами