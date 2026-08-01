import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

import '../config/experiment_config.dart';
import '../models/device_environment.dart';

/// Coleta os metadados reais do dispositivo via `device_info_plus`, para
/// registro junto a cada resultado (reprodutibilidade e comparação entre
/// dispositivos). Fica separado de `models/device_environment.dart` para
/// manter o modelo testável sem plugins de plataforma.
Future<DeviceEnvironment> collectDeviceEnvironment() async {
  final plugin = DeviceInfoPlugin();
  String manufacturer;
  String model;
  String operatingSystemVersion;

  if (Platform.isAndroid) {
    final info = await plugin.androidInfo;
    manufacturer = info.manufacturer;
    model = info.model;
    operatingSystemVersion = 'Android ${info.version.release} '
        '(SDK ${info.version.sdkInt})';
  } else if (Platform.isIOS) {
    final info = await plugin.iosInfo;
    manufacturer = 'Apple';
    model = info.utsname.machine;
    operatingSystemVersion = '${info.systemName} ${info.systemVersion}';
  } else {
    manufacturer = 'Desconhecido';
    model = Platform.operatingSystem;
    operatingSystemVersion = Platform.operatingSystemVersion;
  }

  return DeviceEnvironment(
    deviceLabel: DeviceEnvironment.buildLabel(
      model: model,
      operatingSystemVersion: operatingSystemVersion,
    ),
    manufacturer: manufacturer,
    model: model,
    operatingSystemVersion: operatingSystemVersion,
    flutterVersion: flutterVersionForRecordKeeping,
    dartVersion: Platform.version.split(' ').first,
  );
}
