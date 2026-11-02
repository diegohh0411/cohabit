#!/usr/bin/env python3
"""Generates the test fixtures for cohabit_analysis.

Usage (from packages/cohabit_analysis):

    python3 -m venv /tmp/venv && /tmp/venv/bin/pip install -r tool/requirements.txt
    /tmp/venv/bin/python tool/generate_fixtures.py            # rewrite fixtures
    /tmp/venv/bin/python tool/generate_fixtures.py --check    # compare only

The Dart tests read the committed JSON in test/fixtures; CI never runs this
script. The expected values are computed here with NumPy, SciPy and
scikit-learn, written independently of the Dart code from the definitions in
docs/SPEC.md ("Analysis"):

  * unadjusted phi:   sklearn.metrics.matthews_corrcoef
  * day-of-week adjustment: residuals of an sklearn LinearRegression on
    one-hot weekday indicators; adjusted phi is their Pearson correlation
    (scipy.stats.pearsonr), i.e. the partial correlation given the weekday
  * p-value:          scipy.stats.t.sf with effective degrees of freedom
  * confidence level: scipy.stats.norm.ppf (Fisher z interval)
  * FDR:              scipy.stats.false_discovery_control(method='bh')

Everything is seeded (numpy RandomState), so the output is deterministic for
given library versions; versions are recorded in the files.
"""
import argparse
import json
import math
import os
import sys
import warnings

import numpy as np
import scipy
import sklearn
from scipy import special, stats
from sklearn.linear_model import LinearRegression
from sklearn.metrics import matthews_corrcoef
from sklearn.preprocessing import OneHotEncoder

warnings.filterwarnings("ignore", category=RuntimeWarning, module="sklearn")

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "test", "fixtures")

CONFIG = dict(
    min_overlap_days=30,
    lags=[1, 2, 3],
    fdr=0.05,
    confidence=0.95,
    min_abs_phi=0.1,
    min_expected_cell=5.0,
    max_autocorr_lag=14,
    min_autocorr_pairs=10,
)
EPS = 1e-9
LAG_SEED = 100
# 2026-10-05, a Monday, as days since 1970-01-01.
START_EPOCH_DAY = 20731


def weekdays_for(start, length):
    # 1970-01-01 was a Thursday; Monday is 1.
    return np.array([(start + j + 3) % 7 + 1 for j in range(length)])


# --------------------------------------------------------------------------
# The statistics, from the definitions in docs/SPEC.md
# --------------------------------------------------------------------------


def mantel_haenszel(x, y, wd):
    """Mantel-Haenszel risk ratio of y=1 given x=1, by weekday, with the
    Greenland-Robins variance of its log. Returns (ratio, var_ln) or None."""
    r = s = v = 0.0
    for w in range(1, 8):
        m = wd == w
        total = int(m.sum())
        if total == 0:
            continue
        xs, ys = x[m], y[m]
        a = float(((xs == 1) & (ys == 1)).sum())
        b = float(((xs == 1) & (ys == 0)).sum())
        c = float(((xs == 0) & (ys == 1)).sum())
        d = float(((xs == 0) & (ys == 0)).sum())
        r += a * (c + d) / total
        s += c * (a + b) / total
        v += ((a + b) * (c + d) * (a + c) - a * c * total) / (total * total)
    if r <= 0 or s <= 0:
        return None
    return r / s, v / (r * s)


