---
layout: post
title:  "Realtime pixel tracking with nginx, syslog-ng, and redis"
date:   2013-09-13 02:57:28
categories: nginx redis syslog pixel-tracking
comments: true
---

Pixel tracking is all over the internet.  Everything from simple page loads to sophisticated ad impression tracking uses web beacons in one form or another.  While it used to be sufficient to just process your access logs offline (remember [Webalizer](http://www.webalizer.org/)?), that is simply no longer the case.  We now require sophisticated realtime analytics to gain insights for A/B testing, bounce debugging, etc.  All the "growth hacking" buzzwords.  There are a million services you can pay to do this for you today, and a million more will spin up tomorrow.  This is how you can do it yourself using the tools you already have.  Of course, the data science to make use of it will be left to you.

Let's get started.

I'm using:

* nginx [1.4.2](http://nginx.org/download/nginx-1.4.2.tar.gz "nginx 1.4.2")
* Redis [2.6.16](http://download.redis.io/releases/redis-2.6.16.tar.gz "Redis 2.6.16")
* syslog-ng [3.4.3](http://www.balabit.com/network-security/syslog-ng/opensource-logging-system/downloads/download/syslog-ng-ose/3.4 "syslog-ng OSE 3.4.3") (earlier versions won't work since they lack the `$(length ...)` template function)

At the time of this writing, nginx doesn't natively support syslog logging, so I'm using [nginx_syslog_patch](https://github.com/yaoweibin/nginx_syslog_patch "nginx_syslog_patch") to add it.  Follow the instructions in the readme to patch your nginx source tree before compiling.

### [Configuring syslog-ng](#syslog-ng)

Add this to `syslog-ng.conf` (if not already present):

```
source s_local {
  system();
  internal();
};
```

This is just the default logging source that receives messages from `/dev/log` on the local system, and messages generated by syslog-ng itself (usually stats-related messages).  Now for the interesting parts:

```
template t_redis_lpush {
  template("*3\r\n$$5\r\nLPUSH\r\n$$$(length ${PROGRAM})\r\n${PROGRAM}\r\n$$$(length ${MESSAGE})\r\n${MESSAGE}\r\n");
};
```

You might recognize this as [Redis protocol](http://redis.io/topics/protocol "Redis protocol").  You're right.  We're going to send messages straight to Redis via TCP.  Here's how:

```
destination d_redis_tcp {
  tcp("127.0.0.1" port(6379) template(t_redis_lpush));
};
```

This connects to the localhost Redis and sends messages after applying the ```t_redis_lpush``` template.  The result is that Redis puts the messages into a list with the key being whatever the ```program``` field is in the message.

Now we need to apply a filter to distinguish between Redis-bound messages, and everything else:

```
filter f_redis {
  facility(local3);
};
```

We're going to log messages to Redis on `local3` facility.

Let's log it:

```
log {
  source(s_local);
  filter(f_redis);
  destination(d_redis_tcp);
};
```

The complete `syslog-ng.conf` looks like:

```
source s_local {
  system();
  internal();
};

template t_redis_lpush {
  template("*3\r\n$$5\r\nLPUSH\r\n$$$(length ${PROGRAM})\r\n${PROGRAM}\r\n$$$(length ${MESSAGE})\r\n${MESSAGE}\r\n");
};

destination d_redis_tcp {
  tcp("127.0.0.1" port(6379) template(t_redis_lpush));
};

destination d_local {
  file("/var/log/messages");
};

filter f_redis {
  facility(local3);
};

filter f_local {
  not filter(f_redis);
};

log {
  source(s_local);
  filter(f_redis);
  destination(d_redis_tcp);
};

log {
  source(s_local);
  filter(f_local);
  destination(d_local);
};
```

### [Configuring nginx](#nginx)

Now we need nginx to send requests for our pixel to syslog-ng.  You need to add the base syslog setting to nginx's [global config scope](http://wiki.nginx.org/CoreModule "nginx core module"):

```
syslog local3 pixel;
```

This is the top-level of the config where you specify the `pid` file, `user`, etc.  This directive indicates syslog is configured to log messages to `local3` facility with the `program` being `pixel`.

In the `http` block of your nginx config, define a new log format:

```
log_format pixel "$msec,$args";
```

This records the request time with millisecond precision, and the arguments to the pixel request.

Create a new config in `conf.d` directory called `pixel.conf` and add this:

```nginx
server {
  listen 80;
  server_name pixel.example.com;

  location = /pixel.gif {
    access_log syslog:info|/var/log/nginx/pixel.log pixel;
    empty_gif;
  }
}
```

This server block accepts requests to `http://pixel.example.com/pixel.gif` and returns a [1x1 transparent pixel](http://wiki.nginx.org/HttpEmptyGifModule "nginx empty gif module") straight from nginx.  No filesystem lookups, database access, or other costly i/o.  It also logs the requests to a file for redundancy but, of course, more sophisticated remote logging can be done with syslog-ng itself.

### That's it.  That's all you need.

Let's try it:

```bash
$ ab -c 10 -n 100 http://pixel.example.com/pixel.gif?foo=bar&baz=1
```

Let's check Redis:  
*note that it can take a bit for syslog-ng to flush it's output buffers.  Adjust as needed but be aware of the performance implications*

```bash
$ redis-cli LRANGE pixel 0 -1
  1) "1379183721.115,foo=bar&baz=1"
  2) "1379183721.115,foo=bar&baz=1"
  3) "1379183721.115,foo=bar&baz=1"
  4) "1379183721.115,foo=bar&baz=1"
  5) "1379183721.115,foo=bar&baz=1"
  6) "1379183721.114,foo=bar&baz=1"
  7) "1379183721.114,foo=bar&baz=1"
  8) "1379183721.114,foo=bar&baz=1"
  9) "1379183721.114,foo=bar&baz=1"
 10) "1379183721.114,foo=bar&baz=1"
 ...
```

## *Nice*

From here it's up to you.  You can imagine a simple Python script to process this:

```python
#!/usr/bin/python
#
#
import redis

def main():

  r = redis.Redis()

  while True:
    _, event = r.brpop("pixel")
    timestamp, args = event.split(",", 1)
    print timestamp, args

if __name__ == '__main__':
  main()
```