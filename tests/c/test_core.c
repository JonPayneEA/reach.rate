/* Standalone tests for the evaluation kernel. No R, no Python: this is the
 * check that reach_core.c really depends on the C library alone.
 * Build and run:  make -C tests/c */
#include "../../src/reach_core.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL line %d: %s\n", __LINE__, #cond); failures++; } } while (0)
#define CLOSE(a, b) CHECK(fabs((a) - (b)) <= 1e-12 * (1.0 + fabs(b)))

/* Two limbs that meet in discharge: Q = 2 H^1.5 below 1, then 2 H^1.5 again. */
static const double LOW[2] = {0.5, 1.0}, UP[2] = {1.0, 3.0};
static const double CC[2] = {2.0, 2.0}, AA[2] = {0.0, 0.0}, NN[2] = {1.5, 1.5};
static reach_rating two_limb(void) {
  reach_rating r = {2, LOW, UP, CC, AA, NN};
  return r;
}

static void test_forward(void) {
  reach_rating r = two_limb();
  const double stage[] = {0.2, 0.5, 0.64, 0.999, 1.0, 2.0, 3.0, 3.5, NAN, -1.0, INFINITY};
  const size_t m = sizeof stage / sizeof stage[0];
  double q[11]; int32_t limb[11]; int8_t ex[11];
  CHECK(reach_forward(&r, stage, m, q, limb, ex) == REACH_OK);

  CLOSE(q[2], 2.0 * pow(0.64, 1.5));
  CLOSE(q[4], 2.0);
  CLOSE(q[6], 2.0 * pow(3.0, 1.5));
  /* below the bottom: evaluated with limb 0 and flagged */
  CHECK(limb[0] == 0 && ex[0] == 1);
  CHECK(limb[1] == 0 && ex[1] == 0);         /* the bottom edge is inside */
  CHECK(limb[3] == 0 && ex[3] == 0);
  CHECK(limb[4] == 1 && ex[4] == 0);         /* a junction belongs to the upper limb */
  CHECK(limb[6] == 1 && ex[6] == 0);         /* the top edge is inside */
  CHECK(limb[7] == 1 && ex[7] == 1);         /* above the top */
  CHECK(isnan(q[8]) && limb[8] == -1 && ex[8] == -1);
  CHECK(q[9] == 0.0 && ex[9] == 1);          /* at or below the offset */
  CHECK(isinf(q[10]) && ex[10] == 1);
}

static void test_optional_outputs(void) {
  reach_rating r = two_limb();
  const double stage[] = {0.7};
  double q[1];
  CHECK(reach_forward(&r, stage, 1, q, NULL, NULL) == REACH_OK);
  CHECK(reach_forward(&r, stage, 0, NULL, NULL, NULL) == REACH_OK);
  CHECK(reach_forward(&r, NULL, 0, NULL, NULL, NULL) == REACH_OK);
  CHECK(reach_forward(&r, NULL, 1, q, NULL, NULL) == REACH_ERR_ARG);
}

static void test_offset_and_square(void) {
  /* An offset limb and an exponent of exactly 2, which R computes as x * x */
  const double lo[1] = {1.0}, up[1] = {5.0}, c[1] = {3.0}, a[1] = {0.4}, n[1] = {2.0};
  reach_rating r = {1, lo, up, c, a, n};
  const double stage[] = {0.4, 1.7, 5.0};
  double q[3];
  CHECK(reach_forward(&r, stage, 3, q, NULL, NULL) == REACH_OK);
  CHECK(q[0] == 0.0);
  CHECK(q[1] == 3.0 * ((1.7 - 0.4) * (1.7 - 0.4)));   /* bit-exact, not just close */
  CLOSE(q[2], 3.0 * 4.6 * 4.6);
}

