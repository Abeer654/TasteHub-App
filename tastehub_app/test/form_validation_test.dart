// E-02 (single-video YouTube links) and E-03 (cooking time) validation.

import 'package:flutter_test/flutter_test.dart';
import 'package:tastehub_app/screens/recipe_form/basics_fields.dart';

void main() {
  group('youtubeVideoId (E-02)', () {
    test('accepts the four single-video shapes', () {
      expect(
        youtubeVideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
      expect(youtubeVideoId('https://youtu.be/dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
      expect(
        youtubeVideoId('https://www.youtube.com/shorts/dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
      expect(
        youtubeVideoId('https://m.youtube.com/watch?v=dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
    });

    test('rejects search, playlist, channel and bare links', () {
      // The seed recipes ship with a search URL - it must fail.
      expect(
        youtubeVideoId('https://www.youtube.com/results?search_query=biryani'),
        isNull,
      );
      expect(
        youtubeVideoId('https://www.youtube.com/playlist?list=PL123'),
        isNull,
      );
      expect(
        youtubeVideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL1'),
        isNull,
      );
      expect(
        youtubeVideoId('https://www.youtube.com/@somechannel'),
        isNull,
      );
      expect(youtubeVideoId('https://www.youtube.com/'), isNull);
      expect(youtubeVideoId('youtube.com/watch?v=dQw4w9WgXcQ'), isNull);
      expect(youtubeVideoId('not a url'), isNull);
      expect(youtubeVideoId(''), isNull);
    });

    test('youtubeUrlError only fires for a non-empty invalid link', () {
      expect(youtubeUrlError(''), isNull);
      expect(youtubeUrlError('https://youtu.be/dQw4w9WgXcQ'), isNull);
      expect(
        youtubeUrlError('https://www.youtube.com/results?search_query=x'),
        'Paste a link to a single YouTube video.',
      );
    });
  });

  group('cookingTimeError (E-03)', () {
    test('empty is allowed, anything outside 1-1440 is not', () {
      expect(cookingTimeError(''), isNull);
      expect(cookingTimeError('60'), isNull);
      expect(cookingTimeError('1'), isNull);
      expect(cookingTimeError('1440'), isNull);

      expect(cookingTimeError('0'), isNotNull);
      expect(cookingTimeError('1441'), isNotNull);
      expect(cookingTimeError('half an hour'), isNotNull);
    });
  });
}
