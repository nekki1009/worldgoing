# Weather audio — sources, licenses and modifications

Prepared for Worldgoing, CC-20261116-195, 2026-11-16. These seven files are audio assets only: Godot native import, SiteClimate/TC5 triggers, final mix and Nekki device listening have **not** been accepted. No endorsement by the source authors is implied.

## Rain (CC0 1.0)

**Ylmir**, **Rain (loopable)**, [original publication](https://opengameart.org/content/rain-loopable), [original Rain OGG.zip](https://opengameart.org/sites/default/files/Rain%20OGG.zip), [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/), [legal code](https://creativecommons.org/publicdomain/zero/1.0/legalcode).

The author describes mono window rain recordings processed to stereo, published as Ogg Vorbis160kbps. These are the author's published files, **not a lossless recording master**. We use the Ogg version directly, not the webpage's MP3 preview.

- `weather_rain_light_loop.wav`: archive `4.ogg`, original5–26s; downmix to mono; 1s equal-power cyclic tail/head overlap,20s output; RMS/peak gain normalization; low-delta cyclic rotation, final2PCM samples aligned to the first (at most1LSB correction); WAV44100Hz PCM16.
- `weather_rain_heavy_loop.wav`: archive `2.ogg`, original2–23s; same downmix/cyclic/normalization/PCM process,20s output. A different original rain take from the light loop; not merely a louder copy.
- `weather_storm_loop.wav` rain layer: archive `1.ogg`, original3–24s; mixed with the CC0 wind described below.20s cyclic rain/wind composite; **no embedded thunder**, allowing the weather owner to schedule separate thunder cues.

## Wind and storm wind layer (CC0 1.0)

**Luke.RUSTLTD**, **wind1**, [original publication](https://opengameart.org/content/wind1), [original wind1.wav](https://opengameart.org/sites/default/files/wind1.wav), [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/), [legal code](https://creativecommons.org/publicdomain/zero/1.0/legalcode). The author made synthesized wind in PureData and credits **Andy Farnell** for the tutorial. This is **synthesized wind, not an outdoor field recording**.

- `weather_wind_loop.wav`: original5–26s; mono retained; 1s equal-power cyclic tail/head overlap to20s; RMS/peak gain; low-delta cyclic rotation and sample seam alignment; WAV44100Hz PCM16.
- `weather_storm_loop.wav` wind layer: original12–33s, the same cyclic preparation; mixed with Ylmir's `1.ogg`, gain-normalized with peak headroom,20s mono PCM16. Synthesized wind plus recorded rain is a designed strong-wind/rain ambience, not a claim of a recorded typhoon.

## Thunder (CC BY 3.0 Unported — attribution required)

**Jerimee**, **Thunder / thunder-seq.wav**, [original publication](https://opengameart.org/content/thunder), [original thunder-seq.wav](https://opengameart.org/sites/default/files/thunder-seq.wav), [CC BY 3.0 Unported](https://creativecommons.org/licenses/by/3.0/), [legal code](https://creativecommons.org/licenses/by/3.0/legalcode).

Original creator provenance: the publication says it was made using **René Nyffenegger's cSound thunder instrument**, with minor modifications: [instrument reference supplied by the author](http://www.adp-gmbh.ch/csound/fm/thunder.html). These are **synthesized thunder cues**, not field recordings at measured distances.

The following adaptations by **Worldgoing audio preparation** remain distributed under **CC BY 3.0 Unported**. Keep this title/creator/source/license/modification attribution with distributed copies; do not impose additional restrictions on these licensed audio files or imply author endorsement.

- `weather_thunder_01.wav`: original19.8–26.8s,7s output; stereo arithmetic mean to mono, smooth1200Hz spectral low-pass for a muffled distant-style roll;20ms onset/350ms tail fades; RMS/peak normalization;44100Hz PCM16.
- `weather_thunder_02.wav`: original0.6–7.6s,7s output; mono mean, original bandwidth for a sharper near-style clap;20ms onset/350ms tail fades; RMS/peak normalization;44100Hz PCM16.
- `weather_thunder_03.wav`: original34.3–42.3s,8s output; mono mean, smooth3500Hz spectral low-pass for a rolling middle-distance-style cue;20ms onset/350ms tail fades; RMS/peak normalization;44100Hz PCM16.

Distance labels describe editing intent, not verified physical recording distances. Subjective near/far character is for Nekki to assess. Attribution applies to these thunder adaptations only; it does not relicense unrelated existing assets.

## Evidence and integration boundary

Original files/archive, public source-page HTML, CC0/CC BY deeds and legal-code HTML, download URLs/UTC timestamps/hashes, exact extraction/gain/seam processing and PCM readback metrics are retained in `output/project_command_center/evidence/CC-20261116-195/`. `AUDIO_METRICS.json` records each final file's SHA256, frames, duration, sample rate/channels, peak/RMS, gain and loop seam measurements. Existing catalog sound entries and previous attribution sources are preserved; the derived active-file count advances68→75 and seven weather sound entries are appended.

No Godot was run and no `.wav.import` sidecars or generated cache were created by this task. The integrator must perform native import and the weather-trigger/device checks separately. Loop seams have crossfade/PCM continuity checks, not a claim of subjective listening approval. Only these source files and licenses were used; rejected alternate downloads were not mixed into the formal audio.
