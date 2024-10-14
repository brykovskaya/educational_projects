/* Проект первого модуля: анализ данных для агентства недвижимости
 * Часть 2. Решаем ad hoc задачи
 * 
 * Автор: Брыковская Н.В.
 * Дата: 10.10.2024
*/

-- Задача 1: Время активности объявлений
-- Результат запроса должен ответить на такие вопросы:
-- а. Какие сегменты рынка недвижимости Санкт-Петербурга и городов Ленинградской области 
--    имеют наиболее короткие или длинные сроки активности объявлений?
-- б. Какие характеристики недвижимости, включая площадь недвижимости, среднюю стоимость квадратного метра, 
--    количество комнат и балконов и другие параметры, влияют на время активности объявлений? 
--    Как эти зависимости варьируют между регионами?
-- в. Есть ли различия между недвижимостью Санкт-Петербурга и Ленинградской области по полученным результатам?

-- Решение задачи 1: Время активности объявлений
--
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдем id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT 
    	id
    FROM 
    	real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits) 
        AND rooms < (SELECT rooms_limit FROM limits) 
        AND balcony < (SELECT balcony_limit FROM limits) 
        AND ceiling_height < (SELECT ceiling_height_limit_h FROM limits) 
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)
    ),
-- Выведем объявления без выбросов присоединим данные о днях продажи по 
--завершенным объявлениям(отфильтруем активные=не имеющие данных в поле с кол-вом дней);
-- присвоим категорию  Санкт-Петербург, если город объявления соответствует идентификатору Санкт-Петербурга,
-- и категорию ЛенОбл, если недвижимость расположена в другом городе.
--сгруппируем объявления по количеству дней активности публикации, выделим такие сегменты активности
-- 1-30 дней
-- 31-90 дней
-- 91-180 дней
-- болеее 181 дней
category_id AS(
    SELECT *,
		CASE 
			WHEN city = 'Санкт-Петербург' 
				THEN 'Санкт-Петербург'
			ELSE 'ЛенОбл'
			END AS регион,
		CASE
			WHEN days_exposition::INT <= 30 THEN '  1 -  30 дней'
			WHEN days_exposition::INT < 91 THEN ' 31 -  90 дней'
			WHEN days_exposition::INT < 181 THEN ' 91 - 181 дней'
			WHEN days_exposition::INT >= 181 THEN '181 и более дней'
		END AS сегмент_активности,	
		ROUND((last_price::NUMERIC / total_area)::NUMERIC, 2) AS price_sq_m, -- стоимость квадратного метра
		COUNT(id) OVER () AS total_id                                        -- закрытых объявлений всего
	FROM 
		real_estate.flats
	LEFT JOIN 
		real_estate.advertisement USING(id)
	LEFT JOIN 
		real_estate.city USING(city_id)
	LEFT JOIN 
		real_estate.type USING(type_id)
	WHERE 
		days_exposition IS NOT NULL           -- оставим только снятые объявления/закрытые
		AND id IN (SELECT * FROM filtered_id) -- отфильтруем выбросы
		AND type = 'город'                    -- оставим  объявл.только в городах
	ORDER BY 
		сегмент_активности DESC
),
stats AS(
	SELECT 
		*,
		COUNT(id) OVER (PARTITION BY регион) AS кв_по_региону,
		COUNT(id) OVER (PARTITION BY сегмент_активности) AS кв_по_рег_сег
	FROM category_id
)
SELECT регион,
	сегмент_активности,
	COUNT(id) AS объявлений,
	ROUND((COUNT(id)::NUMERIC / total_id *  100)::NUMERIC, 2) AS процент,
	кв_по_региону,
	ROUND((кв_по_региону::NUMERIC / total_id *  100)::NUMERIC, 2) AS проц_региона,
	ROUND((кв_по_рег_сег::NUMERIC / total_id *  100)::NUMERIC, 2) AS проц_сегмента,
	ROUND((COUNT(id)::NUMERIC / кв_по_региону *  100)::NUMERIC, 2) AS проц_сегмента_в_рег,
	регион,
	ROUND(AVG(price_sq_m)::NUMERIC, 2) AS ср_стоимость_квМ,
	ROUND(AVG(total_area)::NUMERIC, 2) AS ср_общ_площадь,
	ROUND((AVG(price_sq_m) * AVG(total_area)::NUMERIC / 1000000)::NUMERIC, 2) AS ср_стоим_кв_млн,
	ROUND(100 - (LAG((ROUND((AVG(price_sq_m) * AVG(total_area)::NUMERIC / 1000000)::NUMERIC, 2)),1, (        --стр1
	ROUND((AVG(price_sq_m) * AVG(total_area)::NUMERIC / 1000000)::NUMERIC, 2))) OVER (                       --стр2
	PARTITION BY регион ORDER BY сегмент_активности))::NUMERIC * 100/ ROUND(                                 --стр3
	(AVG(price_sq_m) * AVG(total_area)::NUMERIC / 1000000)::NUMERIC, 2), 2)  								 --стр4	
		AS рост_стоим_к_пред_сегм_проц, --стр5 отношение цены объекта в текущем месяце к прошлому месяцу в проц - больше 100% - рост. меньше - падение
	(percentile_disc(0.5) WITHIN GROUP (ORDER BY rooms))::INT AS медиана_комн,
	(percentile_disc(0.5) WITHIN GROUP (ORDER BY balcony))::INT AS медиана_балк,
	(percentile_disc(0.5) WITHIN GROUP (ORDER BY floor))::INT AS медиана_этажн
