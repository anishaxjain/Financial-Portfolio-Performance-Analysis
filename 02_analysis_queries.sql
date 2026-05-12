-- =========================================
-- Financial Portfolio Performance Analysis
-- Exploratory SQL Analysis Queries
-- =========================================

-- =========================================
-- 1. Daily Return by Stock
-- Purpose: Calculate day-over-day return for each stock.
-- =========================================
SELECT
    Ticker,
    Date,
    Adjusted AS close_price,
    LAG(Adjusted) OVER (
        PARTITION BY Ticker
        ORDER BY Date
    ) AS previous_close,
    (Adjusted - LAG(Adjusted) OVER (
        PARTITION BY Ticker
        ORDER BY Date
    )) / LAG(Adjusted) OVER (
        PARTITION BY Ticker
        ORDER BY Date
    ) AS daily_return
FROM portfolio_prices
ORDER BY Ticker, Date;


-- =========================================
-- 2. Total Return by Stock
-- Purpose: Identify which stocks had the highest total return.
-- =========================================
WITH ranked_prices AS (
    SELECT
        Ticker,
        Date,
        Adjusted,
        ROW_NUMBER() OVER (
            PARTITION BY Ticker
            ORDER BY Date ASC
        ) AS first_rank,
        ROW_NUMBER() OVER (
            PARTITION BY Ticker
            ORDER BY Date DESC
        ) AS last_rank
    FROM portfolio_prices
),
first_last_prices AS (
    SELECT
        Ticker,
        MAX(CASE WHEN first_rank = 1 THEN Adjusted END) AS first_price,
        MAX(CASE WHEN last_rank = 1 THEN Adjusted END) AS last_price
    FROM ranked_prices
    GROUP BY Ticker
)
SELECT
    Ticker,
    first_price,
    last_price,
    ((last_price - first_price) / first_price) * 100 AS total_return_percent
FROM first_last_prices
ORDER BY total_return_percent DESC;


-- =========================================
-- 3. Portfolio Value Over Time
-- Purpose: Calculate daily portfolio value based on holdings.
-- =========================================
SELECT
    p.Date,
    SUM(p.Adjusted * h.Quantity) AS portfolio_value
FROM portfolio_prices p
JOIN portfolio_holdings h
    ON p.Ticker = h.Ticker
GROUP BY p.Date
ORDER BY p.Date;


-- =========================================
-- 4. Portfolio Allocation by Sector
-- Purpose: Show how much portfolio value is allocated to each sector.
-- =========================================
SELECT
    Sector,
    SUM(Quantity * Close) AS sector_value,
    SUM(Quantity * Close) * 100.0 / SUM(SUM(Quantity * Close)) OVER () AS sector_allocation_percent
FROM portfolio_holdings
GROUP BY Sector
ORDER BY sector_value DESC;


-- =========================================
-- 5. Volatility by Stock
-- Purpose: Calculate daily and annualized volatility.
-- =========================================
WITH daily_returns AS (
    SELECT
        Ticker,
        Date,
        (Adjusted - LAG(Adjusted) OVER (
            PARTITION BY Ticker
            ORDER BY Date
        )) / LAG(Adjusted) OVER (
            PARTITION BY Ticker
            ORDER BY Date
        ) AS daily_return
    FROM portfolio_prices
)
SELECT
    Ticker,
    STDEV(daily_return) AS daily_volatility,
    STDEV(daily_return) * SQRT(252) AS annualized_volatility
FROM daily_returns
WHERE daily_return IS NOT NULL
GROUP BY Ticker
ORDER BY annualized_volatility DESC;


-- =========================================
-- 6. Best and Worst Performing Holdings
-- Purpose: Identify top and bottom performers.
-- =========================================
WITH ranked_prices AS (
    SELECT
        Ticker,
        Date,
        Adjusted,
        ROW_NUMBER() OVER (
            PARTITION BY Ticker
            ORDER BY Date ASC
        ) AS first_rank,
        ROW_NUMBER() OVER (
            PARTITION BY Ticker
            ORDER BY Date DESC
        ) AS last_rank
    FROM portfolio_prices
),
first_last_prices AS (
    SELECT
        Ticker,
        MAX(CASE WHEN first_rank = 1 THEN Adjusted END) AS first_price,
        MAX(CASE WHEN last_rank = 1 THEN Adjusted END) AS last_price
    FROM ranked_prices
    GROUP BY Ticker
),
returns AS (
    SELECT
        Ticker,
        first_price,
        last_price,
        ((last_price - first_price) / first_price) * 100 AS total_return_percent
    FROM first_last_prices
)
SELECT TOP 5
    Ticker,
    first_price,
    last_price,
    total_return_percent
FROM returns
ORDER BY total_return_percent DESC;

SELECT TOP 5
    Ticker,
    first_price,
    last_price,
    total_return_percent
FROM returns
ORDER BY total_return_percent ASC;


-- =========================================
-- 7. Portfolio vs S&P 500 Benchmark
-- Purpose: Compare portfolio growth against the S&P 500.
-- =========================================
WITH portfolio_value AS (
    SELECT
        p.Date,
        SUM(p.Adjusted * h.Quantity) AS portfolio_value
    FROM portfolio_prices p
    JOIN portfolio_holdings h
        ON p.Ticker = h.Ticker
    GROUP BY p.Date
),
portfolio_indexed AS (
    SELECT
        Date,
        portfolio_value,
        portfolio_value * 100.0 / FIRST_VALUE(portfolio_value) OVER (
            ORDER BY Date
        ) AS portfolio_index
    FROM portfolio_value
),
sp500_indexed AS (
    SELECT
        Date,
        Adjusted AS sp500_close,
        Adjusted * 100.0 / FIRST_VALUE(Adjusted) OVER (
            ORDER BY Date
        ) AS sp500_index
    FROM sp500_prices
)
SELECT
    p.Date,
    p.portfolio_index,
    s.sp500_index,
    p.portfolio_index - s.sp500_index AS performance_difference
FROM portfolio_indexed p
JOIN sp500_indexed s
    ON p.Date = s.Date
ORDER BY p.Date;


-- =========================================
-- 8. Portfolio Gain/Loss by Holding
-- Purpose: Calculate dollar contribution of each holding.
-- =========================================
WITH ranked_prices AS (
    SELECT
        Ticker,
        Date,
        Adjusted,
        ROW_NUMBER() OVER (
            PARTITION BY Ticker
            ORDER BY Date ASC
        ) AS first_rank,
        ROW_NUMBER() OVER (
            PARTITION BY Ticker
            ORDER BY Date DESC
        ) AS last_rank
    FROM portfolio_prices
),
first_last_prices AS (
    SELECT
        Ticker,
        MAX(CASE WHEN first_rank = 1 THEN Adjusted END) AS first_price,
        MAX(CASE WHEN last_rank = 1 THEN Adjusted END) AS last_price
    FROM ranked_prices
    GROUP BY Ticker
)
SELECT
    h.Ticker,
    h.Sector,
    h.Quantity,
    f.first_price,
    f.last_price,
    h.Quantity * f.first_price AS starting_value,
    h.Quantity * f.last_price AS ending_value,
    h.Quantity * (f.last_price - f.first_price) AS gain_loss,
    ((f.last_price - f.first_price) / f.first_price) * 100 AS return_percent
FROM portfolio_holdings h
JOIN first_last_prices f
    ON h.Ticker = f.Ticker
ORDER BY gain_loss DESC;