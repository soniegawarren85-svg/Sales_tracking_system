import 'package:flutter/material.dart';

class BranchAnalyticsBars extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final List<Color> colors;
  final List<double>? refunds;
  final List<double>? reduced;
  final String selectedStatus;

  const BranchAnalyticsBars({
    required this.values,
    required this.labels,
    this.colors = const [Color(0xFFC2105C), Color(0xFFE91E63)],
    this.refunds,
    this.reduced,
    this.selectedStatus = 'All',
  });

  @override
  Widget build(BuildContext context) {
    final maximum = values.fold<double>(
      0,
      (max, value) => value > max ? value : max,
    );
    // Keep four readable intervals regardless of the sales amount.
    final targetStep = maximum / 4;
    var magnitude = 50.0;
    while (magnitude * 10 < targetStep) {
      magnitude *= 10;
    }
    final step = [1.0, 2.0, 5.0, 10.0]
        .map((factor) => magnitude * factor)
        .firstWhere((candidate) => candidate >= targetStep);
    const intervals = 4;
    final ceiling = intervals * step;
    return LayoutBuilder(
      builder: (context, constraints) {
        final plotHeight = (constraints.maxHeight - 55).clamp(50.0, 300.0);
        return _buildPlot(context, ceiling, plotHeight, 28, intervals, step);
      },
    );
  }

  Widget _buildPlot(
    BuildContext context,
    double ceiling,
    double plotHeight,
    double labelHeight,
    int intervals,
    double step,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Amount (₱)',
          style: TextStyle(fontSize: 9, color: Colors.black54),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 56,
                height: plotHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: List.generate(
                    intervals + 1,
                    (i) => Positioned(
                      top: i * plotHeight / intervals - 5,
                      right: 6,
                      child: Text(
                        (ceiling - i * step).toStringAsFixed(0),
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    SizedBox(
                      height: plotHeight,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(
                          intervals + 1,
                          (_) => const Divider(
                            height: 0,
                            thickness: 0.5,
                            color: Color(0xFFE5DDE0),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List.generate(values.length, (index) {
                        final value = values[index];
                        final height = plotHeight * value / ceiling;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Column(
                              children: [
                                SizedBox(
                                  height: plotHeight,
                                  child: Align(
                                    alignment: Alignment.bottomCenter,
                                    child: GestureDetector(
                                      onTap: value <= 0
                                          ? null
                                          : () {
                                              final completed =
                                                  (value -
                                                          (refunds?[index] ??
                                                              0) -
                                                          (reduced?[index] ??
                                                              0))
                                                      .clamp(
                                                        0,
                                                        double.infinity,
                                                      );
                                              final details =
                                                  selectedStatus == 'All'
                                                  ? 'Completed: ₱${completed.toStringAsFixed(2)}\nRefund: ₱${(refunds?[index] ?? 0).toStringAsFixed(2)}\nReduced: ₱${(reduced?[index] ?? 0).toStringAsFixed(2)}'
                                                  : '$selectedStatus: ₱${value.toStringAsFixed(2)}';
                                              showDialog<void>(
                                                context: context,
                                                builder: (_) => AlertDialog(
                                                  title: Text(labels[index]),
                                                  content: Text(details),
                                                ),
                                              );
                                            },
                                      child: Container(
                                        width: double.infinity,
                                        height: height,
                                        clipBehavior: Clip.antiAlias,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.bottomCenter,
                                            end: Alignment.topCenter,
                                            colors: colors,
                                          ),
                                          borderRadius:
                                              const BorderRadius.vertical(
                                                top: Radius.circular(5),
                                              ),
                                        ),
                                        child: value <= 0
                                            ? null
                                            : Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.end,
                                                children: [
                                                  if ((refunds?[index] ?? 0) >
                                                      0)
                                                    Container(
                                                      height:
                                                          plotHeight *
                                                          refunds![index] /
                                                          ceiling,
                                                      color: const Color(
                                                        0xFFF9A825,
                                                      ),
                                                    ),
                                                  if ((reduced?[index] ?? 0) >
                                                      0)
                                                    Container(
                                                      height:
                                                          plotHeight *
                                                          reduced![index] /
                                                          ceiling,
                                                      color: const Color(
                                                        0xFF1976D2,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  height: labelHeight,
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 5),
                                    child: Text(
                                      labels[index],
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      style: const TextStyle(
                                        fontSize: 8,
                                        color: Colors.black54,
                                        height: 1.05,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
