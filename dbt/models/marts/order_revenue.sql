{{
    config(
        materialized='table'
    )
}}

with orders as (

    select * from {{ ref('stg_orders') }}

),

lineitem as (

    select * from {{ ref('stg_lineitem') }}

),

revenue_by_order as (

    select
        order_id,
        sum(net_price)      as net_revenue,
        sum(gross_price)    as gross_revenue,
        sum(quantity)       as total_quantity,
        count(*)            as line_count,
        count(case when return_flag = 'R' then 1 end) as returned_lines

    from lineitem
    group by order_id

)

select
    o.order_id,
    o.customer_id,
    o.order_date,
    o.order_status,
    o.order_priority,
    o.clerk,
    o.order_amount                                              as list_price,
    r.net_revenue,
    r.gross_revenue,
    r.total_quantity,
    r.line_count,
    r.returned_lines,
    round(r.net_revenue / nullif(r.total_quantity, 0), 2)      as avg_net_price_per_unit,
    round(r.returned_lines * 100.0 / nullif(r.line_count, 0), 2) as return_rate_pct

from orders o
left join revenue_by_order r on o.order_id = r.order_id
