import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/ui/components.dart';

import 'test_theme.dart';

void main() {
  testWidgets('profile avatar preserves and covers a non-square source', (
    tester,
  ) async {
    final data = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAAXNSR0IA'
      'rs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQA'
      'AAARSURBVBhXY2BoYPjPwPD/PwALgQN+Jw0/qAAAAABJRU5ErkJggg==',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: testLightTheme(),
        home: Scaffold(
          body: Center(
            child: ProfileAvatar(
              fallbackName: 'Home Owner',
              imageProvider: MemoryImage(data),
              radius: 24,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final avatar = find.byType(ProfileAvatar);
    expect(tester.getSize(avatar), const Size.square(48));
    expect(
      find.descendant(of: avatar, matching: find.byType(ClipOval)),
      findsOneWidget,
    );
    final image = tester.widget<Image>(
      find.descendant(of: avatar, matching: find.byType(Image)),
    );
    expect(image.fit, BoxFit.cover);
    expect(image.alignment, Alignment.center);
  });
}
