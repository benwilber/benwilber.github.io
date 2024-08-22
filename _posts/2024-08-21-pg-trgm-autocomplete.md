---
layout: post  
title: "Fast autocomplete in Postgres with pg_trgm"  
date: 2024-08-21 00:00:00  
categories: programming  
comments: true  
---

# Fast autocomplete in Postgres with pg_trgm

Autocomplete functionality can significantly enhance UX, especially in comments or forums where users often mention each other by name or username. Implementing this is very efficient in PostgreSQL using the `pg_trgm` extension, which allows for fast, fuzzy text searches. This post will guide you through setting up autocomplete for usernames in mentions using `pg_trgm`.

## Why `pg_trgm`?

The [`pg_trgm`](https://www.postgresql.org/docs/current/pgtrgm.html) (trigram) extension in PostgreSQL is designed for fast pattern matching. It breaks down strings into sequences of three consecutive characters (trigrams) and uses them to calculate similarity between strings. This makes it an ideal tool for implementing autocomplete, where you need to suggest usernames as users type.

## Setting Up `pg_trgm`

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

Do a fuzzy search for the top 10 users by their username:

```sql
select
	id,
	username,
	similarity(username, 'foo') as score
from
	users
where
	username % 'foo'
order by
	score desc
limit 10
```


Adapt as-needed.  PostgreSQL and `pg_trgm` is great for fuzzy search on small(ish) strings.


I have a PG 12 database with 140,000,0000 records and this query takes 30ms max.


So that's ...*Pretty good*
