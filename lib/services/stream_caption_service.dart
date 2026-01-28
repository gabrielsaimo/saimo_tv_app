import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:vosk_flutter/vosk_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

class StreamCaptionService extends ChangeNotifier {
  static final StreamCaptionService _instance = StreamCaptionService._internal();
  factory StreamCaptionService() => _instance;
  StreamCaptionService._internal();

  Recognizer? _recognizer;
  Model? _model;
  SpeechService? _speechService;
  
  bool _isInitializing = false;
  bool _isListening = false;
  String _currentText = '';
  String _statusMessage = '';

  bool get isListening => _isListening;
  String get currentText => _currentText;
  String get statusMessage => _statusMessage;

  Future<void> initialize() async {
    if (_model != null) return;
    if (_isInitializing) return;

    _isInitializing = true;
    _setStatus('Preparando legenda...');

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelPath = '${appDir.path}/vosk-model-small-pt-0.3';
      final modelDir = Directory(modelPath);

      if (!await modelDir.exists()) {
        await _downloadAndUnzipModel(appDir.path);
      }

      final vosk = VoskFlutterPlugin.instance();
      _model = await vosk.createModel(modelPath);
      // Sample rate 16k is standard for Vosk models, but Mic usually 16k or 44k
      // Vosk plugin usually handles resampling if initialized via initSpeechService?
      // initSpeechService takes recognizer. The recognizer sample rate must match.
      // We'll stick to 16000.
      _recognizer = await vosk.createRecognizer(model: _model!, sampleRate: 16000);
      
      _speechService = await vosk.initSpeechService(_recognizer!);
      _speechService!.onPartial().listen((partial) => _parseVoskResult(partial, isPartial: true));
      _speechService!.onResult().listen((result) => _parseVoskResult(result));
      
      _setStatus('Pronto.');
    } catch (e) {
      debugPrint('Erro init Vosk: $e');
      _setStatus('Erro: $e');
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  Future<void> _downloadAndUnzipModel(String destPath) async {
    _setStatus('Baixando modelo de voz (30MB)...');
    const url = 'https://alphacephei.com/vosk/models/vosk-model-small-pt-0.3.zip';
    
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        _setStatus('Instalando modelo...');
        final bytes = response.bodyBytes;
        final archive = ZipDecoder().decodeBytes(bytes);

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
      } else {
         throw Exception('Falha download: ${response.statusCode}');
      }
    } catch (e) {
       _setStatus('Erro: $e');
       rethrow;
    }
  }

  /// Inicia a legenda (Microfone)
  /// O parametro streamUrl é ignorado pois usamos Mic agora
  Future<void> startCaptioning(String streamUrl) async {
    if (_isListening) return;
    
    // Solicita permissão de Mic
    if (await Permission.microphone.request().isDenied) {
      _setStatus('Permissão de microfone negada.');
      return;
    }

    if (_model == null) {
      await initialize();
    }
    
    if (_speechService == null) {
      _setStatus('Falha no serviço de voz.');
      return;
    }

    try {
      await _speechService!.start();
      _isListening = true;
      _setStatus('Ouvindo...');
      notifyListeners();
    } catch (e) {
      debugPrint('Erro start: $e');
      _setStatus('Erro ao iniciar.');
    }
  }

  Future<void> stopCaptioning() async {
    if (!_isListening) return;
    try {
      await _speechService?.stop();
      _isListening = false;
      notifyListeners();
    } catch (e) {
      debugPrint('Erro stop: $e');
    }
  }
  
  void _parseVoskResult(String jsonStr, {bool isPartial = false}) {
     // Vosk retorna JSON string
     // Simple regex parse
     var text = '';
     if (isPartial) {
        final match = RegExp(r'"partial"\s*:\s*"(.*)"').firstMatch(jsonStr);
        if (match != null) text = match.group(1) ?? '';
     } else {
        final match = RegExp(r'"text"\s*:\s*"(.*)"').firstMatch(jsonStr);
        if (match != null) text = match.group(1) ?? '';
     }
     
     if (text.isNotEmpty) {
       _currentText = text;
       notifyListeners();
       
       if (!isPartial) {
          Future.delayed(const Duration(seconds: 4), () {
             if (_currentText == text) {
                _currentText = '';
                notifyListeners();
             }
          });
       }
     }
  }
  
  void _setStatus(String msg) {
    _statusMessage = msg;
    notifyListeners();
  }
}
