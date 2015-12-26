---
layout: post
title:  "How I built ghit.me, hit count badges for github"
date:   2015-12-25 15:57:28
categories: nginx syslog-ng redis github hit counter
comments: true
---

If you read my blog then you know that I find special pleasure in solving a problem without writing any (or very little) of my own code.  That was my goal for [ghit.me](https://ghit.me/), which is a simple hit counter badge for your Github repos.  This is how I did it.

The goal was to be able to put a simple hit counter badge in your Github repo's README.md file, which is very common and useful.  When a person views your repo on Github, the badge is fetched from the backend server which 1) displays the current hit count, 2) increments the hit count.  As with most of the things I build, it starts out with [nginx](http://nginx.org/), [syslog-ng](https://www.balabit.com/network-security/syslog-ng), and [redis](http://redis.io/).

## nginx

```nginx
http {
    log_format badge '"$datestr","$escaped_repo"';
    ...
}
...
location = /badge.svg {
    expires -1d;
    set_formatted_gmt_time $datestr "%Y-%m-%d";
    set_escape_uri $escaped_repo $arg_repo;
    access_log syslog:server=127.0.0.1,facility=local3,tag=badge,severity=info badge;
    alias /var/www/ghit.me/badges/$escaped_repo.svg;
}  
```

We set a custom log format called `badge` which is a simple CSV of the date, and the repo name, (e.g. `"2015-12-25","benwilber%2Fbashids"`).  We used the `set_formatted_gmt_time` and `set_escape_uri` functions from the [SetMiscModule](https://github.com/openresty/set-misc-nginx-module).  It's important to always escape values that you plan to use in a structured format.

So now we have all of our badge requests logging to syslog in a nice CSV format.

## syslog-ng

```
parser p_badge {
    csv-parser(columns("BADGE.DATE", "BADGE.REPO")
        flags(escape-double-char,strip-whitespace)
        delimiters(",")
        quote-pairs('""[]'));
};

destination d_badge_redis {
    redis(command("SADD" "repos" "${BADGE.REPO}"));
    redis(command("SADD" "repos:${BADGE.DATE}" "${BADGE.REPO}"));
    redis(command("INCR" "repo:${BADGE.REPO}"));
    redis(command("INCR" "repo:${BADGE.DATE}:${BADGE.REPO}"));
};

filter f_badge {
    facility(local3) and level(info) and program("badge");
};

log {
    source(s_sys);
    filter(f_badge);
    parser(p_badge);
    destination(d_badge_redis);
};
```

Now we set syslog-ng to filter and parse these messages, and do some Redis operations with them.  In this case we're just adding the repo to the set `repos` (all time counters) and `repos:<date>`, which is daily counters.  And we just increment the hit counter for each repo, one for total, and one for each day.

And now we just use a really simple cronjob to aggregate counters for each repo, and write new svg badge images.
