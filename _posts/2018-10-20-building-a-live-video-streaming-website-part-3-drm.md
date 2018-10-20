---
layout: post
title:  "Building a live video streaming website - Part 3 - DRM"
date:   2018-10-20 00:00:00
categories: nginx rtmp live video streaming django drm
comments: true
---

This is part 3 of a series on creating a Twitch.tv-like live video streaming website.  See [Part 2 - The Application here](/nginx/rtmp/live/video/streaming/django/2018/10/20/building-a-live-video-streaming-website-part-2-the-applications.html)

# DRM

It is sometimes desirable to have "protected" streams.  These are video streams that can't just be played-back in VLC or other media player directly.  More importantly, they can't be shared easily (HLS link posted on Twitter, Reddit, etc.).

**WARNING**

*This method of DRM will keep honest people honest.  But determined people will figure out how to break it.  This is the case with any kind of DRM.*


## Configuring NGINX

The first thing we need to do is add a few more modules to nginx.  Refer to [Part 1](/nginx/rtmp/live/video/streaming/2018/03/25/building-a-live-video-streaming-website-part-1-start-streaming.html) of this series for instructions on how to add modules to nginx and make a new build.  The specific modules that we need are:

* [ngx_devel_kit](https://github.com/simplresty/ngx_devel_kit)
* [set-misc-nginx-module](https://github.com/openresty/set-misc-nginx-module)
* [ngx_http_substitutions_filter_module](https://github.com/yaoweibin/ngx_http_substitutions_filter_module)

After we've rebuilt nginx we need to update the `nginx.conf`.  The first thing to do is to make nginx-rtmp start encrypting MPEG-TS segments:

```shell
$ mkdir -pZ /var/www/keys
```

```nginx
application hls {
    live on;

    # Only accept publishing from localhost.
    # (the `app` RTMP ingest application)
    allow publish 127.0.0.1;
    deny publish all;
    deny play all;

    # Package streams as HLS
    hls on;
    hls_path /var/www/live;
    hls_nested on;
    hls_fragment_naming system;
    hls_datetime system;

    # Encrypt MPEG-TS segments.
    # Every 1 minute of video will require a new decryption key.
    hls_keys on;
    hls_key_path /var/www/keys;
    hls_fragments_per_key 6;
    hls_key_url /keys/;
}
```

When the `hls` app starts packaging the RTMP stream as HLS, it will produce 10 second segments and encrypt every 6 segments with a new encryption key.  This will result in every 1 minute of video requiring re-authorization to view.  In order to enforce this re-authorization, we need to update the HTTP configuration in nginx:

```nginx
location ~ ^/keys/([^/]+)/[0-9]+\.key$ {
    set $stream_username $1;
    set $user_sig $arg_s;
    auth_request /authorize_key;
}

location = /authorize_key {
    internal;

    # VERY IMPORTANT:
    # Replace SECRET_KEY with some secret that only the website knows,
    # such as Django's SECRET_KEY.
    set_hmac_sha1 $sig "SECRET_KEY" "$cookie_sessionid $stream_username";
    set_encode_base64 $sig $sig;

    # Only valid logged-in users can watch this stream.
    if ($sig != $user_sig) {
        return 403;
    }

    proxy_set_header X-Stream-Username $stream_username;
    proxy_pass http://127.0.0.1:8000/authorize_key;
}

location ~ ^/live/([^/]+)/index\.m3u8$ {
    expires -1d;
    set $stream_username $1;
    set_hmac_sha1 $sig "SECRET_KEY" "$cookie_sessionid $stream_username";
    set_encode_base64 $sig $sig;

    # Append the expected token to the encryption key requests in the manifest
    subs_filter_types application/vnd.apple.mpegurl;
    subs_filter "URI=\"/keys/([^/]+)/([0-9]+)\.key\"" "URI=\"/keys/$1/$2.key?s=$sig\"" gr;
}
```

This modifies the `index.m3u8` HLS manifest by appending the expected token to all encryption key requests.  This allows us to verify whether or not the viewer that requested this manifest is allowed to receive the encryption key required to watch the video stream.

Now we just add a simple view to our `views.py` that ensures the viewer is logged-in to our site and they're not banned:

```python
@require_GET
def authorize_key(request):
    if request.user.is_authenticated() and request.user.is_active:
        # Do other checks here like Pay-Per-View (or Pay-Per-Minute :-))
        return HttpResponse("OK")

    return HttpResponseForbidden("Not authorized")
```

Wire it up to our Django URLs:

```python
urlpatterns = [
    path("admin/", admin.site.urls),
    path("start_stream", start_stream, name="start-stream"),
    path("stop_stream", stop_stream, name="stop-stream"),
    path("authorize_key", authorize_key, name="authorize-key"),
    path("live/<username>/index.m3u8", fake_view, name="hls-url")
]
```

Now only logged-in, authorized viewers are able to watch our video streams.  They will require re-authorization for every 1 minute of video.

<hr>

In the next part we're going to add a CDN so that we can scale to massive audiences.

* [Part 1 - Start Streaming!](/nginx/rtmp/live/video/streaming/2018/03/24/building-a-live-video-streaming-website-part-1-start-streaming.html)
* [Part 2 - The Application](/nginx/rtmp/live/video/streaming/django/2018/10/19/building-a-live-video-streaming-website-part-2-the-applications.html)
* Part 3 - DRM
* Part 4 - We're big now!  Adding a CDN
* Part 5 - Bringing it all together