static void test_inverse(void) {
  reach_rating r = two_limb();
  const double stage_in[] = {0.6, 0.9, 1.5, 2.5};
  double q[4], back[4]; int8_t ex[4];
  size_t i;
  CHECK(reach_forward(&r, stage_in, 4, q, NULL, NULL) == REACH_OK);
  CHECK(reach_inverse(&r, q, 4, back, ex) == REACH_OK);
  for (i = 0; i < 4; i++) { CLOSE(back[i], stage_in[i]); CHECK(ex[i] == 0); }

  {
    const double qs[] = {0.0, -1.0, NAN, 0.01, 100.0};
    double s[5]; int8_t e[5];
    CHECK(reach_inverse(&r, qs, 5, s, e) == REACH_OK);
    CHECK(isnan(s[0]) && e[0] == -1);
    CHECK(isnan(s[1]) && e[1] == -1);
    CHECK(isnan(s[2]) && e[2] == -1);
    CHECK(e[3] == 1 && e[4] == 1);          /* outside the discharge range */
    CLOSE(s[4], pow(100.0 / 2.0, 1.0 / 1.5));
  }
}

static void test_inverse_refuses_what_is_not_single_valued(void) {
  const double lo[2] = {0.0, 1.0}, up[2] = {1.0, 2.0}, c[2] = {5.0, 1.0}, a[2] = {0.0, 0.0}, n[2] = {1.0, 1.0};
  reach_rating falling = {2, lo, up, c, a, n};   /* Q(1) = 5 then limb 2 gives 1 .. 2: not increasing */
  const double q[] = {1.0};
  double s[1];
  CHECK(reach_inverse(&falling, q, 1, s, NULL) == REACH_ERR_MONOTONE);
  {
    const double c0[1] = {-1.0}, l1[1] = {0.0}, u1[1] = {1.0}, a1[1] = {0.0}, n1[1] = {1.0};
    reach_rating neg = {1, l1, u1, c0, a1, n1};
    CHECK(reach_inverse(&neg, q, 1, s, NULL) == REACH_ERR_VALUE);
  }
}

static void test_junctions(void) {
  /* A deliberate gap: limb 2 gives 3 where limb 1 gives 2 at stage 1 */
  const double lo[2] = {0.0, 1.0}, up[2] = {1.0, 2.0}, c[2] = {2.0, 3.0}, a[2] = {0.0, 0.0}, n[2] = {1.0, 1.0};
  reach_rating r = {2, lo, up, c, a, n};
  double below[1], above[1];
  CHECK(reach_junctions(&r, below, above) == REACH_OK);
  CLOSE(below[0], 2.0);
  CLOSE(above[0], 3.0);
  {
    reach_rating one = {1, lo, up, c, a, n};
    CHECK(reach_junctions(&one, NULL, NULL) == REACH_OK);   /* nothing to write */
  }
}

static void test_tangent(void) {
  double C, a;
  /* Q = 2.5 H^1.5 at h = 0.2: slope 1.5 * 2.5 * 0.2^0.5, zero at 0.2 - 0.2 / 1.5 */
  CHECK(reach_tangent_limb(2.5, 0.0, 1.5, 0.2, &C, &a) == REACH_OK);
  CLOSE(C, 1.5 * 2.5 * sqrt(0.2));
  CLOSE(a, 0.2 - 0.2 / 1.5);
  /* The line really touches the curve at h and has its gradient */
  CLOSE(C * (0.2 - a), 2.5 * pow(0.2, 1.5));
  CHECK(reach_tangent_limb(2.5, 0.2, 1.5, 0.2, &C, &a) == REACH_ERR_VALUE);    /* h not above a */
  CHECK(reach_tangent_limb(-1.0, 0.0, 1.5, 0.2, &C, &a) == REACH_ERR_VALUE);
  CHECK(reach_tangent_limb(2.5, 0.0, 1.5, NAN, &C, &a) == REACH_ERR_VALUE);
  CHECK(reach_tangent_limb(2.5, 0.0, 1.5, 0.2, NULL, &a) == REACH_ERR_ARG);
}

static void test_rating_check(void) {
  int bad;
  reach_rating good = two_limb();
  CHECK(reach_rating_check(&good, &bad) == REACH_OK && bad == -1);
  {
    const double lo[2] = {0.5, 1.5}, up[2] = {1.0, 3.0};
    reach_rating gap = {2, lo, up, CC, AA, NN};
    CHECK(reach_rating_check(&gap, &bad) == REACH_ERR_ORDER && bad == 0);
  }
  {
    const double lo[2] = {0.5, 1.0}, up[2] = {1.0, 0.8};
    reach_rating backwards = {2, lo, up, CC, AA, NN};
    CHECK(reach_rating_check(&backwards, &bad) == REACH_ERR_ORDER && bad == 1);
  }
  {
    const double c[2] = {2.0, NAN};
    reach_rating nonfinite = {2, LOW, UP, c, AA, NN};
    CHECK(reach_rating_check(&nonfinite, &bad) == REACH_ERR_VALUE && bad == 1);
  }
  {
    reach_rating none = {0, LOW, UP, CC, AA, NN};
    CHECK(reach_rating_check(&none, &bad) == REACH_ERR_ARG);
    CHECK(reach_rating_check(NULL, &bad) == REACH_ERR_ARG);
  }
}


