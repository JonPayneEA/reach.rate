# Roadmap

Ideas for future work that aren't scheduled yet, kept here so they're visible
alongside the code rather than only in the issue tracker.

## Temporal weighting and seasonality in rating fits

Ratings are currently fitted from spot gaugings with no notion of *when* each
gauging was taken. Related ideas would change that — see
[ROBUST_FITTING.md](ROBUST_FITTING.md) for a plain-English explainer of the
weighting/fitting ideas (#9, #13, #14) before diving into the issues:

- **[#9](https://github.com/JonPayneEA/reach.rate/issues/9) — Age-weighted NLS fitting that protects extreme events.**
  Down-weight old spot gaugings in `rate_optimise()`/`rate_optimise_constrained()`
  so the fit reflects current channel geometry, without discounting large,
  rare discharge events just because they're old. The harder, second-phase
  piece of this group — see #13 and #14 for cheaper wins first.

- **[#13](https://github.com/JonPayneEA/reach.rate/issues/13) — Log-space (relative-error) fitting option.**
  Fit on percentage error instead of absolute error, matching how gauging
  measurement uncertainty actually behaves. Independent of age-weighting;
  a good, low-risk first step.

- **[#14](https://github.com/JonPayneEA/reach.rate/issues/14) — Hydraulic-informed bounds on the `B` exponent.**
  Let known channel-control theory constrain the top of the curve, where
  gauging data is sparsest. A constrained-NLS feature, not a Bayesian one —
  see #11 for the true Bayesian-prior version of this idea.

- **[#10](https://github.com/JonPayneEA/reach.rate/issues/10) — Seasonal/temporal covariates in rating fits.**
  Let a rating account for seasonal shifts (vegetation, ice, sediment) rather
  than assuming one stable stage-discharge relationship year-round. Least
  defined of the group; needs a design spike before implementation.

- **[#11](https://github.com/JonPayneEA/reach.rate/issues/11) — Bayesian alternative to the current NLS fitting approach.**
  A `rate_optimise_bayesian()`-style function giving a full posterior over the
  rating coefficients instead of a bootstrap approximation, with priors that
  can encode known hydraulic constraints. Largest lift of the group.

None of these are implemented yet, and none would become defaults if they
are — see the linked issues for the technical detail, open design questions,
and relevant code pointers.
