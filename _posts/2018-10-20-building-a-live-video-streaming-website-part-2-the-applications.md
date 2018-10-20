---
layout: post
title:  "Building a live video streaming website - Part 2 - The Application"
date:   2018-10-20 00:00:00
categories: nginx rtmp live video streaming django
comments: true
---

This is part 2 of a series on creating a Twitch.tv-like live video streaming website.  See [Part 1 - Start Streaming! here](/nginx/rtmp/live/video/streaming/2018/03/24/building-a-live-video-streaming-website-part-1-start-streaming.html)

# The Application

Now that we have video streaming working, we need to build a web application to manage the streams.  I'm using Django and Python 3, but any web framework will work.

## The Django application

Start by creating your new Django project:

```shell
$ mkvirtualenv -p python3.6 boltstream
$ pip install Django
$ django-admin startproject boltstream
$ cd boltstream
$ pip freeze > requirements.txt
$ tree
.
├── boltstream
│   ├── __init__.py
│   ├── settings.py
│   ├── urls.py
│   └── wsgi.py
├── manage.py
└── requirements.txt

1 directory, 6 files
```

We'll start by creating an admin view, some other views, and one simple model.

```shell
$ touch boltstream/{admin,views,models}.py
```

Our `models.py` will look like this:

```python
from functools import partial

from django.conf import settings
from django.db import models
from django.db.models.signals import post_save
from django.dispatch import receiver
from django.urls import reverse
from django.utils.crypto import get_random_string


make_stream_key = partial(get_random_string, 20)


class Stream(models.Model):

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL, related_name="stream", on_delete=models.CASCADE)
    key = models.CharField(max_length=20, default=make_stream_key, unique=True)
    started_at = models.DateTimeField(null=True, blank=True)

    def __str__(self):
        return self.user.username

    @property
    def is_live(self):
        return self.started_at is not None

    @property
    def hls_url(self):
        return reverse("hls-url", args=(self.user.username,))


@receiver(post_save, sender=settings.AUTH_USER_MODEL, dispatch_uid="create_stream_for_user")
def create_stream_for_user(sender, instance=None, created=False, **kwargs):
    """ Create a stream for new users.
    """
    if created:
        Stream.objects.create(user=instance)
```

and `admin.py`:

```python
from django.contrib import admin

from .models import Stream


@admin.register(Stream)
class StreamAdmin(admin.ModelAdmin):
    list_display = ("__str__", "started_at", "is_live")
    readonly_fields = ("hls_url",)
```

Right now our `views.py` just consists of HTTP callbacks dispatched by nginx-rtmp when streaming starts and stops:


```python
from django.http import HttpResponse, HttpResponseForbidden
from django.shortcuts import redirect, get_object_or_404
from django.utils import timezone
from django.views.decorators.http import require_POST
from django.views.decorators.csrf import csrf_exempt

from .models import Stream


@require_POST
@csrf_exempt
def start_stream(request):
    """ This view is called when a stream starts.
    """
    stream = get_object_or_404(Stream, key=request.POST["name"])

    # Ban streamers by setting them inactive
    if not stream.user.is_active:
        return HttpResponseForbidden("Inactive user")

    # Don't allow the same stream to be published multiple times
    if stream.started_at:
        return HttpResponseForbidden("Already streaming")

    stream.started_at = timezone.now()
    stream.save()

    # Redirect to the streamer's public username
    return redirect(stream.user.username)


@require_POST
@csrf_exempt
def stop_stream(request):
    """ This view is called when a stream stops.
    """
    Stream.objects.filter(key=request.POST["name"]).update(started_at=None)
    return HttpResponse("OK")
```

Hook the views up to the URL paths.

`urls.py`:

```python
from django.contrib import admin
from django.urls import path

from .views import start_stream, stop_stream


def fake_view(*args, **kwargs):
    """ This view should never be called because the URL paths
        that map here will be served by nginx directly.
    """
    raise Exception("This should never be called!")


urlpatterns = [
    path("admin/", admin.site.urls),
    path("start_stream", start_stream, name="start-stream"),
    path("stop_stream", stop_stream, name="stop-stream"),
    path("live/<username>/index.m3u8", fake_view, name="hls-url")
]
```

