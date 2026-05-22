WITH max_date AS (
    SELECT MAX(order_purchase_timestamp) AS maxim_date 
    FROM orders 
    WHERE order_status != 'canceled'
),
rfm_base AS (
    SELECT 
        c.customer_unique_id,
        DATEDIFF((SELECT maxim_date FROM max_date), MAX(o.order_purchase_timestamp)) AS recency,
        COUNT(DISTINCT o.order_id) AS frequency,
        SUM(oi.freight_value + oi.price) AS monetary
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status != 'canceled'
    GROUP BY c.customer_unique_id
),
rfm_scores AS (
    SELECT 
        customer_unique_id,
        recency,
        frequency,
        monetary,
        -- Recency: Shorter days = Better score (1 to 5)
        NTILE(5) OVER (ORDER BY recency ASC) AS r_score,
        
        -- Frequency Fix: Handled explicitly due to severe data skew
        CASE 
            WHEN frequency >= 4 THEN 5
            WHEN frequency = 3 THEN 4
            WHEN frequency = 2 THEN 3
            ELSE 1 -- Failsafe for 1 purchase
        END AS f_score,
        
        -- Monetary: Higher spend = Better score (1 to 5)
        NTILE(5) OVER (ORDER BY monetary DESC) AS m_score
    FROM rfm_base
),
rfm_segments AS (
    SELECT *,
           CONCAT(r_score, f_score, m_score) AS rfm_id,
           CASE
               WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
               WHEN r_score >= 3 AND f_score >= 3 THEN 'Loyal'
               WHEN r_score <= 2 AND f_score >= 3 THEN 'At Risk'
               WHEN r_score = 1 AND f_score = 1 THEN 'Lost'
               ELSE 'Others'
           END AS customer_segment
    FROM rfm_scores
),
segment_aggregates AS (
    SELECT
        customer_segment,
        COUNT(*) AS total_customers,
        AVG(monetary) AS avg_revenue,
        SUM(monetary) AS total_revenue
    FROM rfm_segments
    GROUP BY customer_segment
)
-- Final Select fixes the nested window function issue cleanly
SELECT 
    customer_segment,
    total_customers,
    ROUND(avg_revenue, 2) AS avg_revenue,
    ROUND(total_revenue, 2) AS total_revenue,
    ROUND(total_revenue * 100.0 / SUM(total_revenue) OVER(), 2) AS revenue_percentage
FROM segment_aggregates
ORDER BY total_revenue DESC;
