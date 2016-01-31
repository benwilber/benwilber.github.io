---
layout: post
title:  "How I build Sinklog.com, combine your log outputs into a single stream."
date:   2016-01-31 00:00:00
categories: nginx syslog-ng logs push stream syslog http websocket lua
comments: true
---

I have a lot of little sites and servers on the web that do a variety of things.  I often find that I want to `tail -f` the logs across N number of servers/applications at any time.  Typically you just set up a central log server with `rsyslog` or `syslog-ng`, SSH in and `tail -f` your logs.  I wanted something even simpler than that.  Introducing [Sinklog.com](https://sinklog.com).


The setup is pretty simple.  Go to [Sinklog.com](https://sinklog.com), create a log, and log to it using the associated log key.  Suppose we create a log called `foolog`.  We get a log key `xTBg8Ie7IY`.

```bash
$ logger -t xTBg8Ie7IY -n sinklog.com "Hello foo log"
```

and in a separate console:

```bash
$ curl -ns https://sinklog.com/s/foolog
Hello foo log
```

(note: Mac OS doesn't include the version of `logger` that can log to remote servers.  Check out [python-sinklog](https://github.com/sinklog/python-sinklog) for an alternative.)


Look at the [example integrations](https://github.com/sinklog/sinklog-examples) for other ways to log from common apps/servers.

# How it's built
The server setup is just `nginx`, `syslog-ng`, `redis`, and a tiny bit of `lua`.

## nginx

`nginx` is compiled with [nginx-push-stream-module](https://github.com/wandenberg/nginx-push-stream-module) for the HTTP streaming/websocket support, OpenResty's [set-misc](https://github.com/openresty/set-misc-nginx-module) and [lua](https://github.com/openresty/lua-nginx-module) modules.

### nginx configuration

```nginx
server {
    ...

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
        more_set_headers "Content-Type: text/plain";
    }

    location ~ ^/ws/(.+)$ {
        internal;
        push_stream_subscriber websocket;
        push_stream_websocket_allow_publish off;
        push_stream_ping_message_interval 10s;
        push_stream_channels_path $1;
        push_stream_message_template ~text~\n;
    }

    location ~ ^/s/(.+)$ {
        set_escape_uri $logname $1;
        rewrite_by_lua_block {
            rewrites.rewrite()
        }
    }
}
```

and `rewrites.lua`:

```lua
_M = {}

local redis = require("redis")


local function iswebsocket()
    if ngx.var.http_upgrade then
        return string.match(ngx.var.http_upgrade:lower(), "websocket")
    end
    return false
end


local function isget()
    return ngx.var.request_method == "GET"
end


local function ispost()
    return ngx.var.request_method == "POST"
end


local function getlogkey(name)
    local r = redis:new()
    r:connect("127.0.0.1", 6379)
    local res, err = r:get(name)
    return res
end


local function geturi(name)

    if iswebsocket() or isget() then
        local key = getlogkey(name)
        if not key then
            return nil
        elseif iswebsocket() then
            return "/ws/" .. key
        elseif isget() then
            return "/sub/" .. key
        end

    elseif ispost() then
        return "/pub/" .. name
    end

end


_M.rewrite = function()
    local uri = geturi(ngx.var.logname)

    if not uri then
        ngx.exit(ngx.HTTP_NOT_FOUND)
    else
        ngx.req.set_uri(uri, true)
    end

end

return _M
```

This script just does the internal rewrites of log key <-> log name.


### syslog-ng configuration

```syslog-ng
source s_external {
    udp(ip(0.0.0.0) port(514));
    tcp(ip(0.0.0.0) port(514));
};

template t_http {
    template("POST /s/${PROGRAM} HTTP/1.1\r\nHost: sinklog.com\r\nContent-Length: $(length ${MESSAGE})\r\nContent-Type: text/plain\r\nConnection: keep-alive\r\n\r\n${MESSAGE}");
};

destination d_http {
    tcp("127.0.0.1" port(80) template(t_http) keep-alive(yes));
};

log {
    source(s_external);
    destination(d_http);
};
```

Now when `syslog-ng` receives messages it does and HTTP POST to `nginx-push-stream`, which then delivers the message to any subscribers on that "channel".  The lua rewrite script ensures that the log key is properly translated to the correct log name.

And that's basically it!  Now you can log anything you want via syslog and view the stream using any HTTP/Websocket client.



