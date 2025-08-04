import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:rxdart/rxdart.dart';

import '../auth/auth_service.dart';
import '../types/types.dart';
import '../utils/constants.dart';

class WebSocketClient {
  final AuthService authService;
  final String baseUrl;
  
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _manuallyDisconnected = false;
  int _reconnectAttempts = 0;
  
  final int _maxReconnectAttempts = 10;
  final int _reconnectInterval = 5000;
  final int _heartbeatInterval = 30000;
  
  // Event streams
  final _connectController = StreamController<void>.broadcast();
  final _disconnectController = StreamController<void>.broadcast();
  final _errorController = StreamController<PyAirtableException>.broadcast();
  final _messageController = StreamController<WebSocketMessage>.broadcast();
  
  Stream<void> get onConnect => _connectController.stream;
  Stream<void> get onDisconnect => _disconnectController.stream;
  Stream<PyAirtableException> get onError => _errorController.stream;
  Stream<WebSocketMessage> get onMessage => _messageController.stream;

  WebSocketClient({
    required this.authService,
    required this.baseUrl,
  });

  bool get isConnected => _isConnected;

  Future<void> connect() async {
    if (_isConnecting || _isConnected) return;

    if (!authService.isAuthenticated) {
      throw const PyAirtableException('Must be authenticated to connect to WebSocket');
    }

    _isConnecting = true;
    _manuallyDisconnected = false;

    try {
      final wsUrl = _buildWebSocketUrl();
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      
      await _channel!.ready;
      
      _setupListeners();
      _startHeartbeat();
      
      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;
      
      _connectController.add(null);
    } catch (error) {
      _isConnecting = false;
      throw NetworkException('Failed to connect to WebSocket: $error');
    }
  }

  void disconnect() {
    _manuallyDisconnected = true;
    _cleanup();
    
    _channel?.sink.close();
    _channel = null;
    
    _disconnectController.add(null);
  }

  void send(Map<String, dynamic> data) {
    if (!_isConnected || _channel == null) {
      throw const NetworkException('WebSocket is not connected');
    }

    try {
      _channel!.sink.add(jsonEncode(data));
    } catch (error) {
      throw NetworkException('Failed to send WebSocket message: $error');
    }
  }

  void subscribeToTable(String baseId, String tableId) {
    send({
      'type': 'subscribe',
      'data': {
        'baseId': baseId,
        'tableId': tableId,
      },
    });
  }

  void unsubscribeFromTable(String baseId, String tableId) {
    send({
      'type': 'unsubscribe',
      'data': {
        'baseId': baseId,
        'tableId': tableId,
      },
    });
  }

  String _buildWebSocketUrl() {
    final wsProtocol = baseUrl.startsWith('https') ? 'wss' : 'ws';
    final wsBaseUrl = baseUrl.replaceFirst(RegExp(r'^https?'), wsProtocol);
    
    final tokens = authService.tokens;
    if (tokens?.accessToken == null) {
      throw const PyAirtableException('No access token available');
    }

    final uri = Uri.parse('$wsBaseUrl${ApiEndpoints.websocket}');
    return uri.replace(queryParameters: {
      'token': tokens!.accessToken,
    }).toString();
  }

  void _setupListeners() {
    _subscription = _channel!.stream.listen(
      (data) {
        try {
          final message = WebSocketMessage.fromJson(jsonDecode(data as String));
          _messageController.add(message);
        } catch (error) {
          _errorController.add(const PyAirtableException('Invalid WebSocket message'));
        }
      },
      onError: (error) {
        _errorController.add(NetworkException('WebSocket error: $error'));
      },
      onDone: () {
        _cleanup();
        
        if (!_manuallyDisconnected) {
          _disconnectController.add(null);
          _scheduleReconnect();
        }
      },
    );
  }

  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(
      Duration(milliseconds: _heartbeatInterval),
      (_) {
        if (_isConnected) {
          send({'type': 'ping'});
        }
      },
    );
  }

  void _scheduleReconnect() {
    if (_manuallyDisconnected || _reconnectAttempts >= _maxReconnectAttempts) {
      return;
    }

    _reconnectAttempts++;
    
    final delay = (_reconnectInterval * (1 << (_reconnectAttempts - 1))).clamp(0, 30000);

    _reconnectTimer = Timer(Duration(milliseconds: delay), () async {
      try {
        await connect();
      } catch (error) {
        _errorController.add(error is PyAirtableException 
            ? error 
            : PyAirtableException(error.toString()));
        _scheduleReconnect();
      }
    });
  }

  void _cleanup() {
    _isConnected = false;
    _isConnecting = false;
    
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    
    _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    _manuallyDisconnected = true;
    _cleanup();
    
    _channel?.sink.close();
    _channel = null;
    
    _connectController.close();
    _disconnectController.close();
    _errorController.close();
    _messageController.close();
  }
}