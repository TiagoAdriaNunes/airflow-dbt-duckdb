{{
    config(
        materialized='view'
    )
}}

with source_data as (

    select * from {{ source('tpch', 'orders') }}

)

select
    o_orderkey      as order_id,
    o_custkey       as customer_id,
    o_totalprice    as order_amount,
    o_orderdate     as order_date,
    o_orderstatus   as order_status,
    o_orderpriority as order_priority,
    o_clerk         as clerk,
    current_timestamp as _loaded_at

from source_data
