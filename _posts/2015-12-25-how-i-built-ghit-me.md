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

And now we just use a really simple cronjob to aggregate counters for each repo, and write new svg badge images:

```python
#!/usr/bin/env python
from os.path import join as pathjoin
import locale
import redis

# for pretty numbers
locale.setlocale(locale.LC_ALL, 'en_US')

BADGE_DIR = "/var/www/ghit.me/badges"
BADGE_TEMPLATE = """
<svg xmlns="http://www.w3.org/2000/svg" width="95" height="20">
    <linearGradient id="b" x2="0" y2="100%">
        <stop offset="0" stop-color="#bbb" stop-opacity=".1"/>
        <stop offset="1" stop-opacity=".1"/>
    </linearGradient><mask id="a">
    <rect width="95" height="20" rx="3" fill="#fff"/>
    </mask>
    <g mask="url(#a)"><path fill="#555" d="M0 0h53v20H0z"/>
        <path fill="#13B28A" d="M53 0h42v20H53z"/>
        <path fill="url(#b)" d="M0 0h95v20H0z"/>
    </g>
    <g fill="#fff" text-anchor="middle" font-family="DejaVu Sans,Verdana,Geneva,sans-serif" font-size="11">
        <text x="26.5" y="15" fill="#010101" fill-opacity=".3">ghit.me</text>
        <text x="26.5" y="14">ghit.me</text><text x="73" y="15" fill="#010101" fill-opacity=".3">
            {count}
        </text>
        <text x="73" y="14">
            {count}
        </text>
    </g>
</svg>
"""


def repokey(repo):
    """redis key storing counts for a repo
    """
    return "repo:{}".format(repo)


def writebadge(repo, count):
    """Write updated count to <repo>.svg
    """
    path = "{}.svg".format(pathjoin(BADGE_DIR, repo))
    # 1000 -> 1,000
    svg = BADGE_TEMPLATE.format(
        count=locale.format("%d", count, grouping=True))

    with open(path, "wb") as fd:
        fd.write(svg)


def main():
    r = redis.Redis()
    repos = r.smembers("repos")
    repo_keys = map(repokey, repos)
    for repo, count in zip(repos, r.mget(repo_keys)):
        writebadge(repo, int(count or 0))


if __name__ == '__main__':
    main()
```
