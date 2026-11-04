import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';
import 'package:hiddify/features/one_tap/vpn_profile.dart';

String decodeMitQrImage(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024) throw const FormatException('QR-01');
  try {
    final decoder = img.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (info == null || info.width <= 0 || info.height <= 0 || info.width * info.height > 16000000) {
      throw const FormatException('QR-02');
    }
    final image = decoder!.decodeFrame(0);
    if (image == null) throw const FormatException('QR-02');
    final source = RGBLuminanceSource(
      image.width,
      image.height,
      image.convert(numChannels: 4).getBytes(order: img.ChannelOrder.abgr).buffer.asInt32List(),
    );
    final bitmap = BinaryBitmap(HybridBinarizer(source));
    final value = QRCodeReader().decode(bitmap).text;
    prepareVpnProfile(value);
    return value;
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('QR-03');
  }
}

Future<String?> pickMitQrImage() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['png', 'jpg', 'jpeg', 'bmp'],
    allowMultiple: false,
  );
  if (result == null) return null;
  final picked = result.files.single;
  if (picked.size > 8 * 1024 * 1024 || picked.path == null) throw const FormatException('QR-01');
  final file = File(picked.path!);
  if (await file.length() > 8 * 1024 * 1024) throw const FormatException('QR-01');
  return compute(decodeMitQrImage, await file.readAsBytes());
}
