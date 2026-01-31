import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

/// Serviço de legendas em tempo real usando sherpa-onnx.
/// 
/// Este serviço usa sherpa-onnx para reconhecimento de fala offline:
/// 1. Captura áudio do dispositivo via AudioCapturePlugin nativo
/// 2. Processa com Whisper em chunks de 3 segundos
/// 3. Retorna legendas em português
class StreamCaptionService extends ChangeNotifier {
  static final StreamCaptionService _instance = StreamCaptionService._internal();
  factory StreamCaptionService() => _instance;
  StreamCaptionService._internal();

  // Platform channels
  static const _methodChannel = MethodChannel('com.saimo.saimo_tv/audio_capture');
  static const _eventChannel = EventChannel('com.saimo.saimo_tv/caption_audio');
  StreamSubscription? _audioSubscription;
  
  // State
  bool _isListening = false;
  bool _modelLoaded = false;
  bool _isInitializing = false;
  String _currentText = '';
  String _partialText = '';
  String _statusMessage = '';
  double _downloadProgress = 0.0;
  bool _hasError = false;
  
  // Sherpa-onnx components
  sherpa_onnx.OfflineRecognizer? _recognizer;
  static const int _sampleRate = 16000;
  
  // Audio buffer for processing in chunks
  final List<double> _audioBuffer = [];
  static const int _bufferSize = _sampleRate * 3; // 3 seconds of audio
  Timer? _processTimer;
  bool _isProcessing = false;
  
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

  /// Initialize the sherpa-onnx model
  Future<void> initialize() async {
    if (_modelLoaded || _isInitializing) return;
    
    _isInitializing = true;
    _hasError = false;
    _setStatus('Preparando legenda...');
    notifyListeners();
    
    try {
      // Initialize sherpa-onnx bindings
      sherpa_onnx.initBindings();
      
      // Ensure model is downloaded
      final modelDir = await _ensureModelAvailable();
      if (modelDir == null) {
        throw Exception('Failed to download model');
      }
      
      // Create recognizer with offline Whisper model (supports Portuguese)
      final config = sherpa_onnx.OfflineRecognizerConfig(
        model: sherpa_onnx.OfflineModelConfig(
          whisper: sherpa_onnx.OfflineWhisperModelConfig(
            encoder: '$modelDir/tiny-encoder.int8.onnx',
            decoder: '$modelDir/tiny-decoder.int8.onnx',
            language: 'pt', // Portuguese
            task: 'transcribe',
          ),
          tokens: '$modelDir/tiny-tokens.txt',
          modelType: 'whisper',
          debug: false,
          numThreads: 2,
        ),
        ruleFsts: '',
      );
      
      _recognizer = sherpa_onnx.OfflineRecognizer(config);
      
      _modelLoaded = true;
      _setStatus('Pronto');
      debugPrint('✅ [Caption] Sherpa-onnx Whisper model initialized');
      
    } catch (e) {
      debugPrint('❌ [Caption] Init error: $e');
      _setStatus('Erro ao carregar modelo');
      _hasError = true;
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  /// Ensure the sherpa-onnx model is available
  Future<String?> _ensureModelAvailable() async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${appDir.path}/sherpa-onnx-whisper-tiny');
    
    if (await modelDir.exists()) {
      final encoderFile = File('${modelDir.path}/tiny-encoder.int8.onnx');
      if (await encoderFile.exists()) {
        debugPrint('[Caption] Model already downloaded');
        return modelDir.path;
      }
    }
    
    // Download the model
    return await _downloadModel(appDir.path);
  }

  /// Download the sherpa-onnx Whisper model
  Future<String?> _downloadModel(String destPath) async {
    _setStatus('Baixando modelo de voz...');
    
    // Using Whisper tiny int8 model (multilingual, supports Portuguese)
    final modelDir = Directory('$destPath/sherpa-onnx-whisper-tiny');
    await modelDir.create(recursive: true);
    
    final modelFiles = {
      'tiny-encoder.int8.onnx': 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny/resolve/main/tiny-encoder.int8.onnx',
      'tiny-decoder.int8.onnx': 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny/resolve/main/tiny-decoder.int8.onnx',
      'tiny-tokens.txt': 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny/resolve/main/tiny-tokens.txt',
    };
    
    try {
      int downloadedCount = 0;
      for (final entry in modelFiles.entries) {
        final fileName = entry.key;
        final url = entry.value;
        final filePath = '${modelDir.path}/$fileName';
        
        // Skip if already exists
        if (await File(filePath).exists()) {
          downloadedCount++;
          continue;
        }
        
        _setStatus('Baixando $fileName...');
        _downloadProgress = downloadedCount / modelFiles.length;
        notifyListeners();
        
        final response = await http.get(Uri.parse(url));
        if (response.statusCode != 200) {
          throw Exception('Failed to download $fileName: ${response.statusCode}');
        }
        
        await File(filePath).writeAsBytes(response.bodyBytes);
        downloadedCount++;
        debugPrint('[Caption] Downloaded: $fileName');
      }
      
      _downloadProgress = 1.0;
      _setStatus('Modelo instalado!');
      return modelDir.path;
      
    } catch (e) {
      debugPrint('[Caption] Download error: $e');
      _setStatus('Erro no download');
      _hasError = true;
      return null;
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
    
    // Start native audio capture
    try {
      final result = await _methodChannel.invokeMethod<bool>('startCapture');
      if (result != true) {
        debugPrint('[Caption] Failed to start audio capture');
        _setStatus('Erro ao capturar áudio');
        _hasError = true;
        notifyListeners();
        return;
      }
      debugPrint('✅ [Caption] Native audio capture started');
    } catch (e) {
      debugPrint('[Caption] Audio capture error: $e');
      _setStatus('Erro de permissão de áudio');
      _hasError = true;
      notifyListeners();
      return;
    }
    
    // Clear buffer
    _audioBuffer.clear();
    
    // Subscribe to audio from native plugin
    _audioSubscription?.cancel();
    _audioSubscription = _eventChannel.receiveBroadcastStream().listen(
      (data) {
        if (data is Uint8List) {
          _addAudioToBuffer(data);
        }
      },
      onError: (e) {
        debugPrint('[Caption] Audio stream error: $e');
      },
    );
    
    // Start periodic processing
    _processTimer?.cancel();
    _processTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _processBufferedAudio();
    });
    
    _isListening = true;
    _setStatus('Ouvindo...');
    _partialText = '...';
    notifyListeners();
    debugPrint('✅ [Caption] Started recognition');
  }

