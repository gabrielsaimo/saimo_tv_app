import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dart_chromecast/casting/cast_device.dart' as cast_lib;
import 'package:dart_chromecast/casting/cast_sender.dart';
import 'package:dart_chromecast/casting/cast_media.dart';
import 'package:dart_chromecast/utils/mdns_find_chromecast.dart' as discovery;
import 'package:dlna_dart/dlna.dart';

enum CastDeviceType {
  chromecast,
  dlna,
  fireTv, 
  other
}

class CastDevice {
  final String id;
  final String name;
  final String host;
  final int port;
  final CastDeviceType type;
  final dynamic originalDevice; 

  CastDevice({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.type,
    this.originalDevice,
  });
}

class CastingService extends ChangeNotifier {
  final List<CastDevice> _devices = [];
  List<CastDevice> get devices => List.unmodifiable(_devices);

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  CastDevice? _connectedDevice;
  CastDevice? get connectedDevice => _connectedDevice;

  CastSender? _castSender;
  DLNAManager? _dlnaManager;
  DeviceManager? _dlnaDeviceManager;
  
  static final CastingService _instance = CastingService._internal();
  factory CastingService() => _instance;
  CastingService._internal();

  /// Start scanning for devices (Chromecast & DLNA)
  Future<void> startDiscovery() async {
    if (_isScanning) return;
    
    _isScanning = true;
    _devices.clear();
    notifyListeners();

    debugPrint('Starting Casting Discovery...');

    // 1. Scan for Chromecast (One-shot, maybe loop or separate timer?)
    _scanChromecast();

    // 2. Scan for DLNA
    _scanDLNA();

    // Stop scanning after 30 seconds automatically
    Future.delayed(const Duration(seconds: 30), () {
      if (_isScanning) {
        stopDiscovery();
      }
    });
  }

  void stopDiscovery() {
    _isScanning = false;
    _dlnaManager?.stop(); // Stops DLNA listening
    notifyListeners();
  }

  Future<void> _scanChromecast() async {
    try {
      // The utility returns a list, it's not a stream.
      // We can run it once or periodically. Let's run it once.
      // Note: this function waits.
      final found = await discovery.find_chromecasts();
      
      for (var d in found) {
        if (!_devices.any((existing) => existing.host == d.ip && existing.port == d.port)) {
          // Convert discovery.CastDevice to casting.CastDevice for the Sender
          final libDevice = cast_lib.CastDevice(
            name: d.name,
            host: d.ip,
            port: d.port,
            type: '_googlecast._tcp', // Assuming type needed
          );

          final castDevice = CastDevice(
            id: '${d.ip}:${d.port}',
            name: d.name ?? 'Chromecast',
            host: d.ip ?? '',
            port: d.port ?? 8009,
            type: CastDeviceType.chromecast,
            originalDevice: libDevice,
          );
          _addDevice(castDevice);
        }
      }
    } catch (e) {
      debugPrint('Error scanning Chromecast: $e');
    }
  }

  Future<void> _scanDLNA() async {
    try {
      _dlnaManager ??= DLNAManager();
      // start() returns the DeviceManager which has the stream
      _dlnaDeviceManager = await _dlnaManager!.start();
      
      _dlnaDeviceManager!.devices.stream.listen((deviceMap) {
        for (var device in deviceMap.values) {
             // Basic heuristic: check if name implies FireTV
             CastDeviceType type = CastDeviceType.dlna;
             if (device.info.friendlyName.toLowerCase().contains('fire')) {
               type = CastDeviceType.fireTv;
             }

             final castDevice = CastDevice(
              id: device.info.URLBase, // Use URLBase as unique ID since UDN is not available
              name: device.info.friendlyName,
              host: device.info.URLBase, 
              port: 0, 
              type: type,
              originalDevice: device,
            );
            _addDevice(castDevice);
        }
      });
    } catch (e) {
      debugPrint('Error scanning DLNA: $e');
    }
  }

  void _addDevice(CastDevice device) {
    if (!_devices.any((d) => d.id == device.id)) {
      _devices.add(device);
      notifyListeners();
    }
  }

  /// Connect and Cast Media
  Future<void> castMedia({
    required CastDevice device,
    required String url,
    required String title,
    String? subtitle,
    String? mimeType,
    String? imageUrl,
  }) async {
    try {
      _connectedDevice = device;
      notifyListeners();

      if (device.type == CastDeviceType.chromecast) {
        await _castToChromecast(device.originalDevice, url, title, subtitle, mimeType, imageUrl);
      } else {
        await _castToDLNA(device.originalDevice, url, title, subtitle, mimeType, imageUrl);
      }
    } catch (e) {
      debugPrint('Error casting media: $e');
      disconnect();
      rethrow;
    }
  }

  Future<void> _castToChromecast(cast_lib.CastDevice device, String url, String title, String? subtitle, String? mimeType, String? imageUrl) async {
    _castSender = CastSender(device);
    
    final connected = await _castSender!.connect();
    if (connected) {
      // Load media
      final media = CastMedia(
        contentId: url,
        title: title,
        contentType: mimeType ?? 'video/mp4',
        images: imageUrl != null ? [imageUrl] : null,
      );
      
      _castSender!.load(media);
      // Play is typically automatic after load, but we can ensure
      // _castSender!.play(); 
    } else {
      throw Exception('Could not connect to Chromecast');
    }
  }

  Future<void> _castToDLNA(DLNADevice device, String url, String title, String? subtitle, String? mimeType, String? imageUrl) async {
    await device.setUrl(url, title: title);
    await device.play();
  }

  Future<void> disconnect() async {
    if (_connectedDevice != null) {
       if (_castSender != null) {
         try {
           _castSender!.disconnect();
         } catch (e) {
           debugPrint('Error disconnecting Chromecast: $e');
         }
         _castSender = null;
       }
       if (_dlnaManager != null && _connectedDevice!.originalDevice is DLNADevice) {
         try {
           await (_connectedDevice!.originalDevice as DLNADevice).stop();
         } catch (e) {
           debugPrint('Error stopping DLNA: $e');
         }
       }
       _connectedDevice = null;
       notifyListeners();
    }
  }
}
