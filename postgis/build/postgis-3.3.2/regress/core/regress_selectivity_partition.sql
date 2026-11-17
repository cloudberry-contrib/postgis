-- Cloudberry stores HLL stats (stakind 98/99) in the last pg_statistic slot
-- of leaf partitions, which used to overwrite the PostGIS 2D histogram
-- (stakind 103). The && selectivity estimator then found no stats and
-- crashed on pfree(NULL).

SET client_min_messages TO warning;

CREATE TABLE sel_part_test (
    id int,
    city varchar(50),
    geom geometry(Polygon,3857)
) USING ao_column
  DISTRIBUTED BY (id)
  PARTITION BY LIST (city)
  ( PARTITION p_chengdu VALUES ('chengdu'),
    DEFAULT PARTITION p_other );

INSERT INTO sel_part_test (id, city, geom)
SELECT i, 'chengdu',
       ST_MakeEnvelope(11500000 + (i % 40) * 5000, 3500000 + (i / 40) * 5000,
                       11500000 + (i % 40) * 5000 + 300, 3500000 + (i / 40) * 5000 + 300,
                       3857)
FROM generate_series(0, 999) i;

ANALYZE sel_part_test;

-- Leaf partition keeps both PostGIS kinds and Cloudberry's HLL kind
SELECT 'leaf_kinds',
       103 = ANY(ARRAY[stakind1, stakind2, stakind3, stakind4, stakind5]) AS has_2d,
       102 = ANY(ARRAY[stakind1, stakind2, stakind3, stakind4, stakind5]) AS has_nd,
       stakind5 IN (98, 99) AS hll_last
FROM pg_statistic s
JOIN pg_attribute a ON a.attrelid = s.starelid AND a.attnum = s.staattnum
WHERE a.attrelid = 'sel_part_test_1_prt_p_chengdu'::regclass AND a.attname = 'geom';

-- Stats are readable (errors out if the 2D kind is missing)
SELECT 'leaf_sel', _postgis_selectivity('sel_part_test_1_prt_p_chengdu', 'geom',
       ST_MakeEnvelope(11500000, 3500000, 11600000, 3600000, 3857)) > 0.0001;

-- Used to crash the backend
SELECT 'query', count(*) FROM sel_part_test
WHERE geom && ST_MakeEnvelope(11500000, 3500000, 11510000, 3510000, 3857)
AND ST_Intersects(ST_MakeEnvelope(11500000, 3500000, 11510000, 3510000, 3857), geom);

-- Non-partitioned table keeps the upstream slot layout
CREATE TABLE sel_plain_test AS SELECT * FROM sel_part_test DISTRIBUTED BY (id);
ANALYZE sel_plain_test;
SELECT 'plain_kinds', stakind4, stakind5
FROM pg_statistic s
JOIN pg_attribute a ON a.attrelid = s.starelid AND a.attnum = s.staattnum
WHERE a.attrelid = 'sel_plain_test'::regclass AND a.attname = 'geom';

DROP TABLE sel_plain_test;
DROP TABLE sel_part_test;