  /// Add audio data to buffer
  void _addAudioToBuffer(Uint8List audioData) {
    final samples = _convertBytesToFloat32(audioData);
    _audioBuffer.addAll(samples);
    
    // Keep buffer at reasonable size (max 30 seconds)
    const maxBufferSize = _sampleRate * 30;
    if (_audioBuffer.length > maxBufferSize) {
      _audioBuffer.removeRange(0, _audioBuffer.length - maxBufferSize);
    }
    
    // Update status when receiving audio
    if (_isListening && _partialText == '...') {
      _setStatus('Processando...');
    }
  }

  /// Process buffered audio 
  Future<void> _processBufferedAudio() async {
    if (!_isListening || !_modelLoaded || _recognizer == null) return;
    if (_isProcessing) return;
    if (_audioBuffer.length < _bufferSize) {
      debugPrint('[Caption] Buffer too small: ${_audioBuffer.length} < $_bufferSize');
      return;
    }
    
    _isProcessing = true;
    
    try {
      // Take samples from buffer
      final samplesToProcess = Float32List.fromList(
        _audioBuffer.take(_bufferSize).toList()
      );
      _audioBuffer.removeRange(0, _bufferSize);
      
      debugPrint('[Caption] Processing ${samplesToProcess.length} samples...');
      
      // Create stream and process
      final stream = _recognizer!.createStream();
      stream.acceptWaveform(samples: samplesToProcess, sampleRate: _sampleRate);
      _recognizer!.decode(stream);
      
      final result = _recognizer!.getResult(stream);
      final text = result.text.trim();
      
      stream.free();
      
      if (text.isNotEmpty && text != '<unk>' && text.length > 2) {
        _currentText = text;
        _partialText = '';
        
        _captionHistory.add(text);
        if (_captionHistory.length > 5) {
          _captionHistory.removeAt(0);
        }
        
        // Clear after delay
        _clearTimer?.cancel();
        _clearTimer = Timer(const Duration(seconds: 6), () {
          _currentText = '';
          _partialText = '';
          _setStatus('Ouvindo...');
          notifyListeners();
        });
        
        debugPrint('[Caption] TEXT: $text');
        notifyListeners();
      } else {
        debugPrint('[Caption] No speech detected in chunk');
      }
    } catch (e) {
      debugPrint('[Caption] Process error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// Convert 16-bit PCM bytes to Float32 samples
  Float32List _convertBytesToFloat32(Uint8List bytes) {
    final shortCount = bytes.length ~/ 2;
    final result = Float32List(shortCount);
    
    final byteData = ByteData.view(bytes.buffer);
    for (int i = 0; i < shortCount; i++) {
      final sample = byteData.getInt16(i * 2, Endian.little);
      result[i] = sample / 32768.0;
    }
    
    return result;
  }

  /// Stop captioning
  Future<void> stopCaptioning() async {
    if (!_isListening) return;
    
    // Stop native audio capture
    try {
      await _methodChannel.invokeMethod('stopCapture');
      debugPrint('[Caption] Native audio capture stopped');
    } catch (e) {
      debugPrint('[Caption] Error stopping capture: $e');
    }
    
    _audioSubscription?.cancel();
    _audioSubscription = null;
    _processTimer?.cancel();
    _processTimer = null;
    
    _isListening = false;
    _isProcessing = false;
    _audioBuffer.clear();
    _currentText = '';
    _partialText = '';
    _setStatus('');
    _clearTimer?.cancel();
    
    notifyListeners();
    debugPrint('[Caption] Stopped');
  }

  /// Reset the service
  void reset() {
    _currentText = '';
    _partialText = '';
    _captionHistory.clear();
    _audioBuffer.clear();
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
    _clearTimer?.cancel();
    _recognizer?.free();
    super.dispose();
  }
}
