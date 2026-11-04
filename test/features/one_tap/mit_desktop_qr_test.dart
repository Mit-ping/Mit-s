import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';
import 'package:hiddify/features/one_tap/mit_desktop_qr.dart';

Uint8List qrImage(String text) {
  final matrix = Encoder.encode(text, ErrorCorrectionLevel.m).matrix!;
  const scale = 5, quiet = 4;
  final image = img.Image(width: (matrix.width + quiet * 2) * scale, height: (matrix.height + quiet * 2) * scale);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  for (var y = 0; y < matrix.height; y++) {
    for (var x = 0; x < matrix.width; x++) {
      if (matrix.get(x, y) == 1) {
        img.fillRect(
          image,
          x1: (x + quiet) * scale,
          y1: (y + quiet) * scale,
          x2: (x + quiet + 1) * scale - 1,
          y2: (y + quiet + 1) * scale - 1,
          color: img.ColorRgb8(0, 0, 0),
        );
      }
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  test('desktop QR image decodes supported REALITY profile and rejects arbitrary links', () {
    const profile =
        'vless://11111111-1111-4111-8111-111111111111@example.com:443?security=reality&sni=example.com&fp=chrome&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&sid=abcd&type=tcp&flow=xtls-rprx-vision#Test';
    expect(decodeMitQrImage(qrImage(profile)), profile);
    expect(() => decodeMitQrImage(qrImage('https://example.com/login')), throwsFormatException);
  });
  test('desktop QR rejects invalid and oversized files before decoding', () {
    expect(() => decodeMitQrImage(Uint8List(0)), throwsFormatException);
    expect(() => decodeMitQrImage(Uint8List.fromList([0, 1, 2])), throwsFormatException);
    expect(() => decodeMitQrImage(Uint8List(8 * 1024 * 1024 + 1)), throwsFormatException);
  });
}