def pair_stats(x, y, wd, cfg):
    x, y, wd = np.asarray(x), np.asarray(y), np.asarray(wd)
    mask = (x >= 0) & (y >= 0)
    n = int(mask.sum())
    if n < cfg["min_overlap_days"]:
        return dict(status="tooFewDays", n=n)
    xs, ys, ws = x[mask], y[mask], wd[mask]
    pos = np.flatnonzero(mask)

    n1, n0 = int((xs == 1).sum()), int((xs == 0).sum())
    m1, m0 = int((ys == 1).sum()), int((ys == 0).sum())
    raw_phi = None
    if min(n1, n0, m1, m0) > 0:
        raw_phi = float(matthews_corrcoef(xs, ys))

    onehot = OneHotEncoder(sparse_output=False).fit_transform(ws.reshape(-1, 1))
    # One indicator per weekday and no separate intercept (they would be
    # collinear); the fit values are each weekday's mean.
    rx = xs - LinearRegression(fit_intercept=False).fit(onehot, xs).predict(onehot)
    ry = ys - LinearRegression(fit_intercept=False).fit(onehot, ys).predict(onehot)
    for w in np.unique(ws):
        # Guards against the spurious floating-point warnings some BLAS builds
        # (Apple Accelerate) raise from matmul: each weekday must sum to zero.
        assert abs(rx[ws == w].sum()) < 1e-9 and abs(ry[ws == w].sum()) < 1e-9
    sxx, syy = float((rx**2).sum()), float((ry**2).sum())
    if sxx < EPS or syy < EPS:
        return dict(status="constant", n=n, rawPhi=raw_phi)

    phi = float(stats.pearsonr(rx, ry)[0])
    phi = max(-1.0, min(1.0, phi))
    mh = mantel_haenszel(xs, ys, ws)

    min_expected = min(n1, n0) * min(m1, m0) / n
    if min_expected < cfg["min_expected_cell"]:
        return dict(status="sparse", n=n, rawPhi=raw_phi, phi=phi)

    length = len(x)
    full_rx, full_ry = np.zeros(length), np.zeros(length)
    full_rx[pos], full_ry[pos] = rx, ry
    present = mask
    cross = 0.0
    for h in range(1, min(cfg["max_autocorr_lag"], n // 4) + 1):
        valid = present[:-h] & present[h:]
        pairs = int(valid.sum())
        if pairs < cfg["min_autocorr_pairs"]:
            continue
        px = float((full_rx[:-h] * full_rx[h:])[valid].sum())
        py = float((full_ry[:-h] * full_ry[h:])[valid].sum())
        rho_x = (px / pairs) / (sxx / n)
        rho_y = (py / pairs) / (syy / n)
        cross += max(-1.0, min(1.0, rho_x)) * max(-1.0, min(1.0, rho_y))
    deff = max(1.0, 1 + 2 * cross)
    n_eff = n / deff

    controls = len(np.unique(ws)) - 1
    df = n_eff - 2 - controls
    z = float(stats.norm.ppf(1 - (1 - cfg["confidence"]) / 2))
    if df < 1:
        p, low, high = 1.0, -1.0, 1.0
    else:
        t = math.inf if abs(phi) >= 1 else phi * math.sqrt(df / (1 - phi * phi))
        p = float(2 * stats.t.sf(abs(t), df))
        if n_eff - 3 - controls > 0 and abs(phi) < 1:
            se = 1 / math.sqrt(n_eff - 3 - controls)
            low = float(np.tanh(np.arctanh(phi) - z * se))
            high = float(np.tanh(np.arctanh(phi) + z * se))
        else:
            low, high = -1.0, 1.0

    ratio = r_low = r_high = None
    if mh is not None:
        ratio = mh[0]
        if mh[1] > 0:
            se = math.sqrt(mh[1] * deff)
            r_low = math.exp(math.log(ratio) - z * se)
            r_high = math.exp(math.log(ratio) + z * se)
    return dict(
        status="tested", n=n, rawPhi=raw_phi, phi=phi, phiLow=low, phiHigh=high,
        nEff=n_eff, p=p, ratio=ratio, ratioLow=r_low, ratioHigh=r_high,
    )


def analyze(start, series, cfg):
    length = len(series[0]["values"])
    wd = weekdays_for(start, length)
    rows = []

    def add(i, k, lag):
        span = length - lag
        x = np.array(series[i]["values"][:span])
        y = np.array(series[k]["values"][lag:])
        rows.append(dict(
            fromId=series[i]["id"], toId=series[k]["id"], lag=lag,
            **pair_stats(x, y, wd[:span], cfg)))

    for i in range(len(series)):
        for k in range(i + 1, len(series)):
            add(i, k, 0)
    for lag in cfg["lags"]:
        for i in range(len(series)):
            for k in range(len(series)):
                if i != k:
                    add(i, k, lag)

    tested = [r for r in rows if r["status"] == "tested"]
    if tested:
        q = stats.false_discovery_control([r["p"] for r in tested], method="bh")
        for r, qv in zip(tested, q):
            r["q"] = float(qv)
    for r in rows:
        r["isInsight"] = bool(
            r.get("q") is not None and r["q"] <= cfg["fdr"]
            and abs(r["phi"]) >= cfg["min_abs_phi"])
    return dict(
        testsRun=len(tested),
        maxOverlap=max(r["n"] for r in rows) if rows else 0,
        pairs=rows)


# --------------------------------------------------------------------------
# Deterministic datasets
# --------------------------------------------------------------------------


def streaky(rs, days, habits, start, loadings, base, momentum, weekday_fx, noise=1.0):
    """Binary habits sharing an AR(1) latent mood, with momentum and weekday
    effects. `habits` is the count."""
    wd = weekdays_for(start, days)
    z = np.zeros(days)
    for t in range(1, days):
        z[t] = 0.7 * z[t - 1] + rs.normal(0, 0.7)
    out = []
    for h in range(habits):
        v = np.zeros(days, dtype=int)
        prev = 0
        for t in range(days):
            logit = (base[h] + weekday_fx[h][wd[t] - 1] + loadings[h] * z[t]
                     + momentum[h] * (prev - 0.5) + rs.normal(0, noise * 0.3))
            v[t] = int(rs.uniform() < 1 / (1 + math.exp(-logit)))
            prev = v[t]
        out.append(v)
    return out


def lagged(rs, days, start, strength):
    """B follows A the day before."""
    a = (rs.uniform(size=days) < 0.5).astype(int)
    b = np.zeros(days, dtype=int)
    for t in range(1, days):
        p = 0.2 + strength * a[t - 1]
        b[t] = int(rs.uniform() < p)
    return [a, b]


def runs(rs, days, stay):
    """A Markov chain that keeps its state with probability `stay`: long
    streaks, so neighbouring days are far from independent."""
    v = np.zeros(days, dtype=int)
    v[0] = int(rs.uniform() < 0.5)
    for t in range(1, days):
        v[t] = v[t - 1] if rs.uniform() < stay else 1 - v[t - 1]
    return v


def blank(rs, values, rate, gaps=()):
    v = [int(a) for a in values]
    for t in range(len(v)):
        if rs.uniform() < rate:
            v[t] = -1
    for lo, hi in gaps:
        for t in range(lo, min(hi, len(v))):
            v[t] = -1
    return v


def build_cases():
    cases = []
    zeros = [[0.0] * 7 for _ in range(8)]

    # 1. Five streaky habits sharing a mood; 10% of days missing.
    rs = np.random.RandomState(20261101)
    days = 180
    data = streaky(rs, days, 5, START_EPOCH_DAY,
                   loadings=[1.4, 1.2, -1.0, 0.0, 0.8],
                   base=[0.1, 0.0, -0.2, 0.3, -0.1],
                   momentum=[1.5, 1.0, 1.2, 1.5, 0.8],
                   weekday_fx=[[0.3, 0.2, 0.0, 0.0, 0.0, -0.3, -0.6]] * 5)
    series = [dict(id="h%d" % i, values=blank(rs, d, 0.10, gaps=[(40 + 7 * i, 48 + 7 * i)]))
              for i, d in enumerate(data)]
    cases.append(dict(name="streaky_five_habits_180_days", startEpochDay=START_EPOCH_DAY, series=series))

    # 2. Two habits that only follow the weekday: raw phi is large, adjusted is not.
    rs = np.random.RandomState(7)
    days = 140
    wd = weekdays_for(START_EPOCH_DAY, days)
    a = [int(rs.uniform() < (0.9 if w <= 5 else 0.1)) for w in wd]
    b = [int(rs.uniform() < (0.85 if w <= 5 else 0.15)) for w in wd]
    c = [int(rs.uniform() < 0.5) for _ in wd]
    cases.append(dict(name="weekday_confounded_140_days", startEpochDay=START_EPOCH_DAY,
                      series=[dict(id="weekday_a", values=a), dict(id="weekday_b", values=b),
                              dict(id="coin", values=c)]))

    # 3. Overlap right at the threshold: 29, 30 and 31 shared days.
    rs = np.random.RandomState(3)
    days = 60
    base = (rs.uniform(size=(3, days)) < 0.5).astype(int)
    s_full = [int(v) for v in base[0]]
    s_29 = [int(v) for v in base[1]]
    s_30 = [int(v) for v in base[2]]
    for t in range(days):
        if t >= 29:
            s_29[t] = -1
        if t >= 30:
            s_30[t] = -1
    s_31 = [int(v) if t < 31 else -1 for t, v in enumerate(base[1])]
    cases.append(dict(name="overlap_threshold_29_30_31", startEpochDay=START_EPOCH_DAY + 3,
                      series=[dict(id="full", values=s_full), dict(id="d29", values=s_29),
                              dict(id="d30", values=s_30), dict(id="d31", values=s_31)]))

    # 4. Degenerate series: constant, weekday-only, rare, plus a normal pair.
    rs = np.random.RandomState(11)
    days = 98
    wd = weekdays_for(START_EPOCH_DAY, days)
    normal_a = (rs.uniform(size=days) < 0.5).astype(int)
    normal_b = np.where(rs.uniform(size=days) < 0.7, normal_a, 1 - normal_a)
    rare = np.zeros(days, dtype=int)
    rare[[10, 40, 77]] = 1
    cases.append(dict(name="degenerate_series_98_days", startEpochDay=START_EPOCH_DAY, series=[
        dict(id="always", values=[1] * days),
        dict(id="never", values=[0] * days),
        dict(id="mondays", values=[int(w == 1) for w in wd]),
        dict(id="rare", values=[int(v) for v in rare]),
        dict(id="a", values=[int(v) for v in normal_a]),
        dict(id="b", values=[int(v) for v in normal_b]),
    ]))

    # 5. A clear lagged effect and an unrelated habit.
    rs = np.random.RandomState(LAG_SEED)
    days = 150
    a, b = lagged(rs, days, START_EPOCH_DAY, 0.55)
    noise = (rs.uniform(size=days) < 0.4).astype(int)
    cases.append(dict(name="lagged_effect_150_days", startEpochDay=START_EPOCH_DAY + 1, series=[
        dict(id="sleep", values=blank(rs, a, 0.05)),
        dict(id="gym", values=blank(rs, b, 0.05)),
        dict(id="noise", values=blank(rs, noise, 0.05)),
    ]))

    # 6. Independent habits with long streaks: neighbouring days are strongly
    # dependent, so chance correlations are large and n_eff well below n.
    rs = np.random.RandomState(404)
    days = 150
    cases.append(dict(name="persistent_independent_runs_150_days", startEpochDay=START_EPOCH_DAY, series=[
        dict(id="r%d" % i, values=blank(rs, runs(rs, days, 0.9), 0.05)) for i in range(4)]))

    # 7. Long streaks with a real link: b copies a on 85% of days.
    rs = np.random.RandomState(405)
    days = 150
    a = runs(rs, days, 0.88)
    b = np.where(rs.uniform(size=days) < 0.85, a, 1 - a)
    c = runs(rs, days, 0.88)
    cases.append(dict(name="persistent_coupled_runs_150_days", startEpochDay=START_EPOCH_DAY + 2, series=[
        dict(id="a", values=blank(rs, a, 0.05)), dict(id="b", values=blank(rs, b, 0.05)),
        dict(id="c", values=blank(rs, c, 0.05))]))

    # 8. A year of eight habits for the false discovery family.
    rs = np.random.RandomState(2026)
    days = 366
    n = 8
    data = streaky(rs, days, n, START_EPOCH_DAY,
                   loadings=[1.2, 1.0, 0.9, -0.8, 0.0, 0.0, 0.5, -0.4],
                   base=[0.2, 0.0, -0.3, 0.1, 0.4, -0.5, 0.0, 0.2],
                   momentum=[1.2, 0.8, 1.5, 1.0, 0.4, 1.4, 0.9, 1.1],
                   weekday_fx=[[0.2, 0.1, 0.0, 0.0, 0.0, -0.2, -0.4]] * n)
    series = [dict(id="h%d" % i, values=blank(rs, d, 0.15)) for i, d in enumerate(data)]
    cases.append(dict(name="year_eight_habits_366_days", startEpochDay=START_EPOCH_DAY, series=series))
    return cases


def analysis_fixture():
    cases = []
    for c in build_cases():
        cases.append(dict(c, expected=analyze(c["startEpochDay"], c["series"], CONFIG)))
    return dict(versions=versions(), config=CONFIG, cases=cases)


def special_fixture():
    t_cases = []
    for df in [1.0, 2.0, 3.5, 7.25, 12.0, 20.6, 33.3, 60.0, 150.0, 400.75]:
        for t in [0.0, 0.3, 1.0, 1.96, 2.5, 4.0, 8.0, -2.2]:
            t_cases.append(dict(t=t, df=df, p=float(2 * stats.t.sf(abs(t), df))))
    quantiles = [
        dict(p=p, z=float(stats.norm.ppf(p)))
        for p in [1e-10, 1e-6, 0.001, 0.01, 0.025, 0.05, 0.1, 0.3, 0.5, 0.7, 0.9, 0.95, 0.975, 0.99, 0.999, 1 - 1e-8]
    ]
    betas = [
        dict(a=a, b=b, x=x, value=float(special.betainc(a, b, x)))
        for a, b in [(0.5, 0.5), (0.5, 10.0), (3.0, 0.5), (12.0, 7.0), (0.5, 100.0)]
        for x in [0.01, 0.2, 0.5, 0.8, 0.99]
    ]
    bh = []
    rs = np.random.RandomState(5)
    lists = [
        [0.04],
        [0.001, 0.008, 0.039, 0.041, 0.042, 0.06, 0.074, 0.205, 0.212, 0.216],
        [0.5, 0.5, 0.5, 1.0, 0.01],
        [1e-12, 0.3, 0.3, 0.9, 1.0, 0.0],
        [float(x) for x in rs.uniform(size=40)],
        [float(x) for x in rs.uniform(size=25) ** 3],
    ]
    for ps in lists:
        bh.append(dict(p=ps, q=[float(v) for v in stats.false_discovery_control(ps, method="bh")]))
    return dict(versions=versions(), tCases=t_cases, quantiles=quantiles, betas=betas, bh=bh)


def versions():
    return dict(numpy=np.__version__, scipy=scipy.__version__, sklearn=sklearn.__version__)


# --------------------------------------------------------------------------


def compare(a, b, path="", tol=1e-9):
    if isinstance(a, dict) and isinstance(b, dict):
        if a.keys() != b.keys():
            return "%s: keys differ" % path
        for k in a:
            if k == "versions":
                continue
            r = compare(a[k], b[k], "%s.%s" % (path, k), tol)
            if r:
                return r
    elif isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            return "%s: length differs" % path
        for i, (x, y) in enumerate(zip(a, b)):
            r = compare(x, y, "%s[%d]" % (path, i), tol)
            if r:
                return r
    elif isinstance(a, float) or isinstance(b, float):
        if a is None or b is None or abs(a - b) > tol * max(1.0, abs(a)):
            return "%s: %r != %r" % (path, a, b)
    elif a != b:
        return "%s: %r != %r" % (path, a, b)
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="compare with the committed files instead of writing")
    args = parser.parse_args()
    files = {"analysis.json": analysis_fixture(), "special.json": special_fixture()}
    status = 0
    for name, data in files.items():
        path = os.path.join(OUT, name)
        if args.check:
            with open(path) as f:
                diff = compare(json.load(f), json.loads(json.dumps(data)))
            print("%s: %s" % (name, diff or "matches"))
            status |= 1 if diff else 0
        else:
            os.makedirs(OUT, exist_ok=True)
            with open(path, "w") as f:
                json.dump(data, f, indent=1, sort_keys=True)
                f.write("\n")
            print("wrote", os.path.normpath(path))
    return status


if __name__ == "__main__":
    sys.exit(main())