FROM 
	stats
GROUP BY 
	регион, 
	сегмент_активности, 
	total_id, 
	кв_по_региону, 
	кв_по_рег_сег
ORDER BY 
	регион DESC, 
	сегмент_активности;

-- Задача 2: Сезонность объявлений
-- Результат запроса должен ответить на такие вопросы:
-- 1. В какие месяцы наблюдается наибольшая активность в публикации объявлений о продаже недвижимости? 
--    А в какие — по снятию? Это показывает динамику активности покупателей.
-- 2. Совпадают ли периоды активной публикации объявлений и периоды, 
--    когда происходит повышенная продажа недвижимости (по месяцам снятия объявлений)?
-- 3. Как сезонные колебания влияют на среднюю стоимость квадратного метра и среднюю площадь квартир? 
--    Что можно сказать о зависимости этих параметров от месяца?

-- Решение задачи 2: Сезонность объявлений
--Считаем, что дата сянтия объявления=дате продажи. У нас есть дата размещения и интервал, через который обхявление закрыто.
--С этими данными найдем дату снятия объявления. Для этого выделим мсяцы из даты публикации и даты снятия объявления
--Отфильтруем данные с выбросами и актуальные/не снятые с публикации объявления.
--Для сравнения активности месяцев по публикации и снятия объявлений —  используем оконные функции ранжирования:
-- это позволит выявить месяцы с наибольшей активностью.
-- период подачи объявлений 2014-11-27 — 2019-05-03 - для сравнения месяцев возьмем полные месяцы и отсечем объявления 
--до  01.12.2014 и после 28.02.2019
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдем id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits) 
        AND rooms < (SELECT rooms_limit FROM limits) 
        AND balcony < (SELECT balcony_limit FROM limits) 
        AND ceiling_height < (SELECT ceiling_height_limit_h FROM limits) 
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)
    ),
