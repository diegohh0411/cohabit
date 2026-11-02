/// Benjamini-Hochberg adjusted p-values (q-values), in input order.
///
/// With the p-values sorted ascending as p(1) <= ... <= p(m), the adjusted
/// value of p(i) is the minimum over j >= i of min(1, m * p(j) / j). Rejecting
/// every hypothesis with q <= alpha controls the false discovery rate at alpha
/// when the tests are independent or positively dependent. Ties are broken by
/// input position, which cannot change the adjusted values. Same result as
/// `scipy.stats.false_discovery_control(p, method='bh')`.
List<double> benjaminiHochberg(List<double> p) {
  final m = p.length;
  final order = List<int>.generate(m, (i) => i)
    ..sort((a, b) {
      final c = p[a].compareTo(p[b]);
      return c != 0 ? c : a.compareTo(b);
    });
  final q = List<double>.filled(m, 0);
  var running = 1.0;
  for (var rank = m; rank >= 1; rank--) {
    final i = order[rank - 1];
    final adjusted = p[i] * m / rank;
    if (adjusted < running) running = adjusted;
    q[i] = running > 1 ? 1 : running;
  }
  return q;
}
