---
layout: post
title:  "Streamboat.tv hotlink protection with nginx and Varnish."
date:   2016-02-06 00:00:00
categories: streamboat.tv nginx varnish hotlink video streaming
comments: true
---

I've been running a live video streaming website, [Streamboat.tv](https://streamboat.tv/), as sort of a hobby for the last few months.  The site isn't really anything special or different from any of the numerous other video streaming websites that do the same thing.  It's pretty bare-bones.  I mostly just wanted to try my hand at implementing and scaling one of the hardest things you can do on the web right now: live streaming video.  It's running on Digital Ocean on a pretty small budget (max $50/month).  To date, it has served video streams to 150,000 unique viewers, with about 13,000 uniques in January 2016.  I'm really happy with the acceptance and usage of the site, especially since I've been able to scale it in a way that stays within my budget.


Every once in a while someone will start a stream and then hotlink it on their own site, playing in their own player.  I've never had any problem with this before since I offer the VLC (HLS playlist) link right there on the player page.  It's totally reasonable that people want to watch their streams in whatever software they want.  The problem that I've run into is that sometimes these 3rd party stream embeds cause an enormous amount of unexpected traffic that my poor small servers just can't handle.  I've reached bandwidth capacity on my Droplets on more than one occasion, which gets problematic for Digital Ocean admins, and rightly so.  I'm not intending to run a CDN for arbitrary websites to host video streams.  [Streamboat.tv](https://streamboat.tv/) is just a small-time streaming site running on a shoestring budget.

## Hotlink protection

I resisted doing this for a long time.  Unfortunately I got to the point where I just couldn't risk overloading my Droplets, or going over my budget.  This is how I locked stream playback to just visitors of [Streamboat.tv](https://streamboat.tv/).

### nginx

nginx is compiled with OpenResty's [set-misc-module](https://github.com/openresty/set-misc-nginx-module), which provides a number of crypto hashing functions including `set_sha1`, which I use in the configuration below:

```nginx
...
root /var/www/streamboat.tv;
set $secret "my-hotlink-secret";

location ~ ^/live/.+\.m3u8$ {
    set_sha1 $expected_digest "${secret}${remote_addr}";

    if ($expected_digest != $arg_digest) {
        return 403;
    }
}
```

Requests for the HLS playlist are validated by comparing the SHA-1 of `$secret + $remote_addr`, with the SHA-1 in the `digest` query parameter.  Playlist URLs served up by the [Streamboat.tv](https://streamboat.tv/) backend (ie, when you visit a stream page) automatically add this digest parameter.  However, when a streamer just copies this URL and embeds it on their own site, it will fail to play back for their viewers since the digest won't match.

### Varnish

The same thing has to be implemented in Varnish.  I used [libvmod-digest](https://github.com/varnish/libvmod-digest) to get the SHA-1 function available in my Varnish VCL.


```varnish
...

import digest;

sub vcl_recv {
    set req.http.X-Client-IP = client.ip;
    set req.http.X-Secure-Hash = digest.hash_sha1("my-hotlink-secret" + req.http.X-Client-IP);
    set req.http.X-Provided-Secure-Hash = regsub(req.url, "^.*digest=([a-zA-Z0-9]+).*$", "\1");

    // normalize the URL so it's still cacheable
    set req.url = regsub(req.url, "^(.*)digest=([a-zA-Z0-9]+)(.*)$", "\1\3");

    if (req.url ~ "/live/") {

        if (req.url ~ "\.m3u8" &&
            req.http.X-Secure-Hash != req.http.X-Provided-Secure-Hash) {

            return (synth(403, "forbidden"));
        }

...
```

And that's basically it.  It doesn't rely on fungible `Referer` blocks, or any other non-scalable mechanisms.  People can watch their streams however they want as long as they personally got the link from [Streamboat.tv](https://streamboat.tv/).
