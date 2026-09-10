from pathlib import Path
import soundfile as sf
from kokoro_onnx import Kokoro

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "the_case_against" / "output" / "ep01"
OUT.mkdir(parents=True, exist_ok=True)

MODEL = ROOT / "kokoro-v1.0.int8.onnx"
VOICES = ROOT / "voices-v1.0.bin"
VOICE = "am_onyx"
SPEED = 0.93

SCRIPT = """There is a version of the LeBron James story where the verdict is already in. Four championships. Four Finals MVP awards. More points than anyone who ever played in the regular season. More playoff points than anyone. More playoff wins than anyone. Two decades of elite basketball. If greatness is measured by how much elite basketball one player can give you over time, the case almost writes itself.

But this is not the case for LeBron. This is the case against LeBron being the greatest player of all time.

And if you want to challenge the strongest argument in basketball, you cannot bring lazy hate. You have to bring the best evidence the other side has.

Exhibit A: the Finals record.

LeBron reached the NBA Finals ten times and won four championships. That means six Finals losses. His supporters will say reaching ten Finals is an accomplishment by itself, and they are right. But the prosecution asks a different question. If the title is greatest ever, should the standard be appearances, or should it be finishing the job?

Michael Jordan reached six Finals and won all six. He also won Finals MVP all six times. The cleanest version of the case against LeBron starts right there. When Jordan reached the final stage, the story ended with a championship every time. When LeBron reached it, the result was more complicated.

Now, that number can lie if you treat it like context does not matter. LeBron lost to the San Antonio Spurs as a young star in 2007. He lost to a Golden State team that became one of the defining dynasties of the era. In 2015, Cleveland entered the Finals without Kevin Love and lost Kyrie Irving after Game One. A Finals loss is not automatically proof that the best player failed.

But there is one Finals loss the prosecution will not let go.

Exhibit B: 2011.

Miami had LeBron James, Dwyane Wade, and Chris Bosh. The Heat entered the season with championship expectations, reached the Finals, and then lost to Dallas in six games. LeBron averaged seventeen point eight points in that series. In Game Four, he scored eight points.

For a player in the greatest-ever conversation, that series is difficult to explain away. It was not late-career LeBron. It was not a roster stripped by injuries. Dallas was excellent, smart, experienced, and brilliantly coached. But Miami had enormous talent, and LeBron did not play like the best player in the world when the championship was there to be taken.

The defense will say that failure changed him. And it did. One year later, he won his first title and Finals MVP. But the case against him is not asking whether he recovered. It is asking whether the greatest career should contain a collapse that severe at the center of a player's physical prime.

Exhibit C: team construction.

LeBron changed the way superstar movement works in the modern NBA. He joined Wade and Bosh in Miami. He returned to Cleveland, where Kyrie Irving was already there and Kevin Love soon arrived. Later, he joined the Lakers, and Anthony Davis became his championship partner.

There is nothing illegal about that. Players are allowed to choose their teams. Front offices have always built around stars. Jordan had Scottie Pippen. Magic had Kareem. Bird had McHale and Parish. Nobody wins alone.

But the prosecution's argument is about how much control a superstar had over the environment around him. LeBron's career includes multiple resets, multiple organizations, and multiple title windows built around new combinations of elite talent. Critics argue that when the situation stopped looking good enough, the ecosystem changed.

That does not erase the championships. It does create a different kind of greatness argument from the one built around dominating with one franchise through the same competitive cycle.

Exhibit D: peak versus longevity.

This might be the real case.

LeBron's career is almost impossible to match for duration. By the end of the twenty twenty-five twenty-six regular season, he had more than forty-three thousand regular-season points and had become the league's all-time leader in games played. He has also produced more playoff points and playoff wins than any player in NBA history.

That is absurd.

But longevity and peak are not automatically the same question.

Jordan retired with the highest career scoring average in league history at thirty point one points per game. He won ten scoring titles, five regular-season MVP awards, six championships, six Finals MVP awards, and a Defensive Player of the Year award.

So the prosecution asks this: if you were choosing one player at his absolute best for one season, one playoff run, or one Finals, are you choosing the player who sustained greatness the longest, or the player whose peak felt more overwhelming?

There is no stat that settles that question. It is a definition problem disguised as a basketball argument.

Now the defense gets the floor.

Because if we are going to put LeBron on trial, we have to admit how ridiculous the defense is.

He is the only player in NBA history with at least ten thousand points, ten thousand rebounds, and ten thousand assists. He is a four-time league MVP and four-time Finals MVP. He won championships with three different franchises. He has more regular-season points than anyone and more playoff points than anyone.

And then there is 2016.

Cleveland fell behind Golden State three games to one in the Finals. The Warriors had won seventy-three games in the regular season. No team had ever come back from a three-to-one deficit in the NBA Finals.

LeBron and the Cavaliers did it.

He and Kyrie Irving each scored forty-one points in Game Five. LeBron scored forty-one again in Game Six. Cleveland won Game Seven, and a city that had waited fifty-two years for a major sports championship finally had one.

If the prosecution wants to use Finals record as evidence, the defense gets to put 2016 on the biggest screen in the building.

That championship is not just a ring. It is one of the strongest single pieces of evidence any player has ever produced in a greatest-ever debate.

And this is where the case gets uncomfortable.

The argument against LeBron is strongest when it focuses on the 2011 Finals, the difference between four championships in ten Finals and Jordan's six in six, and the question of whether longevity should outweigh peak dominance.

But the argument starts falling apart when it pretends LeBron's longevity is just stat padding, or that changing teams means his titles do not count, or that reaching ten Finals somehow hurts his résumé.

It does not.

The real debate is much narrower.

What do you value most?

If greatest means the cleanest championship peak, the six-for-six Finals record, scoring dominance, and a shorter career with fewer visible failures, Jordan has an extraordinary case.

If greatest means total basketball value across the longest possible span, elite play across eras, unmatched accumulation, versatility, and winning in multiple environments, LeBron has an extraordinary case.

So did the prosecution prove LeBron cannot be the GOAT?

No.

That was never the point.

The point was to see whether the strongest case against him could survive its own cross-examination.

Some of it did.

Some of it did not.

And that is why this debate will never die.

The evidence is in.

Case made.

You decide."""

# Break on paragraphs so Kokoro gets natural pauses and avoids long-input instability.
chunks = [p.strip() for p in SCRIPT.split("\n\n") if p.strip()]
kokoro = Kokoro(str(MODEL), str(VOICES))
parts = []
sr = None
for i, text in enumerate(chunks):
    samples, rate = kokoro.create(text, voice=VOICE, speed=SPEED, lang="en-us")
    if sr is None:
        sr = rate
    elif rate != sr:
        raise RuntimeError(f"Sample rate changed: {rate} vs {sr}")
    # ~220 ms pause between paragraphs.
    import numpy as np
    pause = np.zeros(int(sr * 0.22), dtype=samples.dtype)
    parts.extend([samples, pause])

import numpy as np
full = np.concatenate(parts)
raw = OUT / "malik_ep01_raw.wav"
sf.write(raw, full, sr)
print(f"Wrote {raw} at {sr} Hz, {len(full)/sr:.1f}s")
