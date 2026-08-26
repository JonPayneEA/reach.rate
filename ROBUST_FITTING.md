# Robust fitting: plain-English notes

These are not features of `reach.rate` yet. This is a companion explainer for
three ideas tracked as issues ([#9](https://github.com/JonPayneEA/reach.rate/issues/9),
[#13](https://github.com/JonPayneEA/reach.rate/issues/13),
[#14](https://github.com/JonPayneEA/reach.rate/issues/14)) on the
[roadmap](ROADMAP.md) — written for anyone who isn't already familiar with
these statistical methods, since we don't use any of them in the package
today.

**If and when any of these are implemented, they will be opt-in arguments,
not new defaults.** `rate_optimise()` will keep fitting the way it does now
unless you deliberately ask for one of these.

## The problem, in plain terms

Right now, every spot gauging that goes into a rating fit counts equally —
a measurement from twenty years ago pulls just as hard on the fitted curve
as one from last week. That's fine if the channel hasn't changed, but real
channels do change: the bed shifts, vegetation grows, sediment moves. Old
gaugings can end up describing a channel that no longer exists.

The obvious fix — "just trust recent data more" — has a sting in its tail.
The biggest floods are also the rarest, so a lot of your best evidence about
extreme flows is *necessarily* old. If you down-weight everything old, you
also down-weight the flood record you can least afford to lose, right when
it matters most (extrapolating up to a design flood, for instance). So any
fix needs two properties at once: trust recent data more for the everyday
part of the curve, but don't let a genuinely large old flood get quietly
discounted.

## Idea 1 — Weight gaugings by age and by size (#9)

**What it does:** each gauging gets a weight when the curve is fitted.
Newer gaugings get a bigger weight; older ones get a smaller one — a
standard "age decay," similar to how a moving average leans on recent data.
But that decay is then combined with a second weight based on how big the
flow was: a big, rare flood keeps a high weight almost regardless of age,
because its size matters more to the fit than its age does.

**Analogy:** think of it like a jury weighing witness testimony. A witness's
account naturally carries less weight the longer ago the event was — memory
fades, context shifts. But if a witness describes something dramatic and
distinctive (a landmark event), you don't discount their account just
because time has passed — the significance of what they saw earns it back
its weight.

**Why it's the harder one to get right:** the age-decay part is
straightforward, but the "how big counts" part needs care. If you're not
careful, one enormous historic flood can end up dominating the whole fit —
the opposite failure to the one you started with. It also needs the
package to start recording *when* each gauging was taken, which it doesn't
today.

## Idea 2 — Fit on percentage error instead of absolute error (#13)

**What it does:** changes what "best fit" means. Today, the fit tries to
minimise the *absolute* size of the errors (in cubic metres per second).
This option instead minimises the *percentage* size of the errors.

**Why that matters:** flow gauging error is naturally proportional — a
measurement is typically accurate to within a few percent, whether the flow
is a trickle or a torrent, not accurate to within a few cubic metres per
second regardless of size. Fitting on absolute error means big flows
automatically matter more to the fit just because their errors are bigger
in absolute terms, which can crowd out the low-flow part of the curve.
Fitting on percentage error puts low flows and high flows on a fairer
footing.

**Analogy:** being off by 1 m3/s matters a lot if the true flow is 2 m3/s,
and barely matters if the true flow is 2,000 m3/s. Absolute-error fitting
treats both misses the same; percentage-error fitting treats them
proportionally, which is closer to how gauging accuracy actually works.

**Why it's a good early candidate:** it's a genuinely separate improvement
from the age-weighting idea above — it doesn't need gauging dates, and it
addresses a real mismatch between how the package fits curves today and how
gauging error actually behaves. It's also a small, mechanical change to
make.

## Idea 3 — Let known channel shape constrain the curve's top end (#14)

**What it does:** the top end of a rating curve — the part covering the
biggest floods — is usually where you have the least data, because big
floods are rare. But hydraulics gives us theory about how a curve *should*
behave at the top, based on the physical shape of the channel or floodplain
at high stage (rectangular, triangular, etc. each imply a particular curve
steepness). This idea lets that theoretical knowledge constrain the fit,
instead of leaving the top end of the curve to be guessed purely from
whatever scarce data happens to be there.

**Analogy:** it's like knowing the shape of a glass before you've finished
pouring water into it. Even with only a partial fill, you can predict how
the water level will rise as you keep pouring, because the glass's shape
constrains the possibilities. Here, known channel geometry plays the same
role — it rules out physically implausible curve shapes even where gauging
data can't.

**A note on the name:** this was originally floated as a "Bayesian"
technique, but as scoped it's really a constraint on the fit (a hard limit
or bound on one of the equation's parameters), not a true Bayesian method.
A true Bayesian version — where the theoretical value acts as a starting
assumption that real data can still override, given enough of it — is
tracked separately under the (larger, not-yet-started) Bayesian fitting
idea, [#11](https://github.com/JonPayneEA/reach.rate/issues/11).

## Suggested order

Ideas 2 and 3 are judged the better first steps: they're cheaper to build,
lower-risk, and more directly protect the extreme end of the curve than
age-weighting does. Idea 1 (age-weighting) is left as the harder,
second-phase piece — see the linked issues for the technical detail behind
each.
