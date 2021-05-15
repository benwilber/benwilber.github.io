---
layout: post
title:  "Don't parse ISO-8601 datetime strings with a regex"
date:   2021-05-07 00:00:00
categories: programming
comments: true
---

# Do not try to parse ISO-8601 with a regex
In 2017, I opened a [pull request](https://github.com/google/ExoPlayer/pull/2547) to Google's [ExoPlayer](https://github.com/google/ExoPlayer) to properly support datetime strings in HLS manifests configured with a European locale.  Basically, support comma (`,`) separators for unit delinations, in addition to the regular dot (`.`) separators that people are probably used to.

It was a very simple change that was quickly accepted.  A few months later I submitted a similar [patch to Django](https://github.com/django/django/pull/11818).  This one was also ultimately accepted as well.

These were all just trivial regex changes to fix narrow use-cases.

Now I've just submitted [another one to Django](https://github.com/django/django/pull/14368) to fix *yet another* regex ISO-8601 parser bug.

**I'm starting to see a pattern here.**

## Do not try to parse ISO-8601 datetime strings with a regex


Consider these two valid ISO-8601 datetime strings:

```
2012-04-23T10:20:30.400-0200
2012-04-23T10:20:30.400 -0200
```

Django:

```
>>> from django.utils.dateparse import parse_datetime
>>> parse_datetime("2012-04-23T10:20:30.400-0200")
datetime.datetime(2012, 4, 23, 10, 20, 30, 400000, tzinfo=datetime.timezone(datetime.timedelta(days=-1, seconds=79200), '-0200'))
>>> parse_datetime("2012-04-23T10:20:30.400 -0200")
>>>
```

python-dateutil:
```
>>> from dateutil.parser import parse as parse_datetime
>>> parse_datetime("2012-04-23T10:20:30.400-0200")
datetime.datetime(2012, 4, 23, 10, 20, 30, 400000, tzinfo=tzoffset(None, -7200))
>>> parse_datetime("2012-04-23T10:20:30.400 -0200")
datetime.datetime(2012, 4, 23, 10, 20, 30, 400000, tzinfo=tzoffset(None, -7200))
>>>
```

You see that Django doesn't parse the second string correctly.  Why?

[This is why](https://github.com/django/django/blob/main/django/utils/dateparse.py#L22):

```
datetime_re = _lazy_re_compile(
    r'(?P<year>\d{4})-(?P<month>\d{1,2})-(?P<day>\d{1,2})'
    r'[T ](?P<hour>\d{1,2}):(?P<minute>\d{1,2})'
    r'(?::(?P<second>\d{1,2})(?:[\.,](?P<microsecond>\d{1,6})\d{0,6})?)?'
    r'(?P<tzinfo>Z|[+-]\d{2}(?::?\d{2})?)?$'
)
```
Look at this monstrous regex.  Do you think this thing can possibly capture all 33 pages of the ISO-8601 datetime format specification?  Up until a couple years ago it couldn't even capture the difference between `en` and `fr` locales.  Those ISO-8601 datetime formats are *different*.

# What to do?

Don't try to parse ISO-8601 datetime strings with a regex!

As far as I know, there is no regex that can parse the full specification accurately.

Use a library that doesn't use (brittle) regexes to parse the strings.

If you're using Python, use [python-dateutil](https://github.com/dateutil/dateutil).
