---
layout: post  
title: "SQLite is great for what it is: a small, embedded SQL database.  But nothing more."  
date: 2025-03-31 00:00:00  
categories: programming  
comments: true  
---

 > Client/server SQL database engines strive to implement a shared repository of enterprise data. They emphasize scalability, concurrency, centralization, and control. SQLite strives to provide local data storage for **individual applications and devices**. SQLite emphasizes economy, efficiency, reliability, independence, and simplicity.

> SQLite does not compete with client/server databases. SQLite competes with `fopen()`.

[source](https://www.sqlite.org/whentouse.html)

It's great for your personal web browser history, or the contacts on your iPhone.  But it's not great for a multi-user server application.  Here's why.

## Limited concurrency

SQLite is designed for a single writer and multiple readers.  If you have multiple writers, you'll have problems.  SQLite uses `fcntl()` (or `flock()`) to prevent multiple writers from corrupting the database.  This means that if you have a lot of writes, you'll have a lot of contention for the lock.

### How to solve this?

Well, just have many SQLite databases.  But now you've lost everything that's great about a relational SQL database: transactions, joins, and foreign keys.

## Foreign keys

SQLite has foreign key support, but it's off by default.  You have to enable it at runtime.

> Assuming the library is compiled with foreign key constraints enabled, it must still be enabled by the application at runtime, using the PRAGMA foreign_keys command. For example:

```
sqlite> PRAGMA foreign_keys = ON;
```

[source](https://www.sqlite.org/foreignkeys.html)

## Flimsy data types

SQLite has a very limited set of data types.  For example, there's no `DATE` type.  Everything is a string.  And you can insert *whatever* into any column.

### Insert a string into an integer column

```
sqlite> CREATE TABLE test (id INTEGER PRIMARY KEY);
sqlite> INSERT INTO test (id) VALUES ('hello world');
sqlite> SELECT * FROM test;
hello world
```

You can fix this (egregious) issue by creating `strict` tables:

```
sqlite> CREATE TABLE test (id INTEGER PRIMARY KEY) STRICT;
```

But that's not the default.  I remember [another database](https://www.mongodb.com/) that optimized for performance over data safety and correctness.

### Dates/Times

Use any `date`-related functions on a column where SQLite doesn't recognize the string as a parsable "date" and you'll only get `NULL`, not any indication that the column is incorrect for what you think it should be (a  date/time).

# Just use Postgres

There are projects like [LiteStream](https://litestream.io/) and many others that aim to make SQLite a real backend database.  But SQLite is fundamentally not a backend database.  Dr. Hipp himself has said that none of the features that would make SQLite a competitor with Postgres, or MySQL, are a priority simply because they would bloat the embedded object size of the **embedded** database.

