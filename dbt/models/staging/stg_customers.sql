{{
    config(
        materialized='view'
    )
}}

with source_data as (

    select * from {{ source('tpch', 'customer') }}

)

select
    c_custkey       as customer_id,
    c_name          as customer_name,
    c_phone         as phone,
    c_address       as address,
    c_acctbal       as account_balance,
    c_mktsegment    as market_segment,
    c_nationkey     as nation_key,
    current_timestamp as _loaded_at

from source_data
