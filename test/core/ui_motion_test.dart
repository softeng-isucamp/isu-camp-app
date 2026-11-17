import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isu_camp_app/core/app_motion.dart';
import 'package:isu_camp_app/core/app_theme.dart';
import 'package:isu_camp_app/core/widgets/app_pressable.dart';
import 'package:isu_camp_app/features/auth/screens/get_started_screen.dart';
import 'package:isu_camp_app/features/auth/screens/register_screen.dart';
import 'package:isu_camp_app/features/onboarding/screens/welcome_greeting_screen.dart';

void main() {
  Widget wrap(Widget child, {bool reduced = false, double scale = 1}) =>
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reduced,
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        ),
        home: child,
      );

  testWidgets('onboarding actions are visible on the first frame',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final screen in [
      const GetStartedScreen(),
      const WelcomeGreetingScreen(userName: 'Visitor')
    ]) {
      await tester.pumpWidget(wrap(screen));
      final action = find.byType(AppPressable);
      expect(action, findsOneWidget);
      final fade =
          find.ancestor(of: action, matching: find.byType(FadeTransition));
      for (final widget in tester.widgetList<FadeTransition>(fade)) {
        expect(widget.opacity.value, 1);
      }
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('reduced motion settles entrances without waiting',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final screen in [
      const GetStartedScreen(),
      const WelcomeGreetingScreen(userName: 'Visitor'),
      const RegisterScreen()
    ]) {
      await tester.pumpWidget(wrap(screen, reduced: true));
      for (final fade
          in tester.widgetList<FadeTransition>(find.byType(FadeTransition))) {
        expect(fade.opacity.value, 1);
      }
      for (final slide
          in tester.widgetList<SlideTransition>(find.byType(SlideTransition))) {
        expect(slide.position.value, Offset.zero);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('onboarding scrolls on a narrow phone with large text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final screen in [
      const GetStartedScreen(),
      const WelcomeGreetingScreen(userName: 'Visitor')
    ]) {
      await tester.pumpWidget(wrap(screen, reduced: true, scale: 2));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byType(AppPressable));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('a second touch catches a settling sheet', (tester) async {
    final controller = DraggableScrollableController();
    addTearDown(controller.dispose);
    late BuildContext sheetContext;
    await tester.pumpWidget(wrap(Builder(builder: (context) {
      sheetContext = context;
      return DraggableScrollableSheet(
        controller: controller,
        builder: (_, scrollController) =>
            ListView(controller: scrollController),
      );
    })));
    AppMotion.settleSheet(sheetContext, controller, 0.9);
    await tester.pump(const Duration(milliseconds: 80));
    AppMotion.catchSheet(controller);
    final caught = controller.size;
    await tester.pump(const Duration(seconds: 1));
    expect(controller.size, caught);
    await tester.pumpWidget(const SizedBox());
  });
}