--выделим месяц подачи объявления и месяц закрытия объявления-т.к. данные за несколько лет, то используем DATE_TRUNC.
date_extact AS ( 
    SELECT *,
 		COUNT(id) OVER () AS total_close_id,                                 -- закрытых объявлений всего
		ROUND((last_price::NUMERIC / total_area)::NUMERIC, 2) AS price_sq_m, -- стоимость квадратного метра   
		(DATE_TRUNC('month',first_day_exposition::DATE))::DATE AS first_month_exposition,
		EXTRACT(MONTH FROM first_day_exposition::DATE) AS month_start,
		(first_day_exposition::DATE + INTERVAL '1 day' * days_exposition::INT)::DATE AS closed_day_exposition,
		EXTRACT(MONTH FROM (first_day_exposition::DATE + INTERVAL '1 day' * days_exposition::INT)::DATE) AS month_finish,
		(DATE_TRUNC('month', (first_day_exposition::DATE + INTERVAL '1 day' * days_exposition::INT)::DATE))::DATE AS closed_month_exposition
	FROM 
		real_estate.flats
	LEFT JOIN 
		real_estate.advertisement USING(id)
	LEFT JOIN 
		real_estate.city USING(city_id)
	LEFT JOIN 
		real_estate.type USING(type_id)
	WHERE 
		days_exposition IS NOT NULL                                     -- оставим только снятые объявления/закрытые
		AND id IN (SELECT * FROM filtered_id)                           -- отфильтруем выбросы
		AND first_day_exposition BETWEEN  '2014-12-01' AND '2019-02-28' -- учли период 01.12.2014 и после 28.02.2019
		AND type = 'город'                                              -- оставим  объявл.только в городах
	),
stats AS (
	SELECT 
		id, 
		total_close_id, 
		total_area, 
		price_sq_m, 
		rooms, 
		last_price,
		month_start,
		COUNT(id) OVER (PARTITION BY month_start) AS колич_опубл_за_мес,
		ROUND((AVG(price_sq_m) OVER (PARTITION BY month_start)::REAL/1000)::NUMERIC, 1) AS ср_стоим_в_мес_публ_тыс,
		ROUND(AVG(total_area) OVER (PARTITION BY month_start)::NUMERIC, 1) AS ср_площадь_в_мес_публ,
		month_finish,
		COUNT(id) OVER (PARTITION BY month_finish) AS колич_снято_за_мес,
		first_day_exposition::DATE, closed_day_exposition, days_exposition::INT AS days_exposition
	FROM 
		date_extact
),
top_start AS ( 
	SELECT 
		month_start AS месяц_публикации,
		колич_опубл_за_мес,
		ср_стоим_в_мес_публ_тыс, 
		ср_площадь_в_мес_публ,
		NTILE(12) OVER (ORDER BY колич_опубл_за_мес DESC) AS рейтинг
	FROM 
		stats
	GROUP BY 
		month_start, 
		колич_опубл_за_мес, 
		ср_стоим_в_мес_публ_тыс, 
		ср_площадь_в_мес_публ 
),
top_finish AS (
	SELECT 
		month_finish AS месяц_снятия,
		колич_снято_за_мес,
		NTILE(12) OVER (ORDER BY колич_снято_за_мес DESC) AS рейтинг
	FROM 
		stats
	GROUP BY 
		month_finish, 
		колич_снято_за_мес
) 
SELECT 
	рейтинг,
	месяц_публикации,
	месяц_снятия,
	колич_опубл_за_мес,
	колич_снято_за_мес,
	месяц_публикации,
	ср_стоим_в_мес_публ_тыс,
	NTILE(12) OVER (ORDER BY ср_стоим_в_мес_публ_тыс) AS рейтинг_стоимости, -- чем ниже стоимость, тем выше рейтинг, где 1 самый высокий, а 12 низкий
	ср_площадь_в_мес_публ,
	NTILE(12) OVER (ORDER BY ср_площадь_в_мес_публ) AS рейтинг_площ         -- чем меньше площадь, тем выше рейтинг, где 1 самый высокий, а 12 низкий
FROM 
	top_start
LEFT JOIN 
	top_finish AS f USING(рейтинг)
ORDER BY 
	рейтинг;

/* Задача 3: Анализ рынка недвижимости Ленобласти
 Результат запроса должен ответить на такие вопросы:
 1. В каких населённые пунктах Ленинградской области наиболее активно публикуют объявления о продаже недвижимости?
 2. В каких населённых пунктах Ленинградской области — самая высокая доля снятых с публикации объявлений? 
    Это может указывать на высокую долю продажи недвижимости.
 3. Какова средняя стоимость одного квадратного метра и средняя площадь продаваемых квартир 
 	в различных населённых пунктах? 
    Есть ли вариация значений по этим метрикам?
 4. Среди выделенных населённых пунктов какие пункты выделяются по продолжительности публикации объявлений? 
    То есть где недвижимость продаётся быстрее, а где — медленнее.*/

