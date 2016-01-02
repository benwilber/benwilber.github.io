---
layout: post
title:  "Streaming logs over HTTP with nginx"
date:   2015-12-31 15:57:28
categories: nginx syslog-ng logs push stream
comments: true
---

I often want to `tail` my app and website logs across multiple servers at the same time.  There are a bunch of tools to do this, which basically just SSH to your servers and combine the outputs of `tail -f` to your terminal.  I've been working on a better way using [nginx](http://nginx.org), [nginx-push-stream](https://github.com/wandenberg/nginx-push-stream-module), and [syslog-ng](https://www.balabit.com/network-security/syslog-ng).

The end result is that you can "tail" logs across N servers just via:

```bash
$ curl -s https://ghit.me/logs/badge_access
<remote addr> - - [02/Jan/2016:15:07:22 -0500] "-" "ghit.me" "GET /badge.svg?repo=benwilber/bashids HTTP/1.1" 304 0 "https://ghit.me/logs.html" "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/47.0.2526.106 Safari/537.36" "-" "0.000"
<remote addr> - - [02/Jan/2016:15:07:46 -0500] "-" "ghit.me" "GET /badge.svg?repo=benwilber/bashids HTTP/1.1" 304 0 "https://ghit.me/logs.html" "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/47.0.2526.106 Safari/537.36" "-" "0.000"
<remote addr> - - [02/Jan/2016:15:09:22 -0500] "-" "ghit.me" "GET /badge.svg?repo=benwilber/bashids HTTP/1.1" 304 0 "https://ghit.me/logs.html" "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/47.0.2526.106 Safari/537.36" "-" "0.000"
...
```

In this example we're streaming the access logs of badge requests from [ghit.me](https://ghit.me/).

## nginx

```nginx
http {
    log_format main '$remote_addr - $remote_user [$time_local] "$http_x_forwarded_proto" '
                    '"$http_host" "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" "$request_time"';
    ...
    push_stream_shared_memory_size 100M;
    push_stream_max_messages_stored_per_channel 10;
}
...
location = /badge.svg {
    expires -1d;
    set_formatted_gmt_time $datestr "%Y-%m-%d";
    set_escape_uri $escaped_repo $arg_repo;
    access_log syslog:server=127.0.0.1,facility=local3,tag=badge,severity=info badge;
    access_log syslog:server=127.0.0.1,facility=local3,tag=badge_access,severity=info main;
    error_log syslog:server=127.0.0.1,facility=local3,tag=badge_error,severity=info;
    alias /var/www/ghit.me/badges/$escaped_repo.svg;
}  
```

Take a look at my [previous post]({% post_url 2015-12-25-how-i-built-ghit-me %}) about [ghit.me](https://ghit.me/) for details on what the `badge.svg` location entails.  The only additional thing I added was:

```
access_log syslog:server=127.0.0.1,facility=local3,tag=badge_access,severity=info main;
error_log syslog:server=127.0.0.1,facility=local3,tag=badge_error,severity=info;
```

This logs a message in nginx's standard `main` logging format under the tag `badge_access`.  `push_stream_max_messages_stored_per_channel` is a global setting that sets the maximum messages to buffer.  In our case it will function as a FIFO buffer of access log lines stored in memory.  Additionally, we're logging the badge error log to `badge_error`.

### nginx-push-stream

```nginx
location ~ ^/pub/(.+)$ {
    internal;
    push_stream_publisher admin;
    push_stream_channels_path $1;
    push_stream_store_messages on;
}

location ~ ^/sub/(.+)$ {
    internal;
    push_stream_subscriber;
    push_stream_channels_path $1;
    push_stream_message_template ~text~\n;
    add_header Content-Type "text/plain";
}

location ~ ^/ws/(.+)$ {
    internal;
    push_stream_subscriber websocket;
    push_stream_websocket_allow_publish off;
    push_stream_ping_message_interval 10s;
    push_stream_channels_path $1;
    push_stream_message_template ~text~\n;
}

location ~ ^/logs/(.+)$ {
    set $chan $1;

    if ($http_upgrade ~ "websocket") {
      rewrite ^ /ws/$chan last;
    }

    if ($request_method = "GET") {
      rewrite ^ /sub/$chan last;
    }

    if ($request_method = "POST") {
      rewrite ^ /pub/$chan last;
    }
}
```

Here we just set up our `push-stream` endpoints.  `/pub/<channel>` to publish messages via HTTP POST, `/sub/<channel>` to subscribe via long-polling, and `/ws/<channel>` to subscribe via a WebSocket.

## syslog-ng

```syslog-ng
template t_badge_http {
    template("POST /logs/${PROGRAM} HTTP/1.1\r\nHost: ghit.me\r\nContent-Length: $(length ${MESSAGE})\r\nConnection: keep-alive\r\n\r\n${MESSAGE}");
};

filter f_badge_access {
    facility(local3) and level(info);
};

destination d_badge_http {
    tcp("127.0.0.1" port(80) template(t_badge_http) keep-alive(yes));
};

log {
    source(s_sys);
    filter(f_badge_access);
    destination(d_badge_http);
};
```

We tell syslog-ng to filter messages for `local3.info` and apply the template `t_badge_http`, which is just a raw HTTP POST to `/logs/${PROGRAM}`, either `badge_access` or `badge_error`, which publishes the log message to that channel.

Now we can subscribe to log messages via:

```bash
$ curl -s https://ghit.me/logs/badge_access
<remote addr> - - [02/Jan/2016:15:07:22 -0500] "-" "ghit.me" "GET /badge.svg?repo=benwilber/bashids HTTP/1.1" 304 0 "https://ghit.me/logs.html" "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/47.0.2526.106 Safari/537.36" "-" "0.000"
<remote addr> - - [02/Jan/2016:15:07:46 -0500] "-" "ghit.me" "GET /badge.svg?repo=benwilber/bashids HTTP/1.1" 304 0 "https://ghit.me/logs.html" "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/47.0.2526.106 Safari/537.36" "-" "0.000"
<remote addr> - - [02/Jan/2016:15:09:22 -0500] "-" "ghit.me" "GET /badge.svg?repo=benwilber/bashids HTTP/1.1" 304 0 "https://ghit.me/logs.html" "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/47.0.2526.106 Safari/537.36" "-" "0.000"
...
```

We're streaming our logs via cURL.  It works equally well with a WebSocket:

```javascript
var ws = new WebSocket("wss://ghit.me/logs/badge_access");
ws.onmessage = function(e) {
  console.log(e.data);
};
```
