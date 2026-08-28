import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

/// Widget tests for the core tutorial flows.
///
/// NOTE: `pumpAndSettle` is intentionally avoided everywhere because the
/// pulse animation loops forever — it would never settle.
void main() {
  const focus = Duration(milliseconds: 100);
  const unfocus = Duration(milliseconds: 100);

  group('TutorialCoachMark', () {
    testWidgets('focuses the first target and shows its content',
        (tester) async {
      final k0 = GlobalKey();
      final tutorial = _buildTutorial(
        targets: [_target('0', k0, 'content-0')],
        pulseEnable: false,
      );

      await _showAndFocus(tester, tutorial, keys: [k0], focus: focus);

      expect(find.text('content-0'), findsOneWidget);
      expect(tutorial.isShowing, isTrue);

      await _teardown(tester);
    });

    testWidgets('calls onFinish and removes the overlay when completed',
        (tester) async {
      final k0 = GlobalKey();
      var finished = false;
      final tutorial = _buildTutorial(
        targets: [_target('0', k0, 'content-0')],
        onFinish: () => finished = true,
        pulseEnable: false,
      );

      await _showAndFocus(tester, tutorial, keys: [k0], focus: focus);

      tutorial.next();
      await _pumpAdvance(tester, focus: focus, unfocus: unfocus);

      expect(finished, isTrue);
      expect(tutorial.isShowing, isFalse);

      await _teardown(tester);
    });

    testWidgets('skip button calls onSkip and closes the tutorial',
        (tester) async {
      final k0 = GlobalKey();
      var skipped = false;
      final tutorial = _buildTutorial(
        targets: [_target('0', k0, 'content-0')],
        onSkip: () {
          skipped = true;
          return true;
        },
        pulseEnable: false,
      );

      await _showAndFocus(tester, tutorial, keys: [k0], focus: focus);

      await tester.tap(find.text('SKIP'));
      await tester.pump();

      expect(skipped, isTrue);
      expect(tutorial.isShowing, isFalse);

      await _teardown(tester);
    });

    testWidgets('onSkip returning false advances instead of closing',
        (tester) async {
      final k0 = GlobalKey();
      final k1 = GlobalKey();
      var skipped = false;
      final tutorial = _buildTutorial(
        targets: [
          _target('0', k0, 'content-0'),
          _target('1', k1, 'content-1'),
        ],
        onSkip: () {
          skipped = true;
          return false; // keep the tutorial open, go to next
        },
        pulseEnable: false,
      );

      await _showAndFocus(tester, tutorial, keys: [k0, k1], focus: focus);

      await tester.tap(find.text('SKIP'));
      await _pumpAdvance(tester, focus: focus, unfocus: unfocus);

      expect(skipped, isTrue);
      expect(tutorial.isShowing, isTrue);
      expect(find.text('content-1'), findsOneWidget);

      await _teardown(tester);
    });

    testWidgets('tapping the target calls onClickTarget and advances',
        (tester) async {
      final k0 = GlobalKey();
      final k1 = GlobalKey();
      var clicked = false;
      final tutorial = _buildTutorial(
        targets: [
          _target('0', k0, 'content-0'),
          _target('1', k1, 'content-1'),
        ],
        onClickTarget: (_) => clicked = true,
        pulseEnable: false,
      );

      await _showAndFocus(tester, tutorial, keys: [k0, k1], focus: focus);

      await tester.tap(find.byKey(k0));
      await _pumpAdvance(tester, focus: focus, unfocus: unfocus);

      expect(clicked, isTrue);
      expect(find.text('content-1'), findsOneWidget);

      await _teardown(tester);
    });

    testWidgets(
      'rapid synchronous next() calls only advance one step '
      '(#175, #183)',
      (tester) async {
        final k0 = GlobalKey();
        final k1 = GlobalKey();
        final k2 = GlobalKey();
        TutorialCoachMarkController? controller;
        final tutorial = _buildTutorial(
          targets: [
            _targetWithBuilder('0', k0, (c, ctrl) {
              controller = ctrl;
              return const Text('content-0');
            }),
            _target('1', k1, 'content-1'),
            _target('2', k2, 'content-2'),
          ],
          pulseEnable: false,
        );

        await _showAndFocus(tester, tutorial, keys: [k0, k1, k2], focus: focus);

        // Two synchronous calls — the second must be swallowed by the
        // `_isAnimating` guard set before the user callback await.
        controller!.next();
        controller!.next();
        await _pumpAdvance(tester, focus: focus, unfocus: unfocus);

        // ignore: avoid_print
        print('DIAG texts: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList()}');
        // ignore: avoid_print
        print('DIAG isShowing: ${tutorial.isShowing}');

        expect(find.text('content-1'), findsOneWidget,
            reason: 'rapid taps must not skip to target 2');
        expect(find.text('content-2'), findsNothing);

        await _teardown(tester);
      },
    );

    testWidgets(
      'rapid double-tap on the overlay only advances one step '
      '(#175, #183)',
      (tester) async {
        final k0 = GlobalKey();
        final k1 = GlobalKey();
        final k2 = GlobalKey();
        final tutorial = _buildTutorial(
          targets: [
            _target('0', k0, 'content-0', enableOverlayTab: true),
            _target('1', k1, 'content-1', enableOverlayTab: true),
            _target('2', k2, 'content-2', enableOverlayTab: true),
          ],
          pulseEnable: false,
        );

        await _showAndFocus(tester, tutorial, keys: [k0, k1, k2], focus: focus);

        // First tap starts the transition; second tap lands while animating.
        await tester.tapAt(const Offset(10, 10));
        await tester.pump(const Duration(milliseconds: 5));
        await tester.tapAt(const Offset(10, 10));
        await _pumpAdvance(tester, focus: focus, unfocus: unfocus);

        expect(find.text('content-1'), findsOneWidget,
            reason: 'double-tap must not skip to target 2');
        expect(find.text('content-2'), findsNothing);

        await _teardown(tester);
      },
    );

    testWidgets(
      'next() is not delayed by a long pulse animation (#235)',
      (tester) async {
        final k0 = GlobalKey();
        final k1 = GlobalKey();
        final tutorial = _buildTutorial(
          targets: [
            _target('0', k0, 'content-0'),
            _target('1', k1, 'content-1'),
          ],
          pulseEnable: true,
          // A 10s pulse would delay the unfocus by up to 10s with the bug.
          pulse: const Duration(seconds: 10),
          focus: focus,
          unfocus: unfocus,
        );

        await _showAndFocus(tester, tutorial, keys: [k0, k1], focus: focus);

        tutorial.next();
        // ~305ms total — far below the 10s pulse cycle.
        await _pumpAdvance(tester, focus: focus, unfocus: unfocus);

        expect(find.text('content-1'), findsOneWidget,
            reason: 'unfocus must not wait for the pulse animation to end');

        await _teardown(tester);
      },
    );

    testWidgets(
      'a missing target is skipped and the tutorial continues '
      '(#218, #223, #199)',
      (tester) async {
        final k0 = GlobalKey();
        final kMissing = GlobalKey(); // never attached to a widget
        final k2 = GlobalKey();
        var finished = false;
        final tutorial = _buildTutorial(
          targets: [
            _target('0', k0, 'content-0'),
            _target('missing', kMissing, 'content-missing'),
            _target('2', k2, 'content-2'),
          ],
          onFinish: () => finished = true,
          pulseEnable: false,
        );

        await _showAndFocus(tester, tutorial, keys: [k0, k2], focus: focus);

        tutorial.next();
        await _pumpAdvance(tester, focus: focus, unfocus: unfocus);

        expect(find.text('content-2'), findsOneWidget,
            reason: 'the tutorial should skip the unavailable target');
        expect(finished, isFalse,
            reason: 'the tutorial must not abort when a target is missing');

        await _teardown(tester);
      },
    );

    testWidgets(
      'finishes when no remaining target is available (#218, #223)',
      (tester) async {
        final kMissing0 = GlobalKey(); // never attached
        final kMissing1 = GlobalKey(); // never attached
        var finished = false;
        final tutorial = _buildTutorial(
          targets: [
            _target('0', kMissing0, 'content-0'),
            _target('1', kMissing1, 'content-1'),
          ],
          onFinish: () => finished = true,
          pulseEnable: false,
        );

        await _showAndFocus(tester, tutorial, keys: [], focus: focus);

        expect(finished, isTrue,
            reason: 'with no available targets the tutorial must finish');
        expect(tutorial.isShowing, isFalse);

        await _teardown(tester);
      },
    );

    testWidgets('previous() returns to the previous target', (tester) async {
      final k0 = GlobalKey();
      final k1 = GlobalKey();
      final tutorial = _buildTutorial(
        targets: [
          _target('0', k0, 'content-0'),
          _target('1', k1, 'content-1'),
        ],
        pulseEnable: false,
      );

      await _showAndFocus(tester, tutorial, keys: [k0, k1], focus: focus);

      tutorial.next();
      await _pumpAdvance(tester, focus: focus, unfocus: unfocus);
      expect(find.text('content-1'), findsOneWidget);

      tutorial.previous();
      await _pumpAdvance(tester, focus: focus, unfocus: unfocus);
      expect(find.text('content-0'), findsOneWidget);

      await _teardown(tester);
    });

    testWidgets('initialFocus starts at the given target', (tester) async {
      final k0 = GlobalKey();
      final k1 = GlobalKey();
      final tutorial = _buildTutorial(
        targets: [
          _target('0', k0, 'content-0'),
          _target('1', k1, 'content-1'),
        ],
        initialFocus: 1,
        pulseEnable: false,
      );

      await _showAndFocus(tester, tutorial, keys: [k0, k1], focus: focus);

      expect(find.text('content-1'), findsOneWidget);
      expect(find.text('content-0'), findsNothing);

      await _teardown(tester);
    });
  });
}

