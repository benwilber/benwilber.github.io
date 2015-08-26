---
layout: post
title:  "Dynamic log formats in nginx"
categories: nginx syslog logging
comments: true
---

Some time ago [I wrote]({% post_url 2013-09-13-realtime-pixel-tracking-with-nginx-syslog-ng-and-redis %}) about a way to implement simple realtime pixel tracking using nginx, redis, and syslog-ng.  It is a somewhat novel approach that simply logs requests in a CSV format:

```
"$msec,$args"
```
which produces log lines of:
```
1440615892.165,foo=bar&baz=1
```

That's simple enough to parse because we know there are only two fields: timestamp, and query parameters.  In Python we can just split this on the first instance of a `comma` and be confident that we accurately capture both fields regardless of whether `$args` also contained a `comma` (ie, wasn't urlencoded).

```python
event = "1440616054.165,foo=bar&baz=this, has a comma"
timestamp, args = event.split(",", 1)
print(timestamp, args)
('1440616054.165', 'foo=bar&baz=this, has a comma')
```

However, this breaks if you try to use `csv.reader`:

```python
import csv
from StringIO import StringIO
sio = StringIO(event)
for row in csv.reader(sio):
  print(row)
['1440616054.165', 'foo=bar&baz=this', ' has a comma']
```

The simple solution here would be to quote `$args` when logging:

```
'$msec,"$args"'
```
```
1440617233.705,"foo=bar&baz=this, has a comma"
```

Now `csv.reader` works as expected:

```python
['1440616054.165', 'foo=bar&baz=this, has a comma']
```

But now what happens if `$args` contains a `comma` and a `quote` character?

```
1440618416.679,"foo=bar&baz="this has a , and is quoted""
```

We can predict the problem this is going to cause for `csv.reader`:

```python
['1440618416.679', 'foo=bar&baz=this has a ', ' and is quoted""']
```

We could fight this all day, but the real solution is to simply always urlencode your query parameters.  This is, however, not always possible if you don't control the clients making requests to your server.  What we want to do is *force* urlencoding when we log.


## [`set_escape_uri`](http://wiki.nginx.org/HttpSetMiscModule#set_escape_uri)

The folks at [OpenResty.org](http://openresty.org/) have developed a whole slew of neat nginx modules to complement their primary goal of bringing Lua (and LuaJIT) into nginx itself.  It's a very cool project which I encourage you to check out if you're not familiar.

Among the most useful modules they've developed is [HttpSetMiscModule](http://wiki.nginx.org/HttpSetMiscModule), which provides a number of utilities to encode/decode/hash/unhash any variable that you can use in nginx.

We can use the `set_escape_uri` directive to make sure that any variable we want to log is always properly urlencoded, thus avoiding the problems we might encounter when parsing later.

Let's try it:

```nginx
log_format pixel "$msec,$escaped_args";
```

```nginx
location = /pixel.gif {
    set_escape_uri $escaped_args $args;
    access_log /var/log/nginx/pixel.gif-access.log pixel;
    expires -1d;
    empty_gif;
  }
```

Here we simply urlencoded the `$args` and assigned the result to `$escaped_args`, which is used in our `log_format`.  Now events are logged in a much safer way to parse:

```
1440620805.833,foo%3Dbar%26baz%3D%22this%20is%20quoted%22
```

Your log processor just needs to be aware that it needs to urldecode the args before they can be used, and if the `$args` were *already* urlencoded, then it needs to be done again.


## Dynamic log formats
What if we want to *conditionally* set a variable that gets logged in our format?

```nginx
log_format pixel "$msec,$escaped_args,$request_time,$extra_msg";
```

Here I've added two additional fields, `$extra_msg`, which we'll use to add whatever extra info we want at log time, and the built-in `$request_time`, which is how long the request took to process.  In the case of `empty_gif`, it will pretty much always be  `0.000`.


```nginx
location = /pixel.gif {
    set_escape_uri $escaped_args $args;
    access_log /var/log/nginx/pixel.gif-access.log pixel;
    expires -1d;
    empty_gif;
  }
```

`nginx: [emerg] unknown "extra_msg" variable`

Uh oh.  The problem here is that if we don't explicitely set `$extra_msg` via `set $extra_msg <src>`, then nginx can't resolve the variable when it compiles the config.  It doesn't default to an empty string as you might except.  The solution is rather simple by using a [`map`](http://nginx.org/en/docs/http/ngx_http_map_module.html):

```nginx
map $status $extra_msg {
  default "-";
}
```

`map`s are very cool, underutilized structures in nginx.  If you are ever faced with using an [`if`](http://wiki.nginx.org/IfIsEvil) during a request, you should check to see if you can use a `map` instead.

In our case, we're going to use this `map` a little differently than the intended use-cases.  We don't actually care about the `$status` here.  We only need to pick a variable that we know will resolve so that we can set up our `$extra_msg` variable.  No matter what the `$status` is, our `$extra_msg` variable will always default to a hyphen `"-"`, which in the world of access logs, essentially means "unset".

Now we can do contrived things like:

```nginx
location = /pixel.gif {
    set_escape_uri $escaped_args $args;
    access_log /var/log/nginx/pixel.gif-access.log pixel;
    expires -1d;
    empty_gif;

    if ($http_x_foo) {
      set_escape_uri $extra_msg $http_x_foo;
    }
}
```

```bash
$ curl -s -H "X-Foo: bar baz" 'https://example.com/pixel.gif?foo=bar&baz="this is quoted"' > /dev/null
```

```
1440623915.365,foo%3Dbar%26baz%3D%22this%20is%20quoted%22,0.000,bar%20baz
```

And it's all very easy to parse:

```python
headers = ('timestamp', 'args', 'request_time', 'foo')
sio = StringIO(event)
for row in csv.reader(sio):
  print(zip(headers, row))
[('timestamp', '1440623915.365'), ('args', 'foo%3Dbar%26baz%3D%22this%20is%20quoted%22'), ('request_time', '0.000'), ('foo', 'bar%20baz')]
```

