# Roadmap

Ideas for future work that aren't scheduled yet, kept here so they're visible
alongside the code rather than only in the issue tracker.

## Temporal weighting and seasonality in rating fits

Ratings are currently fitted from spot gaugings with no notion of *when* each
gauging was taken. Three related ideas would change that:

- **[#9](https://github.com/JonPayneEA/reach.rate/issues/9) — Age-weighted NLS fitting that protects extreme events.**
  Down-weight old spot gaugings in `rate_optimise()`/`rate_optimise_constrained()`
  so the fit reflects current channel geometry, without discounting large,
  rare discharge events just because they're old.

- **[#10](https://github.com/JonPayneEA/reach.rate/issues/10) — Seasonal/temporal covariates in rating fits.**
  Let a rating account for seasonal shifts (vegetation, ice, sediment) rather
  than assuming one stable stage-discharge relationship year-round. Least
  defined of the three; needs a design spike before implementation.

- **[#11](https://github.com/JonPayneEA/reach.rate/issues/11) — Bayesian alternative to the current NLS fitting approach.**
  A `rate_optimise_bayesian()`-style function giving a full posterior over the
  rating coefficients instead of a bootstrap approximation, with priors that
  can encode known hydraulic constraints. Largest lift of the three.

None of these are implemented yet — see the linked issues for the technical
detail, open design questions, and relevant code pointers.
