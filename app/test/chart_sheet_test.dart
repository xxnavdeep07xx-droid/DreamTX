import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:dreamtx/core/chart_math.dart';
import 'package:dreamtx/widgets/chart_sheet.dart';

/// The chart sheet edits every series: each series has its own value column,
/// and Done returns all of them (names and colors kept).
void main() {
  testWidgets('editing a second series returns both series', (tester) async {
    const data = ChartData(
      style: 'column',
      title: null,
      labels: const ['Q1', 'Q2'],
      series: const [
        ChartSeriesData(name: 'A', values: [1, 2], color: 'EF4444'),
        ChartSeriesData(name: 'B', values: [3, 4]),
      ],
    );
    ChartData? out;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            key: const Key('open'),
            onPressed: () async {
              out = await Navigator.of(ctx).push<ChartData>(MaterialPageRoute(
                  builder: (_) => Scaffold(body: ChartSheet(data: data))));
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chart_value_s1_0')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('chart_value_s1_1')), '7.5');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('chart_done')));
    await tester.tap(find.byKey(const Key('chart_done')));
    await tester.pumpAndSettle();

    final result = out!;
    expect(result.labels, ['Q1', 'Q2']);
    expect(result.series.length, 2);
    expect(result.series[0].values, [1.0, 2.0]);
    expect(result.series[0].color, 'EF4444');
    expect(result.series[1].name, 'B');
    expect(result.series[1].values, [3.0, 7.5]);
  });

  testWidgets('Done stays disabled while any series has a non-number', (tester) async {
    const data = ChartData(
      style: 'line',
      title: 'T',
      labels: ['Q1'],
      series: [
        ChartSeriesData(name: 'A', values: [1]),
        ChartSeriesData(name: 'B', values: [2]),
      ],
    );
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: ChartSheet(data: data))));
    await tester.pumpAndSettle();

    FilledButton done() => tester.widget<FilledButton>(find.byKey(const Key('chart_done')));
    expect(done().onPressed, isNotNull);

    await tester.enterText(find.byKey(const Key('chart_value_s1_0')), 'x');
    await tester.pumpAndSettle();
    expect(done().onPressed, isNull);
  });
}
