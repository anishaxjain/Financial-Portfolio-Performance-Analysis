-- =========================================
-- Financial Portfolio Performance Analysis
-- SQL Server Views for Power BI Dashboard
-- =========================================

CREATE SCHEMA finance;
GO

-- =========================================
-- View 1: Daily Returns by Stock
-- =========================================
CREATE OR ALTER VIEW finance.vw_daily_returns_by_stock AS
WITH daily_returns AS (
    SELECT
        Ticker,
        Date,
        Adjusted AS close_price,
        LAG(Adjusted) OVER (
            PARTITION BY Ticker
            ORDER BY Date
        ) AS previous_close
    FROM portfolio_prices
)
SELECT
    Ticker,
    Date,
    close_price,
    previous_close,
    CASE
        WHEN previous_close IS NULL OR previous_close = 0 THEN NULL
        ELSE (close_price - previous_close) / previous_close
    END AS daily_return
FROM daily_returns;
GO

-- =========================================
-- View 2: Total Return by Stock
-- =========================================
CREATE OR ALTER VIEW finance.vw_stock_total_returns AS
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
FROM first_last_prices;
GO

-- =========================================
-- View 3: Portfolio Value Over Time
-- =========================================
CREATE OR ALTER VIEW finance.vw_portfolio_value_over_time AS
SELECT
    p.Date,
    SUM(p.Adjusted * h.Quantity) AS portfolio_value
FROM portfolio_prices p
JOIN portfolio_holdings h
    ON p.Ticker = h.Ticker
GROUP BY p.Date;
GO

-- =========================================
-- View 4: Sector Allocation
-- =========================================
CREATE OR ALTER VIEW finance.vw_sector_allocation AS
SELECT
    Sector,
    SUM(Quantity * [Close]) AS sector_value,
    SUM(Quantity * [Close]) * 100.0 / SUM(SUM(Quantity * [Close])) OVER () AS sector_allocation_percent
FROM portfolio_holdings
GROUP BY Sector;
GO

-- =========================================
-- View 5: Volatility by Stock
-- =========================================
CREATE OR ALTER VIEW finance.vw_stock_volatility AS
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
GROUP BY Ticker;
GO

-- =========================================
-- View 6: Best and Worst Holdings
-- =========================================
CREATE OR ALTER VIEW finance.vw_best_worst_holdings AS
WITH ranked_returns AS (
    SELECT
        Ticker,
        first_price,
        last_price,
        total_return_percent,
        ROW_NUMBER() OVER (
            ORDER BY total_return_percent DESC
        ) AS best_rank,
        ROW_NUMBER() OVER (
            ORDER BY total_return_percent ASC
        ) AS worst_rank
    FROM finance.vw_stock_total_returns
)
SELECT
    Ticker,
    first_price,
    last_price,
    total_return_percent,
    CASE
        WHEN best_rank = 1 THEN 'Best Performer'
        WHEN worst_rank = 1 THEN 'Worst Performer'
        ELSE 'Other'
    END AS performance_category
FROM ranked_returns
WHERE best_rank = 1 OR worst_rank = 1;
GO

-- =========================================
-- View 7: Portfolio vs S&P 500
-- =========================================
CREATE OR ALTER VIEW finance.vw_portfolio_vs_sp500 AS
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
    p.portfolio_value,
    p.portfolio_index,
    s.sp500_close,
    s.sp500_index,
    p.portfolio_index - s.sp500_index AS performance_difference
FROM portfolio_indexed p
JOIN sp500_indexed s
    ON p.Date = s.Date;
GO

-- =========================================
-- View 8: Dashboard Summary KPIs
-- =========================================
CREATE OR ALTER VIEW finance.vw_dashboard_summary AS
WITH portfolio_value AS (
    SELECT
        Date,
        portfolio_value
    FROM finance.vw_portfolio_value_over_time
),
ranked_values AS (
    SELECT
        Date,
        portfolio_value,
        ROW_NUMBER() OVER (ORDER BY Date ASC) AS first_rank,
        ROW_NUMBER() OVER (ORDER BY Date DESC) AS last_rank
    FROM portfolio_value
),
summary AS (
    SELECT
        MAX(CASE WHEN first_rank = 1 THEN portfolio_value END) AS starting_portfolio_value,
        MAX(CASE WHEN last_rank = 1 THEN portfolio_value END) AS ending_portfolio_value
    FROM ranked_values
),
best_worst AS (
    SELECT
        MAX(CASE WHEN performance_category = 'Best Performer' THEN Ticker END) AS best_stock,
        MAX(CASE WHEN performance_category = 'Best Performer' THEN total_return_percent END) AS best_stock_return,
        MAX(CASE WHEN performance_category = 'Worst Performer' THEN Ticker END) AS worst_stock,
        MAX(CASE WHEN performance_category = 'Worst Performer' THEN total_return_percent END) AS worst_stock_return
    FROM finance.vw_best_worst_holdings
)
SELECT
    s.starting_portfolio_value,
    s.ending_portfolio_value,
    s.ending_portfolio_value - s.starting_portfolio_value AS total_gain_loss,
    ((s.ending_portfolio_value - s.starting_portfolio_value) / s.starting_portfolio_value) * 100 AS total_return_percent,
    b.best_stock,
    b.best_stock_return,
    b.worst_stock,
    b.worst_stock_return
FROM summary s
CROSS JOIN best_worst b;
GO