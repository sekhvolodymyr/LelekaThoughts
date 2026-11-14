import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:leleka_thoughts/main.dart' as application;
import 'package:leleka_thoughts/store.dart';
import 'package:leleka_thoughts/editor.dart';
import 'package:leleka_thoughts/posts.dart';
import 'package:leleka_thoughts/stories.dart';
import 'package:leleka_thoughts/screens.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Native UI and shared-backend creator journey', (tester) async {
    const password = String.fromEnvironment('QA_PASSWORD');
    const peerPassword = String.fromEnvironment('QA_PEER_PASSWORD');
    const peerEmail = String.fromEnvironment(
      'QA_PEER_EMAIL',
      defaultValue: 'native.qa.20261114@example.invalid',
    );
    expect(
      password,
      isNotEmpty,
      reason: 'Pass a local --dart-define-from-file; never commit credentials.',
    );
    await application.main();
    if (app.uid != null) {
      await app.db.auth.signOut();
      await app.refresh();
    }
    await app.refresh();
    await tester.pumpAndSettle();
    expect(find.byType(PostCard), findsWidgets);
    expect(find.text('LelekaThoughts'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sign-in')));
    await tester.pumpAndSettle();
    Finder input(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    );
    await tester.enterText(input('Email або @нік'), '@leleka_test');
    await tester.enterText(input('Пароль'), password);
    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    for (var i = 0; i < 100 && app.me == null; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(app.me?['username'], 'leleka_test');
    for (
      var i = 0;
      i < 150 &&
          find.byKey(const ValueKey('auth-submit')).evaluate().isNotEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byKey(const ValueKey('auth-submit')), findsNothing);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('theme-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('theme-lavender')));
    await tester.pumpAndSettle();
    expect(app.palette.id, 'lavender');
    await tester.tap(find.widgetWithText(FilledButton, 'Готово'));
    await tester.pumpAndSettle();

    // Publish using native widgets, not a web renderer.
    await tester.tap(find.byKey(const ValueKey('create')));
    await tester.pumpAndSettle();
    expect(find.byType(Editor), findsOneWidget);
    final marker = 'Native QA ${DateTime.now().millisecondsSinceEpoch}';
    await tester.enterText(find.byKey(const ValueKey('compose-body')), marker);
    await tester.tap(find.byKey(const ValueKey('publish')));
    for (var i = 0; i < 150 && find.byType(Editor).evaluate().isNotEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(Editor), findsNothing);
    final first = app.posts.firstWhere((p) => p['body'] == marker);
    final peer = SupabaseClient(
      apiUrl,
      publicKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final uploaded = <LelekaRecord>[];
    String? threadId, seriesId, conversationId;
    final postIds = <String>[text(first['id'])];
    String? storyId;
    try {
      await peer.auth.signInWithPassword(
        email: peerEmail,
        password: peerPassword,
      );
      final peerId = peer.auth.currentUser!.id;
      final existingChats = await app.db
          .from('conversations')
          .select('id')
          .or('member_a.eq.$peerId,member_b.eq.$peerId');
      expect(
        existingChats,
        isEmpty,
        reason:
            'Use a fresh QA peer or reset only this fixture conversation '
            'before rerunning the pending-request scenario.',
      );
      final peerProfile = await peer
          .from('profiles')
          .select()
          .eq('id', peerId)
          .maybeSingle();
      if (peerProfile == null)
        await peer.rpc(
          'app_action',
          params: {
            'action': 'onboard',
            'payload': {
              'username': 'native_qa_peer',
              'display_name': 'Native QA',
              'birth_date': '2002-01-01',
              'interests': ['Дизайн'],
            },
          },
        );
      final second = row(
        await app.action('post', {
          'body': '$marker continuation',
          'parent_id': first['id'],
          'thread_title': 'Native QA chain',
          'media': [],
          'topics': [],
        }),
      );
      threadId = text(second['thread_id']);
      postIds.add(text(second['id']));
      expect(threadId, isNotEmpty);
      final image = File('${Directory.systemTemp.path}/native-qa.png');
      await image.writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      );
      final media = await app.upload(XFile(image.path));
      uploaded.add(media);
      final story = row(
        await app.action('story', {
          'media': media,
          'caption': 'Native QA process',
          'series_title': 'Native QA series',
          'thread_id': threadId,
          'post_id': second['id'],
        }),
      );
      storyId = text(story['id']);
      final savedStory = await app.db
          .from('stories')
          .select()
          .eq('id', storyId)
          .single();
      seriesId = text(savedStory['series_id']);
      expect(seriesId, isNotEmpty);
      await peer.rpc(
        'app_action',
        params: {
          'action': 'follow',
          'payload': {'id': app.uid},
        },
      );
      await peer.rpc(
        'app_action',
        params: {
          'action': 'comment',
          'payload': {'id': first['id'], 'body': 'Native QA comment'},
        },
      );
      await app.action('like', {'id': second['id']});
      await app.action('save', {'id': second['id']});
      await peer.rpc(
        'app_action',
        params: {
          'action': 'like_story',
          'payload': {'id': storyId},
        },
      );
      await peer.rpc(
        'app_action',
        params: {
          'action': 'view_story',
          'payload': {'id': storyId},
        },
      );
      final sent = row(
        await app.action('send', {
          'recipient_id': peerId,
          'body': 'Native QA message request',
        }),
      );
      conversationId = text(sent['id']);
      var denied = false;
      try {
        await app.action('send', {
          'recipient_id': peerId,
          'body': 'Must wait for acceptance',
        });
      } catch (e) {
        denied = true;
      }
      expect(denied, isTrue);
      await peer.rpc(
        'app_action',
        params: {
          'action': 'accept_chat',
          'payload': {'id': conversationId, 'accept': true},
        },
      );
      await app.action('send', {
        'recipient_id': peerId,
        'body': 'Native QA accepted message',
      });
      expect(
        (await app.db
                .from('messages')
                .select()
                .eq('conversation_id', conversationId))
            .length,
        2,
      );
      await app.action('read_notifications');
      expect(app.saved(second['id']), isTrue);
      final navigator = Navigator.of(
        tester.element(find.byType(application.HomeShell)),
      );
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => ThreadPage(threadId!)),
      );
      await tester.pumpAndSettle();
      for (
        var i = 0;
        i < 100 && find.text('Native QA chain').evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.text('Native QA chain'), findsWidgets);
      navigator.pop();
      await tester.pumpAndSettle();
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => SeriesPage(seriesId!)),
      );
      await tester.pumpAndSettle();
      for (
        var i = 0;
        i < 100 && find.text('Native QA series').evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.text('Native QA series'), findsWidgets);
      navigator.pop();
      await tester.pumpAndSettle();
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => ChatPage(conversation: conversationId),
        ),
      );
      await tester.pumpAndSettle();
      for (
        var i = 0;
        i < 100 && find.text('Native QA accepted message').evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.text('Native QA accepted message'), findsOneWidget);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      debugPrint(
        'NATIVE_JOURNEY_PASS post/thread/story/media/comment/follow/save/like/request/accept/chat',
      );
    } finally {
      if (storyId != null) {
        await app.action('delete_story', {'id': storyId});
      }
      for (final id in postIds) {
        await app.action('delete_post', {'id': id});
      }
      await app.removeMedia(uploaded);
      await peer.auth.signOut();
      await peer.dispose();
      debugPrint(
        'NATIVE_QA_CLEANUP thread=$threadId series=$seriesId conversation=$conversationId',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
