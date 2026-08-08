# How the prayer times are calculated

Your prompt does not ask a website what time Maghrib is. It works it out, on your machine, from
where you are and what the sun is doing — the same way a printed timetable is worked out, just
recalculated fresh instead of looked up.

This page explains exactly how, and links to the published sources for every part of it. If you
pray by these times, you deserve to be able to check them.

## Step one: where is the sun?

Everything starts with one question — for this instant, where is the sun in the sky as seen
from your latitude and longitude?

We answer it with the **US Naval Observatory's approximate solar coordinates**: a short set of
formulas giving the sun's declination (how far north or south it sits) and the equation of time
(how far the real sun runs ahead of or behind clock time). The USNO states the accuracy as
about **one arcminute** — roughly a thirtieth of the sun's own width — for any date within two
centuries either side of the year 2000.

In practical terms: the error in your prayer times from the astronomy is a fraction of a second.
Anything that shifts a time by a noticeable amount comes from the *convention* you chose, not
from the arithmetic.

## Step two: what does each prayer mean, as an angle?

Every prayer is a statement about the sun's height, and the sun's height is something the step
above can solve for. Five of the six are read straight off it:

| Prayer | What is actually being calculated |
|---|---|
| **Dhuhr** | The moment the sun crosses your meridian — its highest point of the day. Local noon by the sun, not by the clock. |
| **Sunrise** | The sun's upper edge touching the horizon, taken as **0.833° below** it. |
| **Maghrib** | The same moment at the other end of the day: sunset. |
| **Fajr** | Dawn — the sun a set number of degrees **below** the horizon, still climbing. |
| **Isha** | Nightfall — the same idea, the sun now descending. |
| **Asr** | Not an angle at all. See below. |

**Why 0.833° and not zero.** Two things happen at the horizon. The sun is a disc rather than a
dot, and we count the moment its *edge* appears, which is about 0.267° before its centre would.
And the atmosphere bends light over the horizon, lifting the sun's image roughly 0.567° above
where it geometrically is. Together: 0.833°. This is the standard value, and it is why the sun
is technically already below the horizon at the instant you watch it set.

**Asr is a shadow, not an angle.** The rule is about the length of an object's shadow compared
with the shadow it cast at noon. For most schools, Asr begins when the shadow has grown by *one*
object-length beyond its noon shadow; in the Hanafi school, by *two*. We solve for the moment
the sun's height makes that true, which is why `INZSH_SALAH_ASR=hanafi` moves Asr later.

The definitions we implement are the ones published at
[praytimes.org/calculation](https://praytimes.org/calculation), section by section.

## Step three: whose numbers for Fajr and Isha?

"A set number of degrees below the horizon" — but which number? This is where authorities differ,
and where an honest theme has to let you choose rather than pick for you.

| `INZSH_SALAH_METHOD` | Fajr | Isha |
|---|---|---|
| `MWL` (default) | 18° | 17° |
| `ISNA` | 15° | 15° |
| `UmmAlQura` | 18.5° | **90 minutes after Maghrib** |
| `Egyptian` | 19.5° | 17.5° |
| `Karachi` | 18° | 18° |
| `Algeria` | 18° | 17° |

These are transcribed from [api.aladhan.com/v1/methods](https://api.aladhan.com/v1/methods),
which publishes what each authority states for itself.

Note Umm al-Qura: its Isha is not an angle at all but a **fixed interval after Maghrib**, and
the theme treats that as a first-class case rather than an exception bolted on. Both forms are
equally supported, and setting `INZSH_SALAH_ISHA_INTERVAL` switches any method to the interval
form.

If your local masjid follows angles the theme does not ship, set them directly with
`INZSH_SALAH_FAJR_ANGLE` and `INZSH_SALAH_ISHA_ANGLE` — they win over whatever the named method
said. Nobody should have to wait for a release to pray on time.

## When the sun will not cooperate

Far enough north or south, in summer, the sun never dips 18° below the horizon. There is
genuinely no moment that satisfies the definition — the question has no answer rather than an
answer we failed to find.

`INZSH_SALAH_HIGHLAT` decides what to do:

- **`angle`** (default) — the night is split in proportion to your method's own twilight angle:
  the portion is the angle divided by 60. An 18° Isha therefore takes the last 18/60 of the
  night, and a 15° one takes the last quarter
- **`seventh`** — Isha begins one-seventh of the way through the night, Fajr one-seventh before
  its end
- **`middle`** — the night is halved
- **`none`** — the prayer is simply **absent** from your prompt

That last option exists on purpose. A theme that invented a plausible-looking time would be
lying quietly, and a missing entry is more honest than a wrong one. These conventions are the
ones described under *Higher Latitudes* at
[praytimes.org/calculation](https://praytimes.org/calculation).

## How we know it is right

Two things, beyond reading the code.

**It is checked against someone else's answers.** The test suite pins our output against real
responses from the public [Aladhan API](https://api.aladhan.com/v1/timings) — a separate
implementation by different people — across a matrix of places, dates and methods — Mecca, Cairo, Karachi,
Algiers, New York across a daylight-saving change, Sydney, Cape Town, Buenos Aires, Ushuaia,
Reykjavík under all three high-latitude conventions, and Svalbard in both midnight sun and
polar night. Those expected values were fetched by hand and committed; no test
run regenerates them, so the suite cannot quietly agree with itself.

**The clock is injectable.** The calculation takes the instant as an argument and never reads
the system clock. That is what makes a test for polar night on Svalbard possible at all,
and there is a test that fails if anyone reaches for the real clock inside that file.

## Adjusting to your masjid

Astronomy gives the moment; your community may announce a slightly different one. Rather than
bend the arithmetic, the theme lets you nudge the display:

```zsh
INZSH_SALAH_OFFSET_FAJR=-2      # two minutes earlier
INZSH_SALAH_OFFSET_ISHA=5       # five minutes later
```

Offsets move what is shown and nothing else — nudging Maghrib does not drag an interval-based
Isha along with it, because that would be silently changing a calculation you did not ask to
change.

## The sources, in one place

- **[praytimes.org/calculation](https://praytimes.org/calculation)** — the prayer definitions:
  twilight angles, the 0.833° horizon, the Asr shadow rule, the high-latitude conventions
- **[US Naval Observatory — Computing Approximate Solar
  Coordinates](https://aa.usno.navy.mil/faq/sun_approx)** — the solar position formulas
- **[api.aladhan.com/v1/methods](https://api.aladhan.com/v1/methods)** — each authority's
  published Fajr and Isha parameters
- **[api.aladhan.com/v1/timings](https://api.aladhan.com/v1/timings)** — the independent
  implementation our test oracle is taken from

Every knob mentioned here is documented in the [configuration
reference](configuration.md); what does and does not leave your machine is in
[known limitations, privacy and colour accessibility](limitations.md).
