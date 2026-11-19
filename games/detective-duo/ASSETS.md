# Detective Duo — Meridian cinematic assets

All nine character/environment images were created specifically for Detective Duo using the built-in image generation tool. No stock photography, third-party characters, paid media service, remote font, or remote runtime asset is used. Production files are optimized WebP images under `assets/`; all are bundled in the native app and pre-cached for browser offline play.

Shared direction: original semi-realistic cinematic noir painted realism; midnight navy/charcoal, warm tungsten practical lamps, muted teal rim light, detailed materials, dramatic shadows, consistent Hotel Meridian architecture. No third-party branding or likeness references were supplied.

| Asset | Production brief |
| --- | --- |
| suite.webp | Luxury hotel suite at night; rainy city windows, disturbed cream bed, two teacups, reporter documents, packed luggage, abandoned black telephone. Wide 3:2 view with individually mapped clues. |
| hall.webp | Ninth-floor corridor; brass passenger elevator and display, key reader, linen trolley with rooftop gravel, surveillance camera, service door. Matching navy/brass architecture. |
| security.webp | Surveillance office; CCTV wall, laptop admin audit, open incident log, staff roster, shift radio, unplugged recorder. Tungsten task lighting and teal screens. |
| roof.webp | Rainy service rooftop; skyline, chainlink gate, service door, override panel, torn blue scarf on stair rail, invoice envelope on foreground crate. |
| mara.webp | Original guarded middle-aged hotel manager; auburn bob, ivory blouse, tailored charcoal blazer, restrained brass jewelry. |
| theo.webp | Original young adult Black night bellhop; short natural hair, burgundy uniform with brass piping, earnest anxious expression. |
| iris.webp | Original adult sister of Lena; olive skin, dark wavy hair, teal sweater, charcoal coat, worried but resolute. |
| elias.webp | Original late-forties security contractor; salt-and-pepper cropped hair and stubble, black security jacket, skeptical expression. |
| lena.webp | Original investigative reporter; olive skin, dark wavy hair with family resemblance to Iris, tan trench coat, blue silk scarf. |

Evidence photographs and inspection close-ups crop the actual integrated scene art. The accompanying exhibit text is authoritative for timestamps and narrative facts; incidental text within environment artwork is decorative.

Audio is an original procedural Web Audio score and synthesized Foley/ambience in `audio.js`. A low-volume minor harmonic bed, sparse upper notes, filtered rain/room noise, and distinct collection/document/interview/deduction/verdict cues run entirely on-device. No third-party samples or voice services are used. The iOS audio session uses ambient mixing, respecting the device's silent behavior.

The game retains `detective_duo_v1` saves and validates known clue/location/person IDs before resuming. ResizeObserver fits the same scene coordinate plane to available dimensions; resizing never recreates game state. Expanded and short-landscape layouts expose the caseboard alongside the scene. Hinge-specific positioning is progressive enhancement only; no unverified device model detection is used.
