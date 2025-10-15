{{
    config(
        materialized='table'
    )
}}

with customers as (

    select * from {{ ref('stg_customers') }}

),

orders as (

    select * from {{ ref('stg_orders') }}

),

customer_order_summary as (

    select
        o.customer_id,
        count(*) as total_orders,
        sum(o.order_amount) as total_spent,
        min(o.order_date) as first_order_date,
        max(o.order_date) as last_order_date

    from orders o
    group by o.customer_id

)

select
    c.customer_id,
    c.customer_name,
    c.email,
    c.created_at,
    coalesce(cos.total_orders, 0) as total_orders,
    coalesce(cos.total_spent, 0.0) as total_spent,
    cos.first_order_date,
    cos.last_order_date

from customers c
left join customer_order_summary cos
    on c.customer_id = cos.customer_id
