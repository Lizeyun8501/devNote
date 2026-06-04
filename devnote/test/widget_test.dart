import 'package:flutter_test/flutter_test.dart';

import 'package:devnote/main.dart';

void main() {
  testWidgets('App renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const DevNoteApp());
    expect(find.text('笔记列表'), findsOneWidget);
  });
}
