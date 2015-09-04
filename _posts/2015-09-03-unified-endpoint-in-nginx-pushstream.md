---
layout: post
title:  "Unified Endpoints in nginx-push-stream"
date:   2015-09-03 02:57:28
categories: nginx pushstream websocket pubsub
comments: true
---

I recently started playing with [nginx-push-stream-module](https://github.com/wandenberg/nginx-push-stream-module).  This a really cool module that essentially allows you to replicate the basic functionality of [Pusher](https://pusher.com/) and [PubNub](https://www.pubnub.com/) within nginx.

The configuration is pretty basic:

## Publisher

```nginx
location ~ /pub/(.+) {
    internal;
    push_stream_publisher admin;
    push_stream_channels_path $1;
}  
```

## Subscriber

```nginx
location ~ /sub/(.+) {
    internal;
    push_stream_subscriber;
    push_stream_channels_path $1;
    push_stream_message_template ~text~\n;
}
```

## WebSocket publisher/subscriber

```
  location ~ /ws/(.+) {
    internal;
    push_stream_subscriber websocket;
    push_stream_websocket_allow_publish on;
    push_stream_ping_message_interval 10s;
    push_stream_channels_path $1;
    push_stream_message_template ~text~\n;
  }
```

## Unified PubSub endpoint
```
location ~ /chan/([\w\d\-_:]+)$ {
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

## Usage

### Publisher
```bash
$ curl -s -X POST -d "Hello World" https://streamboat.tv/chan/mychan
```

### Subscriber
```bash
$ curl -s https://streamboat.tv/chan/mychan
Hello World
```

### JS pub/sub
```js
var ws = new WebSocket("wss://streamboat.tv/chan/mychan");
ws.onmessage = function(event) {
    console.log(event.data);
}
// Hello World
```