static void test_crossing(void) {
  double root;
  /* 2 H = H^2 meets at H = 2 */
  CHECK(reach_crossing(2.0, 0.0, 1.0, 1.0, 0.0, 2.0, 1.0, 3.0, 1e-12, &root) == REACH_OK);
  CLOSE(root, 2.0);
  /* An offset pair: 3 (H - 0.5)^1.5 = 2 (H + 0.2)^1.2 somewhere in 1..5 */
  CHECK(reach_crossing(3.0, 0.5, 1.5, 2.0, -0.2, 1.2, 1.0, 5.0, 1e-12, &root) == REACH_OK);
  CHECK(fabs(3.0 * pow(root - 0.5, 1.5) - 2.0 * pow(root + 0.2, 1.2)) < 1e-9);
  /* A crossing exactly at an end is that end, from either side */
  CHECK(reach_crossing(2.0, 0.0, 1.0, 1.0, 0.0, 2.0, 2.0, 3.0, 1e-12, &root) == REACH_OK && root == 2.0);
  CHECK(reach_crossing(2.0, 0.0, 1.0, 1.0, 0.0, 2.0, 1.0, 2.0, 1e-12, &root) == REACH_OK && root == 2.0);
  /* No change of order in the range, or a non-finite value */
  CHECK(reach_crossing(2.0, 0.0, 1.0, 1.0, 0.0, 2.0, 2.5, 3.0, 1e-12, &root) == REACH_NO_CROSSING);
  CHECK(reach_crossing(2.0, 0.0, 1.5, 1.0, 5.0, 1.5, 1.0, 3.0, 1e-12, &root) == REACH_NO_CROSSING); /* (H-5)^1.5 is NaN */
  /* Bad input */
  CHECK(reach_crossing(2.0, 0.0, 1.0, 1.0, 0.0, 2.0, 3.0, 1.0, 1e-12, &root) == REACH_ERR_ORDER);
  CHECK(reach_crossing(2.0, 0.0, 1.0, 1.0, 0.0, 2.0, 1.0, 1.0, 1e-12, &root) == REACH_ERR_ORDER);
  CHECK(reach_crossing(NAN, 0.0, 1.0, 1.0, 0.0, 2.0, 1.0, 3.0, 1e-12, &root) == REACH_ERR_VALUE);
  CHECK(reach_crossing(2.0, 0.0, 1.0, 1.0, 0.0, 2.0, 1.0, 3.0, 0.0, &root) == REACH_ERR_VALUE);
  CHECK(reach_crossing(2.0, 0.0, 1.0, 1.0, 0.0, 2.0, 1.0, 3.0, 1e-12, NULL) == REACH_ERR_ARG);
  /* A steep pair: the two curves agree to rounding at the root found */
  CHECK(reach_crossing(0.3128, 0.0, 4.095, 2.831, -0.886, 1.935, 3.41, 6.0, 1.4901161193847656e-08, &root) == REACH_OK);
  CHECK(fabs(0.3128 * pow(root, 4.095) - 2.831 * pow(root + 0.886, 1.935)) < 1e-6 * 0.3128 * pow(root, 4.095));
}

