---
layout: post  
title: "Fast autocomplete in PostgreSQL with pg_trgm"  
date: 2024-08-21 00:00:00  
categories: programming  
comments: true  
---

# Fast autocomplete in PostgreSQL with pg_trgm

Autocomplete functionality can significantly enhance UX, especially in comments or forums where users often mention each other by name or username. Implementing this is very efficient in PostgreSQL using the `pg_trgm` extension, which allows for fast, fuzzy text searches. This post will guide you through setting up autocomplete for usernames in mentions using `pg_trgm`.

## Why pg_trgm?

The [`pg_trgm`](https://www.postgresql.org/docs/current/pgtrgm.html) (trigram) extension in PostgreSQL is designed for fast pattern matching. It breaks down strings into sequences of three consecutive characters (trigrams) and uses them to calculate similarity between strings. This makes it an ideal tool for implementing autocomplete, where you need to suggest usernames as users type.

## Setting Up pg_trgm

First, ensure that the `pg_trgm` extension is enabled in your PostgreSQL database:

```sql
create extension pg_trgm;
create extension citext; -- case-insensitive text columns
```

Create a simple `users` table with unique usernames:

```sql
create table users (
	id bigserial primary key,
	username citext unique not null collate pg_catalog."C" -- case-insensitive, only ASCII.
);
```

Add the trigram index on the `username` column:

```sql
create index users_username_trgm on users using gist (username gist_trgm_ops);
```

Now insert millions of rows into the `users` table.


PostgreSQL and `pg_trgm` is great for fuzzy search on small(ish) strings.

```sql
select
	id,
	username,
	similarity(username, 'jaso') as score
from
	user_
where
	username % 'jaso'
order by
	score desc
limit
	10
```

```
 id  |  username   |   score    
-----+-------------+------------
 170883 | jason73     | 0.44444445
 66533  | jason55     | 0.44444445
 921950 | jason90     | 0.44444445
 8853   | jasongraves | 0.30769232
```

I have a PG 12 database with 140,000,0000 users and this query takes 30ms max.


Here's an example query plan:

```
                                                               QUERY PLAN                                                               
----------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=20.07..20.10 rows=10 width=22) (actual time=0.386..0.389 rows=4 loops=1)
   ->  Sort  (cost=20.07..20.10 rows=10 width=22) (actual time=0.384..0.386 rows=4 loops=1)
         Sort Key: (similarity((username)::text, 'jaso'::text)) DESC
         Sort Method: quicksort  Memory: 25kB
         ->  Bitmap Heap Scan on user_  (cost=4.22..19.91 rows=10 width=22) (actual time=0.351..0.373 rows=4 loops=1)
               Recheck Cond: ((username)::text % 'jaso'::text)
               Heap Blocks: exact=4
               ->  Bitmap Index Scan on user_username_trgm  (cost=0.00..4.22 rows=10 width=0) (actual time=0.336..0.337 rows=4 loops=1)
                     Index Cond: ((username)::text % 'jaso'::text)
 Planning Time: 0.478 ms
 Execution Time: 0.453 ms
```


So that's ...*Pretty, pretty good*
