{{
    config(
        materialized='view'
    )
}}

with source_data as (

    select * from {{ source('tpch', 'lineitem') }}

)

select
    l_orderkey                                              as order_id,
    l_linenumber                                            as line_number,
    l_quantity                                              as quantity,
    l_extendedprice                                         as extended_price,
    l_discount                                              as discount,
    l_tax                                                   as tax,
    l_extendedprice * (1 - l_discount)                     as net_price,
    l_extendedprice * (1 - l_discount) * (1 + l_tax)      as gross_price,
    l_returnflag                                            as return_flag,
    l_linestatus                                            as line_status,
    l_shipdate                                              as ship_date,
    l_commitdate                                            as commit_date,
    l_shipmode                                              as ship_mode,
    current_timestamp                                       as _loaded_at

from source_data
