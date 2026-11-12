import 'package:flutter/material.dart';
import 'package:flutter_len_os/home_sections.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget home() => MaterialApp(
        home: Scaffold(
          body: HomeSectionList(sections: [
            for (var i = 0; i < 6; i++)
              HomeSection(title: 'Section $i', icon: Icons.star, onTap: () {}),
          ]),
        ),
      );

  testWidgets('the six cards fill most of a phone screen', (tester) async {
    tester.view.physicalSize = const Size(1080, 2280); // 412 x 869 at 2.625x
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(home());

    final screen = tester.getSize(find.byType(Scaffold)).height;
    final cards = find.byType(Card);
    expect(cards, findsNWidgets(6));
    final top = tester.getTopLeft(cards.first).dy;
    final bottom = tester.getBottomLeft(cards.last).dy;
    // All six are on screen, using most of it, with a little room to spare.
    expect(top, lessThan(20));
    final unused = screen - bottom;
    expect(unused, greaterThan(40));
    expect(unused, lessThan(screen * 0.2));
    expect(tester.getSize(cards.first).height, greaterThan(90));
  });

  testWidgets('cards keep a minimum height on short screens and scroll',
      (tester) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(home());
    expect(tester.getSize(find.byType(Card).first).height,
        greaterThanOrEqualTo(HomeSectionList.minTileHeight));
    expect(find.text('Section 5'), findsNothing); // Further down the list.
    await tester.scrollUntilVisible(find.text('Section 5'), 100);
    expect(find.text('Section 5'), findsOneWidget);
  });

  Widget withFooter() => MaterialApp(
        home: Scaffold(
          body: HomeSectionList(
            sections: [
              for (var i = 0; i < 5; i++)
                HomeSection(title: 'Section $i', icon: Icons.star, onTap: () {}),
            ],
            footer: const Text('cat'),
            footerHeight: 52,
          ),
        ),
      );

  testWidgets('the footer shows under the cards when there is room', (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(withFooter());
    expect(find.text('cat'), findsOneWidget);
    expect(tester.getTopLeft(find.text('cat')).dy,
        greaterThan(tester.getBottomLeft(find.byType(Card).last).dy));
  });

  testWidgets('the footer is left out when the cards fill the screen', (tester) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(withFooter());
    expect(find.text('cat'), findsNothing);
  });
}