/// Builds a [TargetFocus] with a static [child] content.
TargetFocus _target(
  String identify,
  GlobalKey key,
  String content, {
  bool enableOverlayTab = false,
}) {
  return TargetFocus(
    identify: identify,
    keyTarget: key,
    enableOverlayTab: enableOverlayTab,
    contents: [
      TargetContent(
        align: ContentAlign.bottom,
        child: Text(content),
      ),
    ],
  );
}

/// Builds a [TargetFocus] with a dynamic [builder] content.
TargetFocus _targetWithBuilder(
  String identify,
  GlobalKey key,
  TargetContentBuilder builder,
) {
  return TargetFocus(
    identify: identify,
    keyTarget: key,
    contents: [
      TargetContent(align: ContentAlign.bottom, builder: builder),
    ],
  );
}

/// Builds a [TutorialCoachMark] with short, fast animation durations.
TutorialCoachMark _buildTutorial({
  required List<TargetFocus> targets,
  VoidCallback? onFinish,
  bool Function()? onSkip,
  FutureOr<void> Function(TargetFocus)? onClickTarget,
  bool pulseEnable = true,
  Duration focus = const Duration(milliseconds: 100),
  Duration unfocus = const Duration(milliseconds: 100),
  Duration pulse = const Duration(milliseconds: 500),
  int initialFocus = 0,
}) {
  return TutorialCoachMark(
    targets: targets,
    onFinish: onFinish,
    onSkip: onSkip,
    onClickTarget: onClickTarget,
    pulseEnable: pulseEnable,
    focusAnimationDuration: focus,
    unFocusAnimationDuration: unfocus,
    pulseAnimationDuration: pulse,
    initialFocus: initialFocus,
  );
}

