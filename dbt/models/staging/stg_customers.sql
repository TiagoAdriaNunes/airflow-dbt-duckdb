{{
    config(
        materialized='view'
    )
}}

with source_data as (

    select * from {{ ref('raw_customers') }}

)

select
    customer_id,
    customer_name,
    email,
    created_at,
    current_timestamp as _loaded_at

from source_data
