import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kogo_voice_learning/core/constants/backend_config.dart';
import 'package:kogo_voice_learning/services/audio/eleven_labs_tts_service.dart';

class FakeHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> _headers = {};

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    _headers.putIfAbsent(name.toLowerCase(), () => []).add(value.toString());
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _headers[name.toLowerCase()] = [value.toString()];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeHttpResponse implements HttpClientResponse {
  @override
  final int statusCode;
  final List<int> _body;
  @override
  final HttpHeaders headers = FakeHttpHeaders();

  FakeHttpResponse(this.statusCode, this._body);

  @override
  int get contentLength => _body.length;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream.value(_body).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeHttpClientRequest implements HttpClientRequest {
  @override
  final Uri uri;
  final List<int> _capturedBody = [];
  final Completer<HttpClientResponse> _completer = Completer<HttpClientResponse>();
  @override
  final HttpHeaders headers = FakeHttpHeaders();
  @override
  int contentLength = 0;

  FakeHttpClientRequest(this.uri);


  @override
  void add(List<int> data) {
    _capturedBody.addAll(data);
  }

  @override
  Future<HttpClientResponse> close() async {
    return _completer.future;
  }

  void completeWith(int status, List<int> body) {
    _completer.complete(FakeHttpResponse(status, body));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeHttpClient implements HttpClient {
  FakeHttpClientRequest? lastRequest;
  int responseStatus = 200;
  List<int> responseBody = [1, 2, 3, 4];

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    final req = FakeHttpClientRequest(url);
    lastRequest = req;
    req.completeWith(responseStatus, responseBody);
    return req;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('BackendConfig & ElevenLabs Proxy Tests', () {
    test('BackendConfig produces valid apiBaseUrl and serverRootUrl', () {
      BackendConfig.setBaseUrl('http://192.168.1.50:4000');
      expect(BackendConfig.apiBaseUrl, equals('http://192.168.1.50:4000/api'));
      expect(BackendConfig.serverRootUrl, equals('http://192.168.1.50:4000'));

      BackendConfig.setBaseUrl('http://192.168.1.50:4000/api');
      expect(BackendConfig.apiBaseUrl, equals('http://192.168.1.50:4000/api'));
      expect(BackendConfig.serverRootUrl, equals('http://192.168.1.50:4000'));
    });

    test('ElevenLabsTtsService formats request payload and sends to backend proxy /voice/tts', () async {
      final fakeClient = FakeHttpClient();
      fakeClient.responseStatus = 200;
      fakeClient.responseBody = [10, 20, 30, 40];

      final ttsService = ElevenLabsTtsService(
        httpClient: fakeClient,
        baseUrl: 'http://127.0.0.1:4000/api',
      );

      final audioBytes = await ttsService.synthesizeSpeech('Halo Kogo');

      expect(audioBytes, isNotNull);
      expect(audioBytes!.length, equals(4));
      expect(fakeClient.lastRequest, isNotNull);
      expect(fakeClient.lastRequest!.uri.path, equals('/api/voice/tts'));

      final sentPayload = utf8.decode(fakeClient.lastRequest!._capturedBody);
      final json = jsonDecode(sentPayload) as Map<String, dynamic>;
      expect(json['text'], equals('Halo Kogo'));
      expect(json['voiceId'], isNotEmpty);
      expect(json['modelId'], isNotEmpty);
    });

    test('ElevenLabsTtsService caches previous responses to save backend quota', () async {
      final fakeClient = FakeHttpClient();
      final ttsService = ElevenLabsTtsService(
        httpClient: fakeClient,
        baseUrl: 'http://127.0.0.1:4000/api',
      );

      final audio1 = await ttsService.synthesizeSpeech('Belajar Membaca');
      expect(audio1, isNotNull);

      // Panggilan kedua untuk teks yang sama harus mengambil dari cache tanpa HTTP request baru
      fakeClient.lastRequest = null;
      final audio2 = await ttsService.synthesizeSpeech('Belajar Membaca');
      expect(audio2, isNotNull);
      expect(fakeClient.lastRequest, isNull); // Verifikasi cache hit
    });
  });
}