/// Pumps an app whose body contains a widget for each of [keys] plus a
/// button that shows [tutorial], taps the button and pumps until the first
/// target's focus animation completes.
Future<void> _showAndFocus(
  WidgetTester tester,
  TutorialCoachMark tutorial, {
  required List<GlobalKey> keys,
  required Duration focus,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final key in keys)
                    SizedBox(
                      key: key,
                      width: 120,
                      height: 60,
                      child: const ColoredBox(color: Colors.blue),
                    ),
                  ElevatedButton(
                    onPressed: () => tutorial.show(context: context),
                    child: const Text('start'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('start'));
  // NOTE: pump(Duration.zero) is required, not pump() — the package uses
  // Future.delayed(Duration.zero) timers (postFrame, _runFocus) which only
  // fire when the fake clock elapses.
  await tester.pump(Duration.zero); // trigger show() + postFrame
  await tester.pump(Duration.zero); // overlay inserted, initState schedules _runFocus
  await tester.pump(focus + const Duration(milliseconds: 50)); // focus in
  await tester.pump(); // build the focused content
}

/// Pumps through one advance (unfocus + focus) using separate frames so the
/// chained async state transitions (reverse -> goToFocus -> forward) settle.
Future<void> _pumpAdvance(
  WidgetTester tester, {
  required Duration focus,
  required Duration unfocus,
}) async {
  await tester.pump(unfocus); // unfocus (reverse) completes
  await tester.pump(focus); // next focus animation
  await tester.pump(focus); // focus completes
  await tester.pump(); // build the focused content
}

/// Disposes the whole tree so tickers/timers don't leak between tests.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
}
