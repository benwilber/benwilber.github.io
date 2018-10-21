---
layout: post
title:  "Building a live video streaming website - Part 1 - Start Streaming!"
date:   2018-03-25 00:00:00
categories: nginx rtmp live video streaming
comments: true
---

# Introduction

I've been working with live video streaming in some capacity for several years.  Everything from simple Periscope or Meerkat clones, to very large-scale live sports productions (Super Bowl, FIFA World Cup).  There are many open source tools available to build services like this yourself if you know what they are and how to use them.  This guide attempts to introduce you to the tech behind live streaming by walking through the construction of a [Twitch.tv](https://twitch.tv)-like website all the way from bare metal (ok, VPS) to backend web application and HTML/CSS.

This is a multipart guide that follows (roughly) this schedule:

* Part 1 - Start Streaming!
* Part 2 - The Application
* Part 3 - DRM
* Part 4 - We're big now!  Adding a CDN
* Part 5 - Bringing it all together

**WARNING**

*Live video streaming is one of the most difficult (and expensive!) things you can do at scale on the web today.  Due to the extreme bandwidth costs involved, almost all streaming sites fail without a very solid, sustainable product + business model behind it.  User-gen streaming sites are also havens for "pirate streamers" -- people that re-broadcast Pay-Per-View, live sports, and other copyrighted content.  If you choose to use this guide to launch such a site then you should be prepared for these users and the responsibility of responding to DMCA takedown requests.*

Let's get started!

## Step 1 - The Server

**You need a server**

It doesn't matter what VPS host you choose, or even if you choose to run it locally via Vagrant or other VM.  I chose [DigitalOcean](http://digitalocean.com/) but you can use whatever host you're comfortable with.

**You need a Linux OS**

This guide is very opinionated about almost everything and especially assumes it's being deployed on a fresh [CentOS 7](https://www.centos.org/) install.  But if you're savvy enough to apply this guide to your own favorite distro then I'm sure it will work just fine.

However, from here on this guide assumes a newly launched CentOS 7 server hosted on DigitalOcean.

**You need a domain name**

OK this one isn't strictly required but makes everything a lot easier to work with.  I'm using `boltstream.me` for this guide, but you can use any subdomain of a domain you already own, or even just an IP address if you want.

### Prepare the server

Bring the system up-to-date:

```shell
$ yum update -y
```

You need to allow some services through the firewall.  On CentOS 7 you need to install the `iptables-services` package:

```shell
$ yum install -y iptables-services
$ systemctl enable iptables
```

Specifically, the ports you need are:

* tcp/22 (SSH)
* tcp/80 (HTTP)
* tcp/443 (HTTPS)
* tcp/1935 (RTMP)

Put this file at `/etc/sysconfig/iptables`

```
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
-A INPUT -p icmp -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -m state --state NEW -m tcp -p tcp --dport 22 -j ACCEPT -m comment --comment "ssh"
-A INPUT -m state --state NEW -m tcp -p tcp --dport 80 -j ACCEPT -m comment --comment "http"
-A INPUT -m state --state NEW -m tcp -p tcp --dport 443 -j ACCEPT -m comment --comment "https"
-A INPUT -m state --state NEW -m tcp -p tcp --dport 1935 -j ACCEPT -m comment --comment "rtmp"
-A INPUT -j REJECT --reject-with icmp-host-prohibited
-A FORWARD -j REJECT --reject-with icmp-host-prohibited
COMMIT

# DO NOT REMOVE THIS LINE
```

And then run:

```shell
$ systemctl restart iptables
```

## Step 2 - NGINX

I don't like installing packages from source but sometimes it's necessary.  In this case we need to compile NGINX from source in order to add support for a few 3rd-party modules that we need.  However, we're not going to do just straight source installs, but rather we're going to rebuild the NGINX source RPMs with the required modules.

**Building NGINX with RTMP support**

```shell
$ yum install -y epel-release yum-utils rpm-build wget gcc
```

Install the NGINX build dependencies

```shell
$ yum-builddep -y nginx
```

We're going to rebuild the NGINX source RPMs so we need to add the `mockbuild` user:

```shell
$ useradd mockbuild
$ su mockbuild
$ cd
```

Download the NGINX source RPM

```shell
$ yumdownloader --source nginx
```

Install the NGINX source RPM

```shell
$ rpm -U nginx-1.12.2-1.el7.src.rpm
```

This installed the NGINX source RPM in `/home/mockbuild/rpmbuild`:

