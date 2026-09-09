from pathlib import Path
import soundfile as sf
from kokoro_onnx import Kokoro

TEXT = """There was a time when picking your Top 8 could actually start an argument. Before Instagram. Before TikTok. Before Facebook took over the world... there was MySpace.

Your profile had a theme. Your favorite song started playing whether anybody wanted it to or not. Glitter backgrounds, wild fonts, custom HTML, comments from people you barely knew... and somehow, everybody was already friends with the same dude named Tom.

For a few years, MySpace wasn't just a website. It felt like the internet itself.

So how did one of the biggest social networks on Earth go from hundreds of millions of profiles... to the place most people forgot to visit?

This is Whatever Happened To MySpace.

MySpace was created in 2003 by Chris DeWolfe, Tom Anderson, and a team working inside Intermix Media. And the idea hit at exactly the right moment.

The internet was changing. Broadband was spreading. Digital cameras were becoming normal. Music was moving online. And teenagers were discovering that the web didn't have to look like a boring office document.

MySpace gave people a page that actually felt like theirs.

You could change the colors. Change the background. Add photos. Add a song. Add graphics. Add enough glitter to make a web designer cry. If you knew a little HTML, or knew somebody who knew a little HTML, you could turn your profile into whatever you wanted.

Sometimes it looked amazing.

Sometimes it looked like a keyboard exploded inside a Hot Topic.

But that was the point. It was personal.

And then there was the Top 8.

Today, apps quietly sort people with algorithms. MySpace basically said: nah... rank your friends publicly.

Eight little pictures. Right there on your profile. Everybody could see who made the cut, who moved up, who moved down, and who disappeared completely.

Friendships were tested. Relationships were questioned. Somebody would log in after school, realize they got dropped from number three to number seven, and suddenly the group chat before group chats existed was on fire.

And waiting inside almost everybody's friend list was Tom Anderson.

Tom was one of MySpace's founders, and for years new users automatically got his profile as their first friend. That simple move turned a tech founder into one of the most recognizable faces of the early social internet.

He wasn't posting motivational speeches. He wasn't trying to become an influencer. He was just... there. Smiling in that profile picture like the internet's landlord.

MySpace also understood something huge before a lot of traditional media companies did: music and social networking belonged together.

Bands didn't have to wait for radio, magazines, or a record label to introduce them to fans. They could build a page, upload music, post dates, talk directly to listeners, and watch people spread songs through their profiles.

By August 2006, MySpace said it had registered its one hundred millionth profile. It wasn't just a hangout anymore. It was a cultural machine.

And big business noticed.

In 2005, Rupert Murdoch's News Corporation agreed to buy Intermix Media, MySpace's parent company, for about five hundred eighty million dollars in cash.

At the time, that number sounded enormous.

Very soon... it started looking cheap.

In August 2006, Google signed a major search and advertising agreement with Fox Interactive Media, the News Corp division that included MySpace. Under that deal, Google committed to guaranteed minimum revenue-share payments totaling nine hundred million dollars, as long as Fox hit certain traffic requirements.

Think about that for a second.

News Corp had paid about five hundred eighty million dollars for Intermix. Then a deal connected to search and advertising across the network carried guaranteed minimum payments of nine hundred million.

MySpace looked like one of the smartest internet purchases ever made.

By 2007, it was still sitting at the center of online culture. Artists, comedians, actors, filmmakers, brands, regular people... everybody wanted a page.

But underneath all that traffic, the product was getting harder to manage.

The freedom people loved also created chaos. Profiles could be slow. Pages could become cluttered. Advertising kept expanding. Different parts of the company were competing for attention. And once News Corp owned the business, MySpace wasn't just trying to build the best social product anymore. It was also expected to become a major media and advertising machine.

That tension mattered because another social network was growing fast.

Facebook launched in 2004 with almost the opposite philosophy.

MySpace said: decorate your room however you want.

Facebook said: everybody gets basically the same room... but we're going to make it easier to find your friends, follow updates, and keep coming back.

MySpace felt like a destination. Facebook became a habit.

And by 2008, the balance had shifted.

ComScore figures reported that April showed Facebook at roughly one hundred sixteen point four million unique users globally, just ahead of MySpace at about one hundred fifteen point seven million.

That was the moment the crown started moving.

It wasn't because one single feature killed MySpace. And it wasn't as simple as saying Facebook showed up and everybody left the next morning.

MySpace had internal problems too.

Product decisions moved slowly. Leadership changed. The site kept trying to balance entertainment, advertising, music, social networking, and corporate goals all at once. Facebook, meanwhile, stayed relentlessly focused on the social product and continued expanding to new groups of users.

Once your friends started spending more time on Facebook, you had a reason to spend more time there too.

That's the brutal thing about social networks. The product isn't only the website.

The product is everybody you know.

By 2009, MySpace was cutting jobs and changing leadership. The site was still enormous, but the momentum had changed direction.

And then the numbers got ugly.

Figures cited by the Los Angeles Times show MySpace's monthly audience peaking around seventy-six point three million in October 2008, then falling to about thirty-five million by May 2011.

Three years earlier, companies were fighting to reach MySpace users.

Now News Corp was looking for a buyer.

In June 2011, Specific Media bought MySpace for thirty-five million dollars in cash and equity.

Five hundred eighty million... down to thirty-five million.

Six years.

That's one of those numbers that doesn't need dramatic music.

But we're going to give it dramatic music anyway.

The strange part is... MySpace never completely vanished.

As of September 2026, Myspace is still online. The modern site focuses heavily on entertainment discovery, including music, videos, people, and editorial content. It doesn't resemble the chaotic blue-and-white social world that dominated the mid-2000s, but the name is still alive.

And maybe that's fitting.

Because a lot of what made MySpace special didn't disappear either.

Artist pages. Direct fan connections. Personal branding. Photo sharing. Messaging. Social identity. Music discovery. Public friend networks. Creators building audiences without waiting for traditional gatekeepers.

Those ideas became normal parts of the internet.

MySpace didn't invent every one of them. But for an entire generation, it was the place where those ideas all collided at once.

So maybe MySpace didn't completely disappear.

Maybe the internet just absorbed it.

The wild customized pages became personal brands. The friend list became followers. The profile song became streaming links and short-form audio. The comments became replies. The artists who once begged you to add their page now build audiences on half a dozen platforms at the same time.

And the Top 8?

Well... apps got smarter than that.

Now they rank everybody without telling us.

Probably safer for friendships.

And somewhere out there, Tom is probably still enjoying life while millions of former MySpace users remember him as the one internet friend who never caused any drama.

I'm Marcus, and this is Whatever Happened To...?

Now you know what happened to it."""

MODEL = "marcus/models/kokoro-v1.0.int8.onnx"
VOICES = "marcus/models/voices-v1.0.bin"
OUT = Path("marcus/output")
OUT.mkdir(parents=True, exist_ok=True)

# LOCKED SHOW VOICE: Marcus = Kokoro am_fenrir
VOICE = "am_fenrir"
SPEED = 0.94

kokoro = Kokoro(MODEL, VOICES)
samples, sample_rate = kokoro.create(TEXT, voice=VOICE, speed=SPEED, lang="en-us")
raw_path = OUT / "Marcus_Fenrir_RAW.wav"
sf.write(raw_path, samples, sample_rate)
print(f"Created {raw_path} using locked voice {VOICE} at {SPEED}x")
