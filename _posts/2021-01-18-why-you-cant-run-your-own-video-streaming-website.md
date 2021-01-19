---
layout: post
title: "Why you can't run your own video streaming website"
date: 2021-01-18 00:00:00
categories: video
comments: true
---
<style>
pre {
    white-space: pre-wrap;       /* css-3 */
    white-space: -moz-pre-wrap;  /* Mozilla, since 1999 */
    white-space: -pre-wrap;      /* Opera 4-6 */
    white-space: -o-pre-wrap;    /* Opera 7 */
    word-wrap: break-word;       /* Internet Explorer 5.5+ */
}
</style>

In 2016 I started a website called Streamboat.tv.  The idea behind it was very simple: no-nonsense live-streaming via RTMP and playback via HLS.  Although it never caught on in the mainstream, it became wildly popular amongst a certain category of video streamers: pirates and pornographers.

I launched Streamboat.tv in April 2016.  I had been working on the infrastructure and tech behind it for several months and finally got it to a place where it worked "good enough" and scaled in the way that I thought was most needed, specifically the RTMP ingest -> egress.

Back then Digital Ocean didn't actually charge for egress bandwidth from servers in their US regions.  Little-known fact.  I discovered this after a few support inquiries like "how can I see my egress bandwidth usage from my Droplets?" -- and they responded with basically "we don't account for bandwidth at this time."

Oh, you don't account for bandwidth?  What if I launch a few Varnish servers in every Digital Ocean region and have them serve my Streamboat.tv video streams?

That's what I did.

<strong>May 2016</strong>

<pre>
New Support Ticket - Inbound DDoS Detected -- live-us-east-00.streamboat.tv
DigitalOcean <support@support.digitalocean.com>
    
Wed, Jul 20, 2016, 4:39 AM
    
Hi there,

Our system has automatically detected an inbound DDoS against your droplet named live-us-east-00.streamboat.tv with the following IP Address: REDACTED

As a precautionary measure, we have temporarily disabled network traffic to your droplet to protect our network and other customers. Once the attack subsides, networking will be automatically reestablished to your droplet. The networking restriction is in place for three hours and then removed.

Please note that we take this measure only as a last resort when other filtering, routing, and network configuration changes have not been effective in routing around the DDoS attack.

Please let us know if there are any questions, we're happy to help.

Thank you,
DigitalOcean Support
</pre>

This single Droplet was running Varnish and pushing about 1 Gb/s to Streamboat.tv viewers.  I was running dozens of these egress/CDN edge servers in every Digital Ocean region.  When they shut one off I would politely apoligize, and then shut off the offending streamer.  But the emails kept coming from Digital Ocean.

And then the big one came:

<pre>
Hi Ben,

We were alerted that, of the top 10 droplets in NYC3 in terms of bandwidth usage, you happened to be all 10 of them.

Upon investigation I noticed that there was a Canadiens vs Sabres hockey game, a Denver vs San Diego football game, and some sort of anime being streamed.

Unfortunately once we realized that this was copyright infringing material (with no legitimate material that we could see) we were put in an awkward position where, since we now knew about this, had to take some action regarding it.

From our end, we have three concerns:

1) Streaming copyrighted material in the fashion we observed is illegal, and as such a violation of our Terms of Service, which mandates we take action in these cases. I understand you can't completely control the activities of your users, but would be curious to know what policies and procedures and escalation paths that are in place to handle issues such as this when they happen.

2) REDACTED

3) The type of bandwidth usage we saw is, quite bluntly, exceedingly expensive to utilize, and we're currently in the process of deploying bandwidth billing - this evening's activities would put you well into a five-figure overage, at the very very least.

We'd be happy to work with you on building your steamboat.tv business with us, but, as mentioned above, there's a few things that'd need to be addressed for both you and us to be successful in doing so.

Regards,

REDACTED
Trust & Safety,
Digital Ocean Support 
</pre>

There was no possible way that I could continue to operate streamboat.tv anymore.  Pirate sports streamers, anime, and pornographers had taken over the site and that was the only thing it was being used for.

> this evening's activities would put you well into a five-figure overage

There was no way that I was ever going to be able to afford a $20,000/day bandwidth bill to stream some shitty pirate sports streams to 100,000 people.

Thus, streamboat.tv died.

And this is why you can't run your own video streaming website.


But if you're still interested, check out [Boltstream](https://github.com/benwilber/boltstream) and [how to make it](https://benwilber.github.io/nginx/rtmp/live/video/streaming/2018/03/25/building-a-live-video-streaming-website-part-1-start-streaming.html)