```shell
$ find rpmbuild/
rpmbuild/
rpmbuild/SOURCES
rpmbuild/SOURCES/404.html
rpmbuild/SOURCES/50x.html
rpmbuild/SOURCES/README.dynamic
rpmbuild/SOURCES/UPGRADE-NOTES-1.6-to-1.10
rpmbuild/SOURCES/index.html
rpmbuild/SOURCES/nginx-1.12.2.tar.gz
rpmbuild/SOURCES/nginx-1.12.2.tar.gz.asc
rpmbuild/SOURCES/nginx-auto-cc-gcc.patch
rpmbuild/SOURCES/nginx-logo.png
rpmbuild/SOURCES/nginx-upgrade
rpmbuild/SOURCES/nginx-upgrade.8
rpmbuild/SOURCES/nginx.conf
rpmbuild/SOURCES/nginx.logrotate
rpmbuild/SOURCES/nginx.service
rpmbuild/SOURCES/poweredby.png
rpmbuild/SPECS
rpmbuild/SPECS/nginx.spec
```

The file that we're interested in is `nginx.spec`.  In order to add RTMP support to our NGINX install, we need to copy that file to `rpmbuild/SPECS/nginx-rtmp.spec` and modify it.

```shell
$ cp rpmbuild/SPECS/nginx.spec rpmbuild/SPECS/nginx-rtmp.spec
```

But first we need to get `nginx-rtmp-module`.

```shell
$ wget -qO- https://github.com/sergey-dryabzhinsky/nginx-rtmp-module/archive/dev.tar.gz | tar zx
```

This is a fork of `nginx-rtmp-module` from [https://github.com/arut/nginx-rtmp-module](https://github.com/arut/nginx-rtmp-module) that adds a few useful features that we want.

Find and add this line in `nginx-rtmp.spec`:

```
    ...
    --with-pcre \
    --with-pcre-jit \
    --with-stream=dynamic \
    --with-stream_ssl_module \
    # add this line: 
    --add-module=/home/mockbuild/nginx-rtmp-module-dev \
%if 0%{?with_gperftools}
    --with-google_perftools_module \
%endif
    ...
```

Now build NGINX with RTMP support:

```shell
$ rpmbuild -bb rpmbuild/SPECS/nginx-rtmp.spec
```

Exit out of the `mockbuild` shell by pressing Ctrl-D or type `exit`

Install our new NGINX RPMs 

```shell
$ find /home/mockbuild/rpmbuild/RPMS -name 'nginx-*.rpm' | xargs rpm -U --force 
```

**Configuring NGINX for RTMP ingest**

First we need to disable SELinux so that NGINX can listen on port 1935 (don't worry, we're going to re-enable it later):

```shell
$ setenforce 0
```

Create the necessary web directories

```shell
$ mkdir -pZ /var/www/live
$ chown -R nginx:nginx /var/www
```

Copy the following to `/etc/nginx/nginx.conf`

```nginx
user nginx;

# I'll explain why we only have 1 worker process later
worker_processes 1;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

include /usr/share/nginx/modules/*.conf;

events {
    use epoll;
    worker_connections 1024;
}

http {
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" $request_time';
    access_log /var/log/nginx/access.log main;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    server {
        listen 80 default_server;
        server_name _;
        root /var/www;
        expires -1d;

        location ~ ^/live/.+\.ts$ {
            # MPEG-TS segments can be cached upstream indefinitely
            expires max;
        }
    }
}

rtmp {
    server {
        listen 1935;

        application app {
            live on;

            # Don't allow RTMP playback
            deny play all;

            # Package streams as HLS
            hls on;
            hls_path /var/www/live;
            hls_nested on;
            hls_fragment_naming system;
            hls_datetime system;
        }
    }
}
```

Start and enable NGINX

```shell
$ systemctl enable nginx
$ systemctl start nginx
```

Now you can use [OBS Studio](https://obsproject.com/), [XSplit](https://www.xsplit.com/), or even just [FFMPEG](http://ffmpeg.org/) to stream to your site.

```shell
$ ffmpeg -re -i <file.mp4> -c copy -f flv rtmp://boltstream.me/app/mystream
```

And play it back with VLC or another player:

```
$ ffplay http://boltstream.me/live/mystream/index.m3u8
```

<hr>

In the next part we're going to create a simple Django-based web application so that users can sign up and live-stream on their own page.

* [Part 1 - Start Streaming!](/nginx/rtmp/live/video/streaming/2018/03/25/building-a-live-video-streaming-website-part-1-start-streaming.html)
* [Part 2 - The Application](/nginx/rtmp/live/video/streaming/django/2018/10/20/building-a-live-video-streaming-website-part-2-the-applications.html)
* [Part 3 - DRM](/nginx/rtmp/live/video/streaming/django/drm/2018/10/20/building-a-live-video-streaming-website-part-3-drm.html)
* Part 4 - We're big now!  Adding a CDN
* Part 5 - Bringing it all together

