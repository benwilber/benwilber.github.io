---
layout: post
title:  "Implementing Stream Keys with nginx-rtmp and Django"
date:   2016-10-22 00:00:00
categories: streamboat.tv nginx rtmp streaming
comments: true
---

Any live video streaming community needs the ability for streamers to publish streams to a private endpoint but have their stream play back on their public profile or channel.  This is typically implemented by providing a secret "stream key" known only to the streamer, preventing others from being able to stream on their account.  There's nothing special about the stream key as far as RTMP is concerned, it's just a regular stream name.  However, when a stream is published under this secret name the RTMP server has the opportunity to inspect the stream key, lookup and verify the publishing user, and redirect the stream to their public profile stream.  The stream key is never visible or accessible publicly.

Implementing this flow with [nginx-rtmp](https://github.com/arut/nginx-rtmp-module) and [Django](https://www.djangoproject.com/) is pretty straightforward.

## nginx-rtmp
The following example configuration assumes that you want to allow private stream publishing via RTMP, but only allow playback via HTTP/HLS.  No RTMP playback is permitted.

```
rtmp {
    server {
        listen 1935;

        application app {
            live on;

            # No RTMP playback
            deny play all;

            # Push this stream to the local HLS packaging application
            push rtmp://127.0.0.1:1935/hls-live;

            # HTTP callback when a stream starts publishing
            # Should return 2xx to allow, 3xx to redirect, anything else to deny.
            on_publish http://127.0.0.1:8080/on_publish;

            # Called when a stream stops publishing.  Response is ignored.
            on_publish_done http://127.0.0.1:8080/on_publish_done;
        }

        application hls-live {
            live on;

            # No RTMP playback
            deny play all;

            # Only allow publishing from localhost
            allow publish 127.0.0.1;
            deny publish all;

            # Package this stream as HLS
            hls on;
            hls_path /var/www/live;

            # Put streams in their own subdirectory under `hls_path`
            hls_nested on;
            hls_fragment_naming system;
        }
    }
}
```

When a stream starts publishing `nginx-rtmp` will dispatch an HTTP POST request to `http://127.0.0.1:8080/on_publish`, expecting either a `2xx` response to accept the stream, a `3xx` to redirect the stream, or any other code to deny the stream.  Assuming our Django application is listening on `localhost:8080`, we can set up a handler to receive these events.


## Django

```python
from django.http import HttpResponse, HttpResponseForbidden, HttpResponseRedirect
from django.shortcuts import get_object_or_404
from django.utils import timezone
from django.views.decorators.http import require_POST

from .models import Stream


@require_POST
def on_publish(request):
    # nginx-rtmp makes the stream name available in the POST body via `name`
    stream_key = request.POST['name']

    # Assuming we have a model `Stream` with a foreign key
    # to `django.contrib.auth.models.User`, we can
    # lookup the stream and verify the publisher is allowed to stream.
    stream = get_object_or_404(Stream, key=stream_key)

    # You can ban streamers by setting them inactive.
    if not stream.user.is_active:
        return HttpResponseForbidden("inactive user")

    # Set the stream live
    stream.live_at = timezone.now()
    stream.save()

    # Redirect the private stream key to the user's public stream
    # NOTE: a relative redirect like this will not work in
    #       Django <= 1.8
    return HttpResponseRedirect(stream.user.username)


@require_POST
def on_publish_done(request):
    # When a stream stops nginx-rtmp will still dispatch callbacks
    # using the original stream key, not the redirected stream name.
    stream_key = request.POST['name']

    # Set the stream offline
    Stream.objects.filter(key=stream_key).update(live_at=None)

    # Response is ignored.
    return HttpResponse("OK")
```

## Serving HLS
After the stream is accepted nginx-rtmp will begin packaging it as HLS, so we need to make it available.

```
server {
    listen 80;
    root /var/www;

    # Let streams be delivered via XHR.
    # You'd also want to configure a `crossdomain.xml` file
    # for Flash-based players.
    add_header Access-Control-Allow-Origin "*";
    add_header Access-Control-Allow-Methods "GET";

    location ~ ^/live/(.+\.ts)$ {
        alias /var/www/live/$1;

        # Let the MPEG-TS video chunks be cacheable
        expires max;
    }

    location ~ ^/live/(.+\.m3u8)$ {
        alias /var/www/live/$1;

        # The M3U8 playlists should not be cacheable
        expires -1d;
    }
}
```

Now we can stream using our private stream key `J42ninLbjl2E2V8ePqy7`, and play back via HLS on our public profile `benw`:

```sh
$ ffmpeg -i video.mp4 -c:v h264 -c:a aac -f flv rtmp://<stream host>:1935/app/J42ninLbjl2E2V8ePqy7
```

More info for streaming with `ffmpeg` is available in their [Streaming Guide](https://trac.ffmpeg.org/wiki/StreamingGuide).

Fetch the public stream playlist:

```
$ wget -qO- http://<stream host>/live/benw/index.m3u8
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-MEDIA-SEQUENCE:7614
#EXT-X-TARGETDURATION:6
#EXTINF:5.950,
1477168823630.ts
#EXTINF:5.950,
1477168829573.ts
#EXTINF:5.950,
1477168835527.ts
#EXTINF:5.234,
1477168841472.ts
#EXTINF:5.550,
1477168846713.ts
#EXTINF:5.450,
1477168852242.ts
```