static void test_xs_geometry(void) {
  /* A trapezoid: walls rise 3 over 1 on each side, flat bed 8 wide */
  const double x[4] = {0.0, 1.0, 9.0, 10.0}, z[4] = {3.0, 0.0, 0.0, 3.0};
  const double stage[] = {-1.0, 0.0, 2.0, 3.0, 5.0, NAN};
  double area[6], perim[6];
  CHECK(reach_xs_geometry(x, z, 4, stage, 6, area, perim) == REACH_OK);
  CLOSE(area[0], 0.0); CLOSE(perim[0], 0.0);            /* below the bed */
  CLOSE(area[1], 0.0); CLOSE(perim[1], 0.0);            /* at the bed: nothing wet */
  /* depth 2: area d (8 + d/3), perimeter 8 + 2 sqrt((d/3)^2 + d^2) */
  CLOSE(area[2], 2.0 * (8.0 + 2.0 / 3.0));
  CLOSE(perim[2], 8.0 + 2.0 * sqrt((2.0 / 3.0) * (2.0 / 3.0) + 4.0));
  /* depth 3 is exactly bank full: the whole trapezoid, no free surface */
  CLOSE(area[3], 3.0 * (8.0 + 1.0));
  CLOSE(perim[3], 8.0 + 2.0 * sqrt(1.0 + 9.0));
  /* above every point: the section is not extended upwards */
  /* stage 5, above every point: segments give 3.5 + 40 + 3.5, and the
   * perimeter is the 8 m bed plus two walls of length sqrt(10) */
  CLOSE(area[4], 47.0);
  CLOSE(perim[4], 8.0 + 2.0 * sqrt(10.0));
  CHECK(isnan(area[5]) && isnan(perim[5]));
  CHECK(reach_xs_geometry(x, z, 4, stage, 6, NULL, NULL) == REACH_OK);
  CHECK(reach_xs_geometry(x, z, 4, NULL, 0, area, perim) == REACH_OK);
}

static void test_xs_geometry_errors(void) {
  const double x[3] = {0.0, 1.0, 2.0}, z[3] = {1.0, 0.0, 1.0}, h[1] = {0.5};
  const double bad_x[3] = {0.0, 1.0, 1.0}, nan_z[3] = {1.0, NAN, 1.0};
  double area[1];
  CHECK(reach_xs_geometry(x, z, 1, h, 1, area, NULL) == REACH_ERR_ARG);
  CHECK(reach_xs_geometry(NULL, z, 3, h, 1, area, NULL) == REACH_ERR_ARG);
  CHECK(reach_xs_geometry(x, z, 3, NULL, 1, area, NULL) == REACH_ERR_ARG);
  CHECK(reach_xs_geometry(bad_x, z, 3, h, 1, area, NULL) == REACH_ERR_ORDER);
  CHECK(reach_xs_geometry(x, nan_z, 3, h, 1, area, NULL) == REACH_ERR_VALUE);
}

static void test_manning(void) {
  const double area[] = {10.0, 0.0, 4.0, NAN}, perim[] = {8.0, 0.0, 0.0, 1.0};
  double q[4];
  CHECK(reach_manning(area, perim, 4, 0.03, 0.001, q) == REACH_OK);
  CLOSE(q[0], (1.0 / 0.03) * 10.0 * pow(1.25, 2.0 / 3.0) * sqrt(0.001));
  CHECK(q[1] == 0.0);
  CHECK(q[2] == 0.0);                    /* no wetted perimeter: radius 0 */
  CHECK(isnan(q[3]));
  CHECK(reach_manning(area, perim, 4, 0.0, 0.001, q) == REACH_ERR_VALUE);
  CHECK(reach_manning(area, perim, 4, 0.03, -1.0, q) == REACH_ERR_VALUE);
  CHECK(reach_manning(area, perim, 4, NAN, 0.001, q) == REACH_ERR_VALUE);
  CHECK(reach_manning(area, perim, 4, 0.03, 0.0, q) == REACH_OK && q[0] == 0.0);
  CHECK(reach_manning(NULL, perim, 4, 0.03, 0.001, q) == REACH_ERR_ARG);
}

static void test_version(void) {
  CHECK(reach_abi_version() == REACH_ABI_VERSION);
  CHECK(strlen(reach_version()) > 0);
}

int main(void) {
  test_forward();
  test_optional_outputs();
  test_offset_and_square();
  test_inverse();
  test_inverse_refuses_what_is_not_single_valued();
  test_junctions();
  test_tangent();
  test_rating_check();
  test_crossing();
  test_xs_geometry();
  test_xs_geometry_errors();
  test_manning();
  test_version();
  if (failures) { printf("%d check(s) failed\n", failures); return 1; }
  printf("reach_core: all checks passed\n");
  return 0;
}
