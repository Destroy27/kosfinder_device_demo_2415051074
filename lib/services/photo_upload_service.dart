import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../cloud_config.dart';

class PhotoUploadResult {
  const PhotoUploadResult(this.storagePath, this.publicUrl);
  final String storagePath;
  final String publicUrl;
}

/// Kegagalan jaringan yang pesannya layak ditampilkan ke pengguna.
/// Dipisahkan agar pesan teknis SocketException tidak muncul di layar.
class UploadFailure implements Exception {
  const UploadFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Layanan ini HANYA dipanggil jika mahasiswa memilih praktik cloud.
class PhotoUploadService {
  static const _bucket = 'kosfinder-demo';
  static const _networkTimeout = Duration(seconds: 20);

  Future<PhotoUploadResult> upload(File photo) async {
    if (!CloudConfig.enabled) {
      throw StateError(
        'Supabase belum dikonfigurasi. Jalankan dengan --dart-define '
        'atau gunakan Simpan Draft Lokal.',
      );
    }

    final client = Supabase.instance.client;
    // Anonymous Sign-In bukan tanpa otorisasi: ini membuat auth.uid() unik.
    if (client.auth.currentUser == null) {
      await _guardNetwork(client.auth.signInAnonymously());
    }
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Sesi anonymous Supabase tidak berhasil dibuat.');
    }

    final ext = photo.path.split('.').last.toLowerCase();
    if (!{'jpg', 'jpeg', 'png'}.contains(ext)) {
      throw const FormatException('Format foto tidak didukung.');
    }
    if (await photo.length() > 5 * 1024 * 1024) {
      throw const FormatException('Ukuran foto maksimal 5 MB.');
    }

    // Policy Storage mengizinkan tulis HANYA di folder milik auth.uid().
    final objectPath = '$userId/${DateTime.now().microsecondsSinceEpoch}.$ext';
    await _guardNetwork(
      client.storage.from(_bucket).upload(
            objectPath,
            photo,
            fileOptions: FileOptions(
              upsert: false,
              contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
            ),
          ),
    );
    // Respons Storage API mengembalikan Key yang sudah berisi nama bucket,
    // misalnya "kosfinder-demo/<uid>/<file>.png". Karena getPublicUrl()
    // menambahkan bucket lagi, URL publik dibentuk dari objectPath agar
    // tidak menjadi "kosfinder-demo/kosfinder-demo/...".
    final publicUrl = client.storage.from(_bucket).getPublicUrl(objectPath);
    return PhotoUploadResult(objectPath, publicUrl);
  }

  /// Membatasi waktu tunggu dan menerjemahkan gangguan jaringan menjadi
  /// pesan yang bisa dibaca pengguna, bukan teks SocketException mentah.
  Future<T> _guardNetwork<T>(Future<T> request) async {
    try {
      return await request.timeout(_networkTimeout);
    } on TimeoutException {
      throw const UploadFailure(
        'Supabase tidak merespons dalam 20 detik. Periksa koneksi internet, '
        'lalu coba unggah lagi.',
      );
    } catch (error) {
      final text = error.toString();
      if (text.contains('SocketException') ||
          text.contains('Failed host lookup') ||
          text.contains('Network is unreachable') ||
          text.contains('Connection refused')) {
        throw const UploadFailure(
          'Tidak ada koneksi internet ke Supabase. Periksa jaringan, '
          'lalu coba unggah lagi.',
        );
      }
      rethrow;
    }
  }
}
