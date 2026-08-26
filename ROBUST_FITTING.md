# Robust fitting: plain-English notes

This is a companion explainer for three ideas about how `reach.rate` fits
rating curves, tracked as issues ([#9](https://github.com/JonPayneEA/reach.rate/issues/9),
[#13](https://github.com/JonPayneEA/reach.rate/issues/13),
[#14](https://github.com/JonPayneEA/reach.rate/issues/14)) on the
[roadmap](ROADMAP.md) — written for anyone who isn't already familiar with
these statistical methods.

**Two of the three are now real, working options.** `objective` (Idea 2) and
`n_bounds` (Idea 3) are opt-in arguments on `rate_optimise()` and friends
today. The third, age-weighting (Idea 1), is still a future idea.

**All of it stays opt-in.** Leaving these arguments out of a call reproduces
today's default fitting behaviour exactly — nothing described here changes
what you get unless you deliberately ask for it.

## The problem, in plain terms

Every spot gauging that goes into a rating fit doesn't automatically count
equally in the way you might want. Two separate issues show up in practice:

1. **Age.** A measurement from twenty years ago pulls just as hard on the
   fitted curve as one from last week, by default. That's fine if the
   channel hasn't changed, but real channels do change: the bed shifts,
   vegetation grows, sediment moves. Old gaugings can end up describing a
   channel that no longer exists. The obvious fix — "just trust recent data
   more" — has a sting in its tail: the biggest floods are also the rarest,
   so a lot of your best evidence about extreme flows is *necessarily* old.
   If you down-weight everything old, you also down-weight the flood record
   you can least afford to lose, right when it matters most (extrapolating
   up to a design flood, for instance).
2. **Error structure and extrapolation.** By default the fit tries to
   minimise absolute discharge error and estimates the curve's shape purely
   from whatever data happens to be available — including at the top end,
   where floods are rare and data is thin. Ideas 2 and 3 below each fix a
   different part of that.

## Available now: fit on percentage error instead of absolute error (#13)

**What it does:** changes what "best fit" means. By default, the fit tries
to minimise the *absolute* size of the errors (in cubic metres per second).
Setting `objective = "relative"` instead minimises the *percentage* size of
the errors.

**Why that matters:** flow gauging error is naturally proportional — a
measurement is typically accurate to within a few percent, whether the flow
is a trickle or a torrent, not accurate to within a few cubic metres per
second regardless of size. Fitting on absolute error means big flows
automatically matter more to the fit just because their errors are bigger in
absolute terms, which can crowd out the low-flow part of the curve. Fitting
on percentage error puts low flows and high flows on a fairer footing.

**Analogy:** being off by 1 m3/s matters a lot if the true flow is 2 m3/s,
and barely matters if the true flow is 2,000 m3/s. Absolute-error fitting
treats both misses the same; percentage-error fitting treats them
proportionally, which is closer to how gauging accuracy actually works.

**How to use it:**

```r
rate_optimise(discharge_cms, stage_m, objective = "relative")
```

The reported fit-quality numbers (`rmse_cms`, `r_squared`) are always shown
in the normal cms units regardless of which objective you pick, so you can
compare a `"relative"` fit against an `"absolute"` one on equal terms.
Leaving `objective` out defaults to `"absolute"` — today's behaviour,
unchanged.

## Available now: let known channel shape constrain the curve's top end (#14)

**What it does:** the top end of a rating curve — the part covering the
biggest floods — is usually where you have the least data, because big
floods are rare. But hydraulics gives us theory about how a curve *should*
behave at the top, based on the physical shape of the channel or floodplain
at high stage (rectangular, triangular, etc. each imply a particular curve
steepness, roughly 1.5 for rectangular, 2.5 for triangular). Setting
`n_bounds` lets that theoretical knowledge constrain the fit, instead of
leaving the top end of the curve to be guessed purely from whatever scarce
data happens to be there.

**Analogy:** it's like knowing the shape of a glass before you've finished
pouring water into it. Even with only a partial fill, you can predict how
the water level will rise as you keep pouring, because the glass's shape
constrains the possibilities. Here, known channel geometry plays the same
role — it rules out physically implausible curve shapes even where gauging
data can't.

**How to use it:**

```r
# Keep the exponent within a plausible range for a roughly rectangular
# channel control:
rate_optimise(discharge_cms, stage_m, n_bounds = c(1.4, 1.7))

# Or fix it outright if you're confident in the theoretical value:
rate_optimise(discharge_cms, stage_m, n_bounds = c(1.5, 1.5))
```

`rate_optimise_constrained()` honours the same bound for every limb it
refits, not just the one it leaves alone, so the constraint holds across a
whole multi-limb rating.

**A note on the name:** this was originally floated as a "Bayesian"
technique, but as built it's really a constraint on the fit (a bound on one
of the equation's parameters), not a true Bayesian method. A true Bayesian
version — where the theoretical value acts as a starting assumption that
real data can still override, given enough of it — is tracked separately
under the (larger, not-yet-started) Bayesian fitting idea,
[#11](https://github.com/JonPayneEA/reach.rate/issues/11).

## Still on the roadmap: weight gaugings by age and by size (#9)

**What it would do:** each gauging would get a weight when the curve is
fitted. Newer gaugings would get a bigger weight; older ones a smaller one —
a standard "age decay," similar to how a moving average leans on recent
data. That decay would then combine with a second weight based on how big
the flow was: a big, rare flood keeps a high weight almost regardless of
age, because its size matters more to the fit than its age does.

**Analogy:** think of it like a jury weighing witness testimony. A
witness's account naturally carries less weight the longer ago the event
was — memory fades, context shifts. But if a witness describes something
dramatic and distinctive (a landmark event), you don't discount their
account just because time has passed — the significance of what they saw
earns it back its weight.

**Why it's the harder one to get right:** the age-decay part is
straightforward, but the "how big counts" part needs care. If you're not
careful, one enormous historic flood can end up dominating the whole fit —
the opposite failure to the one you started with.

**What's already in place for it:** this idea needed the package to start
recording *when* each gauging was taken, which it didn't before. That part
is now done — `rate_optimise()`/`rate_optimise_segmented()` accept a
`gauging_datetime` argument (a `Date` or `POSIXct` vector, one entry per
gauging), stored on the fitted rating alongside the discharge and stage
values. Nothing reads or acts on it yet; it's there so the weighting math,
once designed, has real dates to work with rather than needing its own
follow-up data-model change first.

## What's done, what's next

- **Done:** percentage-error fitting (`objective = "relative"`, #13),
  hydraulic bounds on the exponent (`n_bounds`, #14), and the
  `gauging_datetime` groundwork #9 needs.
- **Next:** the actual age/magnitude weighting math for #9 — see the issue
  for the open design questions (decay shape, how "extreme" is defined,
  per-limb vs. whole-record weighting).
