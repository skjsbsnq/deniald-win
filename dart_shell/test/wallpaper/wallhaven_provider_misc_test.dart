import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:denial_dart_shell/src/wallpaper/providers/wallhaven_wallpaper_provider.dart';
import 'package:denial_dart_shell/src/wallpaper/wallpaper.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeHttpHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeSocket implements Socket {
  bool destroyed = false;

  @override
  void destroy() {
    destroyed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpClientResponse({this.statusCode = HttpStatus.ok}) {
    _body = StreamController<List<int>>(
      onListen: () => _bodySubscribed = true,
      onCancel: () {
        _bodySubscribed = false;
        if (!_bodyReleased.isCompleted) {
          _bodyReleased.complete();
        }
      },
    );
  }

  late final StreamController<List<int>> _body;
  final Completer<void> _bodyReleased = Completer<void>();
  final _FakeSocket socket = _FakeSocket();
  bool _bodySubscribed = false;

  @override
  final int statusCode;

  @override
  int contentLength = -1;

  int listenCalls = 0;
  int drainCalls = 0;
  int detachSocketCalls = 0;

  void emit(List<int> chunk) => _body.add(chunk);

  void closeBody() => _body.close();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    listenCalls += 1;
    return _body.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  Future<E> drain<E>([E? futureValue]) {
    drainCalls += 1;
    return super.drain<E>(futureValue);
  }

  @override
  Future<Socket> detachSocket() {
    detachSocketCalls += 1;
    // A real client only hands the socket over once the body subscription is
    // cancelled or finished; until then the parser still owns it.
    if (!_bodySubscribed) {
      return Future<Socket>.value(socket);
    }
    return _bodyReleased.future.then((_) => socket);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpClientRequest implements HttpClientRequest {
  final Completer<HttpClientResponse> _response =
      Completer<HttpClientResponse>();

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  bool aborted = false;

  void completeResponse(HttpClientResponse response) {
    if (!_response.isCompleted) {
      _response.complete(response);
    }
  }

  @override
  Future<HttpClientResponse> close() => _response.future;

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    aborted = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpClient implements HttpClient {
  final List<_FakeHttpClientRequest> requests = <_FakeHttpClientRequest>[];
  final Queue<_FakeHttpClientResponse> responses =
      Queue<_FakeHttpClientResponse>();
  Completer<void>? getUrlGate;
  bool closed = false;

  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    final request = _FakeHttpClientRequest();
    requests.add(request);
    if (responses.isNotEmpty) {
      request.completeResponse(responses.removeFirst());
    }
    final gate = getUrlGate;
    if (gate != null) {
      return gate.future.then((_) => request);
    }
    return Future<HttpClientRequest>.value(request);
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition was not met in time');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

WallpaperQuery _query() => const WallpaperQuery(
  text: 'mountain',
  page: 1,
  limit: 10,
  targetPixelSize: Size(1920, 1080),
);

WallpaperCandidate _candidate() => WallpaperCandidate(
  id: 'abc123',
  providerId: 'wallhaven',
  label: 'abc123',
  previewUri: Uri.parse('https://wallhaven.cc/w/abc123'),
  downloadUri: Uri.parse('https://wallhaven.cc/w/abc123.jpg'),
  width: 1920,
  height: 1080,
);

void main() {
  late Directory directory;
  late _FakeHttpClient client;
  late WallhavenWallpaperProvider provider;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('wallhaven-test');
    client = _FakeHttpClient();
    provider = WallhavenWallpaperProvider(
      downloadDirectory: directory,
      httpClient: client,
      requestTimeout: const Duration(milliseconds: 20),
      downloadTimeout: const Duration(milliseconds: 20),
    );
  });

  tearDown(() {
    provider.dispose();
    directory.deleteSync(recursive: true);
  });

  test('search aborts a request that produces no response in time', () async {
    await expectLater(
      provider.search(_query()),
      throwsA(isA<TimeoutException>()),
    );
    expect(client.requests.single.aborted, isTrue);
  });

  test(
    'search aborts a request that completes after the getUrl timeout',
    () async {
      client.getUrlGate = Completer<void>();
      await expectLater(
        provider.search(_query()),
        throwsA(isA<TimeoutException>()),
      );

      client.getUrlGate!.complete();
      await pumpEventQueue();
      expect(client.requests.single.aborted, isTrue);
    },
  );

  test('search drains a response that lands after the close timeout', () async {
    await expectLater(
      provider.search(_query()),
      throwsA(isA<TimeoutException>()),
    );

    final response = _FakeHttpClientResponse();
    client.requests.single.completeResponse(response);
    // The late response goes through the bounded drain; a body that never
    // ends hits the stream timeout and falls back to detach + destroy.
    await _waitFor(() => response.listenCalls == 1);
    await _waitFor(() => response.detachSocketCalls == 1);
    await pumpEventQueue();
    expect(response.socket.destroyed, isTrue);
  });

  test(
    'search releases an oversized response without reading the body',
    () async {
      final response = _FakeHttpClientResponse()
        ..contentLength = 3 * 1024 * 1024;
      client.responses.add(response);

      await expectLater(
        provider.search(_query()),
        throwsA(isA<FormatException>()),
      );
      await pumpEventQueue();
      expect(response.listenCalls, 0);
      expect(response.detachSocketCalls, 1);
      expect(response.socket.destroyed, isTrue);
    },
  );

  test('search falls back to releasing a stalled error-body drain', () async {
    final response = _FakeHttpClientResponse(statusCode: HttpStatus.badGateway);
    client.responses.add(response);

    await expectLater(provider.search(_query()), throwsA(isA<HttpException>()));
    await pumpEventQueue();
    expect(response.listenCalls, 1);
    expect(response.detachSocketCalls, 1);
    expect(response.socket.destroyed, isTrue);
  });

  test(
    'materialize releases an oversized response without reading the body',
    () async {
      final response = _FakeHttpClientResponse()
        ..contentLength = 65 * 1024 * 1024;
      client.responses.add(response);

      await expectLater(
        provider.materialize(_candidate()),
        throwsA(isA<FormatException>()),
      );
      await pumpEventQueue();
      expect(response.listenCalls, 0);
      expect(response.detachSocketCalls, 1);
      expect(response.socket.destroyed, isTrue);
    },
  );

  test('materialize drains a failed download response', () async {
    final response = _FakeHttpClientResponse(statusCode: HttpStatus.notFound);
    client.responses.add(response);

    final pending = provider.materialize(_candidate());
    response.emit(Uint8List(16));
    response.closeBody();
    await expectLater(pending, throwsA(isA<HttpException>()));
    expect(response.listenCalls, 1);
    expect(response.detachSocketCalls, 0);
  });

  test(
    'search releases the connection when the response body stalls',
    () async {
      final response = _FakeHttpClientResponse();
      client.responses.add(response);

      await expectLater(
        provider.search(_query()),
        throwsA(isA<TimeoutException>()),
      );
      await pumpEventQueue();
      expect(response.detachSocketCalls, 1);
      expect(response.socket.destroyed, isTrue);
    },
  );

  test('materialize releases the connection when the body stalls', () async {
    final response = _FakeHttpClientResponse();
    client.responses.add(response);

    await expectLater(
      provider.materialize(_candidate()),
      throwsA(isA<TimeoutException>()),
    );
    await pumpEventQueue();
    expect(response.detachSocketCalls, 1);
    expect(response.socket.destroyed, isTrue);
  });

  test('materialize releases the connection when the size cap trips', () async {
    final response = _FakeHttpClientResponse();
    client.responses.add(response);

    final pending = provider.materialize(_candidate());
    response.emit(Uint8List(65 * 1024 * 1024));
    await expectLater(pending, throwsA(isA<FormatException>()));
    expect(response.detachSocketCalls, 1);
  });
}
