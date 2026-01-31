import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

/// Serviço de legendas em tempo real usando Vosk nativo.
/// 
/// Este serviço usa um plugin Android nativo que:
/// 1. Captura áudio diretamente do ExoPlayer (não do microfone)
/// 2. Processa com Vosk para transcrição em tempo real
/// 3. Retorna legendas via EventChannel
class StreamCaptionService extends ChangeNotifier {
  static final StreamCaptionService _instance = StreamCaptionService._internal();
  factory StreamCaptionService() => _instance;
  StreamCaptionService._internal();

  // Platform channels
  static const _methodChannel = MethodChannel('com.saimo.saimo_tv/vosk_caption');
  static const _eventChannel = EventChannel('com.saimo.saimo_tv/vosk_results');
  
  // State
  bool _isListening = false;
  bool _modelLoaded = false;
  bool _isInitializing = false;
  String _currentText = '';
  String _partialText = '';
  String _statusMessage = '';
  double _downloadProgress = 0.0;
  bool _hasError = false;
  
  // Event subscription
  StreamSubscription? _eventSubscription;
  
  // Caption timing
  Timer? _clearTimer;
  final List<String> _captionHistory = [];
  
  // Getters
  bool get isListening => _isListening;
  bool get modelReady => _modelLoaded;
  bool get hasError => _hasError;
  String get currentText => _currentText.isNotEmpty ? _currentText : _partialText;
  String get statusMessage => _statusMessage;
  double get downloadProgress => _downloadProgress;

  /// Initialize the Vosk model
  Future<void> initialize() async {
    if (_modelLoaded || _isInitializing) return;
    
    _isInitializing = true;
    _hasError = false;
    _setStatus('Preparando legenda...');
    notifyListeners();
    
    try {
      // Subscribe to events from native
      _eventSubscription?.cancel();
      _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
        _handleNativeEvent,
        onError: (e) {
          debugPrint('[Caption] Event error: $e');
          _hasError = true;
          _setStatus('Erro');
          notifyListeners();
        },
      );
      
      // Check if model needs to be downloaded to assets
      await _ensureModelAvailable();
      
      // Initialize the native model
      final result = await _methodChannel.invokeMethod<bool>('initModel');
      
      if (result == true) {
        _modelLoaded = true;
        _setStatus('Pronto');
        debugPrint('✅ [Caption] Model initialized');
      } else {
        throw Exception('Failed to initialize model');
      }
      
    } catch (e) {
      debugPrint('❌ [Caption] Init error: $e');
      _setStatus('Erro ao carregar modelo');
      _hasError = true;
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  /// Ensure the Vosk model is available in the app
  Future<void> _ensureModelAvailable() async {
    // The model should be bundled in assets or downloaded
    // For now, we'll try to download it to the documents directory
    // and let the native code unpack it from there
    
    final appDir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${appDir.path}/vosk-model-small-pt-0.3');
    
    if (await modelDir.exists()) {
      final files = await modelDir.list().toList();
      if (files.isNotEmpty) {
        debugPrint('[Caption] Model already downloaded');
        return;
      }
    }
    
    // Download the model
    await _downloadModel(appDir.path);
  }

  /// Download the Vosk Portuguese model
  Future<void> _downloadModel(String destPath) async {
    _setStatus('Baixando modelo de voz...');
    const url = 'https://alphacephei.com/vosk/models/vosk-model-small-pt-0.3.zip';
    
    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);
      
      if (response.statusCode != 200) {
        throw Exception('Download failed: ${response.statusCode}');
      }
      
      final contentLength = response.contentLength ?? 0;
      final bytes = <int>[];
      int received = 0;
      
      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
        received += chunk.length;
        
        if (contentLength > 0) {
          _downloadProgress = received / contentLength;
          _setStatus('Baixando modelo... ${(_downloadProgress * 100).toStringAsFixed(0)}%');
        }
      }
      
      _setStatus('Instalando modelo...');
      
      final archive = ZipDecoder().decodeBytes(Uint8List.fromList(bytes));
      
      for (final file in archive) {
        final filename = '$destPath/${file.name}';
        if (file.isFile) {
          final outFile = File(filename);
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
        } else {
          await Directory(filename).create(recursive: true);
        }
      }
      
      client.close();
      _downloadProgress = 1.0;
      _setStatus('Modelo instalado!');
      
    } catch (e) {
      _setStatus('Erro no download');
      _hasError = true;
      rethrow;
    }
  }

  /// Handle events from native code
  void _handleNativeEvent(dynamic event) {
    if (event is Map) {
      final type = event['type'] as String?;
      final data = event['data'] as String?;
      
      if (type == null || data == null) return;
      
      switch (type) {
        case 'final':
          _currentText = data;
          _partialText = '';
          
          _captionHistory.add(data);
          if (_captionHistory.length > 5) {
            _captionHistory.removeAt(0);
          }
          
          _clearTimer?.cancel();
          _clearTimer = Timer(const Duration(seconds: 5), () {
            _currentText = '';
            _partialText = '';
            notifyListeners();
          });
          
          notifyListeners();
          debugPrint('[Caption] FINAL: $data');
          break;
          
        case 'partial':
          _partialText = data;
          notifyListeners();
          break;
          
        case 'status':
          _setStatus(data);
          break;
          
        case 'modelLoaded':
          _modelLoaded = true;
          notifyListeners();
          break;
          
        case 'error':
          debugPrint('[Caption] Native error: $data');
          _hasError = true;
          _setStatus('Erro: $data');
          notifyListeners();
          break;
      }
    }
  }

  /// Start captioning
  Future<void> startCaptioning(String streamUrl) async {
    if (_isListening) return;
    
    _hasError = false;
    
    // Initialize if not done
    if (!_modelLoaded) {
      await initialize();
      if (!_modelLoaded) {
        debugPrint('[Caption] Model not available, captioning disabled');
        return;
      }
    }
    
    try {
      final result = await _methodChannel.invokeMethod<bool>('startRecognition');
      
      if (result == true) {
        _isListening = true;
        _setStatus('Ouvindo...');
        notifyListeners();
        debugPrint('✅ [Caption] Started recognition');
      }
    } catch (e) {
      debugPrint('❌ [Caption] Start error: $e');
      _hasError = true;
      _setStatus('Erro ao iniciar');
      notifyListeners();
    }
  }

  /// Process audio data from the video player
  /// This should be called with PCM audio chunks
  Future<void> processAudio(Uint8List audioData) async {
    if (!_isListening || !_modelLoaded) return;
    
    try {
      await _methodChannel.invokeMethod('processAudio', {'audio': audioData});
    } catch (e) {
      debugPrint('[Caption] Process error: $e');
    }
  }

  /// Stop captioning
  Future<void> stopCaptioning() async {
    if (!_isListening) return;
    
    try {
      await _methodChannel.invokeMethod('stopRecognition');
      
      _isListening = false;
      _currentText = '';
      _partialText = '';
      _setStatus('');
      
      notifyListeners();
      debugPrint('[Caption] Stopped');
    } catch (e) {
      debugPrint('[Caption] Stop error: $e');
    }
  }

  /// Reset the service
  void reset() {
    _currentText = '';
    _partialText = '';
    _captionHistory.clear();
    _clearTimer?.cancel();
    notifyListeners();
  }

  void _setStatus(String msg) {
    _statusMessage = msg;
    notifyListeners();
  }

  @override
  void dispose() {
    stopCaptioning();
    _eventSubscription?.cancel();
    _clearTimer?.cancel();
    super.dispose();
  }
}
