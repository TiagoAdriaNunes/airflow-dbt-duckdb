{{
    config(
        materialized='view'
    )
}}

with source_data as (

    select * from {{ ref('raw_orders') }}

)

select
    order_id,
    customer_id,
    order_date,
    order_amount,
    current_timestamp as _loaded_at

from source_data