/*--Решение задачи 3: Анализ рынка недвижимости Ленобласти
Осортируем объявления о продаже недвижимости пределами Ленинградской области - исключим Санкт-Петербург г.
также применим фильтрацию, чтобы отсечь аномальные значения
Отсортируем оставшиеся населённые пункты по среднему значению дней активности объявления, разделим объявления на четыре категории по этому показателю.
Выведем рейтинг населённых пунктов в духе «Топ-15 городов», или учитывайте только те населённые пункты, где общее количество объявлений превышает
 определённое значение, к примеру, 50 объявлений. 
Обоснуйте свой выбор порога фильтрации.--*/
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
         PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit
        ,PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit
        ,PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit
        ,PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h
        ,PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM 
    	real_estate.flats     
),
-- Найдем id объявлений, которые не содержат выбросы 
filtered_id AS(
    SELECT 
    	id
    FROM 
    	real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits) 
        AND rooms < (SELECT rooms_limit FROM limits) 
        AND balcony < (SELECT balcony_limit FROM limits) 
        AND ceiling_height < (SELECT ceiling_height_limit_h FROM limits) 
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)
    ),
/* Выведем объявления без выбросов, присоединим нужные поля,
отфильтруем г. СПБ оставим только Ленобласть все населенные пункты :
выведем только поля, которые понадобятся для исследования*/
stats AS(
    SELECT 
    	 city
    	,ROUND(AVG(days_exposition::INT) OVER (PARTITION BY city)) AS avg_days_exp
    	--,total_area
    	,ROUND(AVG(total_area) OVER (PARTITION BY city)) AS avg_total_area
    	,ROUND(	
    		(MIN(total_area) OVER(PARTITION BY city))::NUMERIC
    		, 1) AS min_total_area_city       -- минимальная общая плошадь в населенном пункте
    	,ROUND(	
    		(MAX(total_area) OVER(PARTITION BY city))::NUMERIC
    		, 1) AS max_total_area_city       -- максимальная общая плошадь в населенном пункте
    	,ROUND(
    		(AVG(last_price::REAL / total_area) OVER(PARTITION BY city))::NUMERIC
    		, 1) AS avg_price_sq_m_city       -- средння ст-ть м2 в населенном пункте
    	,ROUND(	
    		(MIN(last_price::REAL / total_area) OVER(PARTITION BY city))::NUMERIC
    		, 1) AS min_price_sq_m_city       -- минимальная ст-ть м2 в населенном пункте
    	,ROUND(	
    		(MAX(last_price::REAL / total_area) OVER(PARTITION BY city))::NUMERIC
    		, 1) AS max_price_sq_m_city       -- максимальная ст-ть м2 в населенном пункте
    	,ROUND(AVG(rooms) OVER (PARTITION BY city)) AS avg_rooms
    	--,floor
    	,ROUND(AVG(floor) OVER (PARTITION BY city)) AS avg_floor
    	--,balcony::INT
    	,ROUND(AVG(balcony) OVER (PARTITION BY city))::INT AS avg_balcony
    	,COUNT(id) OVER () 
			AS ads_total                      -- объявлений всего
		,COUNT(id) OVER (PARTITION BY city) 
			AS ads_city                       -- объявлений всего по населенному пункту
		,COUNT(days_exposition) OVER () 
			AS ads_closed                     -- закрытых объявлений всего
		,COUNT(days_exposition) OVER (PARTITION BY city) 
			AS ads_close_city                 -- закрытых объявлений в населенном пункте
		--,ROUND(AVG(rooms) OVER (PARTITION BY city)) AS avg_rooms
	FROM 
		real_estate.flats
	LEFT JOIN 
			real_estate.advertisement USING(id)    -- добавляем данные о размещении объявлнений
	LEFT JOIN 
		real_estate.city USING(city_id)        -- добавляем название городов
	WHERE 
		id IN (SELECT * FROM filtered_id)      -- отфильтруем выбросы
		AND city <> 'Санкт-Петербург'          -- исключим Спб
	ORDER BY 
		avg_days_exp  DESC
),
--сгруппируем по городу и отфильтруем населенные пункты,в которых нет проданных объявлений () 
stats_2 AS ( 
	SELECT 
 		 city
 		,avg_days_exp
    	,avg_total_area
    	,min_total_area_city       -- минимальная общая плошадь в населенном пункте
    	,max_total_area_city       -- максимальная общая плошадь в населенном пункте
    	,avg_price_sq_m_city       -- средння ст-ть м2 в населенном пункте
    	,min_price_sq_m_city       -- минимальная ст-ть м2 в населенном пункте
    	,max_price_sq_m_city       -- максимальная ст-ть м2 в населенном пункте
    	,avg_rooms
    	,avg_floor
    	,avg_balcony
    	,ads_total                      -- объявлений всего
		,ads_city                       -- объявлений всего по населенному пункту
		,ads_closed                     -- закрытых объявлений всего
		,ads_close_city                 -- закрытых объявлений в населенном пункте	
	FROM 
		stats
	WHERE 
		avg_days_exp IS NOT NULL        -- исключили строки по городам в которых нет закрытых объявлений
	GROUP BY
		 city
	   	,avg_days_exp
    	,avg_total_area
    	,min_total_area_city       
    	,max_total_area_city       
    	,avg_price_sq_m_city       
    	,min_price_sq_m_city       
    	,max_price_sq_m_city       
    	,avg_rooms
    	,avg_floor
    	,avg_balcony
    	,ads_total                      
		,ads_city                       
		,ads_closed                     
		,ads_close_city                 
		),