Add our application to `settings.py` in `INSTALLED_APPS`:

```python
INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',

    "boltstream"
]
```

Create the migrations:

```shell
$ ./manage.py makemigrations boltstream
Migrations for 'boltstream':
  boltstream/migrations/0001_initial.py
    - Create model Stream
```

We're just going to use the default sqlite database backend for now.  So apply the migrations:

```shell
$ ./manage.py migrate
Operations to perform:
  Apply all migrations: admin, auth, boltstream, contenttypes, sessions
Running migrations:
  Applying contenttypes.0001_initial... OK
  Applying auth.0001_initial... OK
  Applying admin.0001_initial... OK
  Applying admin.0002_logentry_remove_auto_add... OK
  Applying admin.0003_logentry_add_action_flag_choices... OK
  Applying contenttypes.0002_remove_content_type_name... OK
  Applying auth.0002_alter_permission_name_max_length... OK
  Applying auth.0003_alter_user_email_max_length... OK
  Applying auth.0004_alter_user_username_opts... OK
  Applying auth.0005_alter_user_last_login_null... OK
  Applying auth.0006_require_contenttypes_0002... OK
  Applying auth.0007_alter_validators_add_error_messages... OK
  Applying auth.0008_alter_user_username_max_length... OK
  Applying auth.0009_alter_user_last_name_max_length... OK
  Applying boltstream.0001_initial... OK
  Applying sessions.0001_initial... OK
```

Create yourself a superuser:

```shell
$ ./manage.py createsuperuser
Username (leave blank to use 'benw'): 
Email address: 
Password: 
Password (again): 
Superuser created successfully.
```

Run the development server:

```shell
$ ./manage.py runserver
Performing system checks...

System check identified no issues (0 silenced).
October 20, 2018 - 19:59:00
Django version 2.1.2, using settings 'boltstream.settings'
Starting development server at http://127.0.0.1:8000/
Quit the server with CONTROL-C.
```

Now you can browse to the [Django admin at http://localhost:8000/admin/](http://localhost:8000/admin/) and see that it automatically created a stream for your user.

![](https://sunspot.io/i/2fxrcp2wxx.png)

## nginx configuration

Next we're going to add the RTMP dispatchers and the stream key -> username redirect.

Update the `nginx.conf` from [Part 1](/nginx/rtmp/live/video/streaming/2018/03/24/building-a-live-video-streaming-website-part-1-start-streaming.html) to the following:

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

        location ~ ^/live/.+\.ts$ {
            # MPEG-TS segments can be cached upstream indefinitely
            expires max;
        }

        location ~ ^/live/[^/]+/index\.m3u8$ {
            # Don't cache live HLS manifests
            expires -1d;
        }

        location / {
            proxy_pass http://127.0.0.1:8000/;
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

            # Push the stream to the local HLS application
            push rtmp://127.0.0.1:1935/hls;

            # The on_publish callback will redirect the RTMP
            # stream to the streamer's username, rather than their
            # secret stream key.
            on_publish http://127.0.0.1:8000/start_stream;
            on_publish_done http://127.0.0.1:8000/stop_stream;
        }

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
        }
    }
}
```

Now we can just copy our stream key from the Django admin and start streaming and see it reflected in our Django application:

```shell
$ ffmpeg -re -i <file.mp4> -c copy -f flv rtmp://boltstream.me/app/8FyNMs7A4fcsAZwWHDYQ
```

And play back the HLS stream under our own username.  Nobody sees your private stream key.


```
$ ffplay http://boltstream.me/live/benw/index.m3u8
```

<hr>

In the next part we're going to add some simple DRM (AES-128 HLS encryption) so that nobody gets to watch your streams unless your want them to.

* [Part 1 - Start Streaming!](/nginx/rtmp/live/video/streaming/2018/03/24/building-a-live-video-streaming-website-part-1-start-streaming.html)
* [Part 2 - The Application](/nginx/rtmp/live/video/streaming/django/2018/10/19/building-a-live-video-streaming-website-part-2-the-applications.html)
* Part 3 - DRM
* Part 4 - We're big now!  Adding a CDN
* Part 5 - Bringing it all together
