---
layout: post
title:  "Hitcount.me: Live Website Popularity"
categories: nginx syslog redis logging static blog hit counter
comments: true
---

I've been experimenting quite a bit lately with various neat things you can do using just nginx, redis, and syslog-ng.  Most recently I wrote about how to use [dynamic log formats]({% post_url 2015-08-26-dynamic-log-formats-in-nginx %}) in nginx.  Before that [I wrote]({% post_url 2013-09-13-realtime-pixel-tracking-with-nginx-syslog-ng-and-redis %}) about an interesting way to implement realtime pixel tracking.  I've decided to put some of these things together into a simple site that someone might find interesting.

### Introducing: [Hitcount.me](https://hitcount.me/)

The idea is pretty basic.  Just include the following HTML somewhere on your page:

```
<img style="display:none;" src="https://hitcount.me/hit.gif" />
```

# What and Why

This is an experiment that I started out implementing for my own blog posts.  Like a lot of people, I get a fair amount of traffic from the typical news aggregator sites (Hacker News, Reddit, etc), but the "upvotes" never seem to even remotely reflect the actual number of visitors I see in my access logs.  This is probably because my posts are lame.  But even on non-lame posts I've seen stuff like 200 visitors, and 2 upvotes.  The reason is easy: most people don't engage by upvoting, sharing, commenting, etc.  They're still there, and still reading, but they're not contributing to my post's popularity at all because they're just "lurking".

[Hitcount.me](https://hitcount.me/) is an experiment in implicit "upvoting".  Just by including the hidden image on your page you automatically get "submitted" to [Hitcount.me](https://hitcount.me/) and "upvoted" whenever you get a visitor.  The top ranked pages daily are simply those that had the most visitors.  There is a small algorithm on the backend that tries to ensure that fraudulent "upvotes" (for instance by crafting your own referer and then pounding `hit.gif` a million times) aren't counted.  I'm sure you can still figure out ways to break it, though.


# Technical details

When your page is loaded and this image is requested, it generates a specially formatted `access_log` message in nginx that gets sent to syslog-ng:

```
log_format hitlog "$msec,$http_referer"
```

```
location = /hit.gif {
    empty_gif;
    expires -1d;
    access_log syslog:server=127.0.0.1,facility=local3,tag=hitlog,severity=info hitlog;
}
```

Then in syslog-ng, we create a custom destination to send these messages to redis:

```
filter f_hitlog {
  facility(local3) and level(info) and program("hitlog");
};

destination d_hitlog {
  redis(
    host("127.0.0.1")
    port(6379)
    command("LPUSH", "$PROGRAM", "$MESSAGE")
  );
};

log {
  source(s_udp);
  filter(f_hitlog);
  destination(d_hitlog);
};
```

```
$ redis-cli LRANGE hitlog 0 -1
1) "1441004287.742,http://benwilber.github.io/"
2) "1441004287.742,http://benwilber.github.io/"
3) "1441004287.729,http://benwilber.github.io/"
4) "1441004287.720,http://benwilber.github.io/"
5) "1441004287.692,http://benwilber.github.io/"
6) "1441004287.639,http://benwilber.github.io/"
7) "1441004287.639,http://benwilber.github.io/"
8) "1441004287.615,http://benwilber.github.io/"
9) "1441004287.590,http://benwilber.github.io/"
10) "1441004287.590,http://benwilber.github.io/"
...
```

And finally there is a Python script that aggregates the referers and renders a simple web page ranked by most popular.

```
import redis

def main():

  r = redis.Redis()
  while True:
    _, event = r.brpop("hitlog")
    timestamp, referer = event.split(",", 1)

    # rank referer counts, render template


if __name__ == '__main__':
  main()
```