--разделим получившиеся объявления на 4 группы	по сроку продажи				
group_avg_days AS (
	SELECT 
		*
		,COUNT(city) OVER () AS cnt_city
 		,NTILE(4) OVER (ORDER BY avg_days_exp) AS n_tile
	FROM 
		stats_2
	ORDER BY 
		ads_close_city DESC,
   		avg_days_exp ASC
 )
--данные из 150 населенных пунктов отфильтруем и оставим только TOП-15 населенных пунктов по общему числу размещенных объявлений.
--Это отсеит населенные пункты, в которых очень низкая доля объявлений среди всех размещенных объявлеий в Лен.области.
SELECT 
	 city
	,avg_days_exp
	,ROW_NUMBER() OVER (ORDER BY avg_days_exp) 
		AS top_days_exp          -- на 1 месте с меньшим средним кол-вом дней экспозиции
	,avg_total_area
    ,min_total_area_city       
    ,max_total_area_city
    ,city
    ,avg_price_sq_m_city       
    ,min_price_sq_m_city       
    ,max_price_sq_m_city       
    ,avg_rooms
    ,avg_floor
    ,avg_balcony
    ,city
    ,ads_total
    ,ads_city
    ,ROUND((ads_city::REAL / ads_total)::NUMERIC ,3) 
		AS ratio_ads             -- доля объявлений в городе от всех объявлений	
	,ads_closed                     
	,ads_close_city
	,ROUND((ads_close_city::REAL / ads_closed)::NUMERIC ,3) 
		AS ratio_ads_closed      -- доля снятых объявлений в городе от всех снятых с публ.объявлений	
	,city
	,ROW_NUMBER() OVER (ORDER BY ads_city DESC) 
		AS top_ads				 -- на 1 месте с наибольшим числом размещенных объявлений
	,ROW_NUMBER() OVER (ORDER BY avg_price_sq_m_city DESC) 
		AS top_price_sq_m        -- на 1 месте с смаой высокой ценой
FROM (
	SELECT
		*
	FROM 
		group_avg_days
	ORDER BY
		ads_city DESC
	LIMIT 15
	) AS t
ORDER BY 
	avg_days_exp;

