import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Streaming authenticated backup container for Owntend (`.owntend-backup`).
///
/// Format v1 (all multi-byte integers little-endian):
///
/// ```text
/// offset  size  field
/// 0       8     magic "OWNTDBK1"
/// 8       1     kdfId        (0x01 = Argon2id)
/// 9       1     aeadId       (0x01 = AES-256-GCM)
/// 10      16    salt
/// 26      4     argonMemoryKiB
/// 30      4     argonIterations
/// 34      1     argonParallelism
/// 35      4     chunkSize    (plaintext bytes per AEAD frame)
/// 39      12    baseNonce
/// 51      1     keyGuard     (0x00 = user passphrase, 0x01 = device key)
/// ```
///
/// The payload is a sequence of frames `[uint32 ciphertextLength][ciphertext +
/// 16-byte GCM tag]`. Every frame is authenticated with
/// `AAD = header || uint64LE(frameIndex)` and a per-frame nonce derived from
/// the base nonce (`baseNonce XOR uint64LE(frameIndex)` in the first 8 bytes).
/// The header itself participates in every frame's AAD, so any tampering with
/// the plaintext KDF parameters or key-guard class fails authentication before
/// use.
///
/// The FIRST frame's plaintext is always the JSON manifest. All remaining
/// frames are raw payload bytes: the database snapshot followed by each media
/// entry, in manifest order.
class BackupContainerCodec {
  BackupContainerCodec._();

  static const List<int> magic = $magicBytes;
  static const int kdfIdArgon2id = 1;
  static const int aeadIdAes256Gcm = 1;
  static const int headerLength = 52;
  static const int keyGuardUserPassphrase = 0x00;
  static const int keyGuardDeviceKey = 0x01;
  static const int tagLength = 16;
  static const int maxChunkSize = 4 * 1024 * 1024;

  /// Hostile-input caps for untrusted headers before any key derivation or
  /// allocation happens. Production writers use smaller, profiled values.
  static const int maxAcceptedKdfMemoryKiB = 512 * 1024;
  static const int maxAcceptedKdfIterations = 16;
  static const int maxAcceptedParallelism = 8;

  /// Default production KDF profile. Device profiling may adjust these; they
  /// are recorded in every file's header so restores are self-describing.
  static const int defaultKdfMemoryKiB = 19 * 1024; // 19 MiB (OWASP floor)
  static const int defaultKdfIterations = 2;
  static const int defaultKdfParallelism = 1;
  static const int defaultChunkSize = 1024 * 1024;

  /// Fast profile used by tests and low-power devices.
  static const int testKdfMemoryKiB = 8 * 1024;
  static const int testKdfIterations = 1;

  static final AesGcm _aead = AesGcm.with256bits();
}

const List<int> $magicBytes = <int>[
  0x4f,
  0x57,
  0x4e,
  0x54,
  0x44,
  0x42,
  0x4b,
  0x31, // "OWNTDBK1"
];

/// Parsed, policy-checked header of an `.owntend-backup` file.
class BackupContainerHeader {
  const BackupContainerHeader({
    required this.kdfId,
    required this.aeadId,
    required this.salt,
    required this.kdfMemoryKiB,
    required this.kdfIterations,
    required this.kdfParallelism,
    required this.chunkSize,
    required this.baseNonce,
    required this.keyGuard,
  });

  final int kdfId;
  final int aeadId;
  final Uint8List salt;
  final int kdfMemoryKiB;
  final int kdfIterations;
  final int kdfParallelism;
  final int chunkSize;
  final Uint8List baseNonce;
  final int keyGuard;

  Uint8List encode() {
    final out = BytesBuilder(copy: false);
    out.add(BackupContainerCodec.magic);
    out.addByte(kdfId);
    out.addByte(aeadId);
    out.add(salt);
    final mem = ByteData(4)..setUint32(0, kdfMemoryKiB, Endian.little);
    final iters = ByteData(4)..setUint32(0, kdfIterations, Endian.little);
    out.add(mem.buffer.asUint8List());
    out.add(iters.buffer.asUint8List());
    out.addByte(kdfParallelism);
    final chunk = ByteData(4)..setUint32(0, chunkSize, Endian.little);
    out.add(chunk.buffer.asUint8List());
    out.add(baseNonce);
    out.addByte(keyGuard);
    return out.toBytes();
  }

  /// Parses and validates an untrusted header BEFORE any key derivation or
  /// large allocation. Throws [BackupContainerFormatException] on anything
  /// unexpected so hostile inputs fail closed and cheaply.
  factory BackupContainerHeader.decode(List<int> bytes) {
    if (bytes.length != BackupContainerCodec.headerLength) {
      throw const BackupContainerFormatException('bad header length');
    }
    for (var i = 0; i < BackupContainerCodec.magic.length; i++) {
      if (bytes[i] != BackupContainerCodec.magic[i]) {
        throw const BackupContainerFormatException('not an Owntend backup');
      }
    }
    final kdfId = bytes[8];
    if (kdfId != BackupContainerCodec.kdfIdArgon2id) {
      throw const BackupContainerFormatException('unsupported KDF');
    }
    final aeadId = bytes[9];
    if (aeadId != BackupContainerCodec.aeadIdAes256Gcm) {
      throw const BackupContainerFormatException('unsupported cipher');
    }
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final salt = Uint8List.fromList(bytes.sublist(10, 26));
    final kdfMemoryKiB = data.getUint32(26, Endian.little);
    final kdfIterations = data.getUint32(30, Endian.little);
    final kdfParallelism = bytes[34];
    final chunkSize = data.getUint32(35, Endian.little);
    final baseNonce = Uint8List.fromList(bytes.sublist(39, 51));
    final keyGuard = bytes[51];

    if (kdfMemoryKiB == 0 ||
        kdfMemoryKiB > BackupContainerCodec.maxAcceptedKdfMemoryKiB) {
      throw const BackupContainerFormatException('KDF memory out of range');
    }
    if (kdfIterations == 0 ||
        kdfIterations > BackupContainerCodec.maxAcceptedKdfIterations) {
      throw const BackupContainerFormatException('KDF iterations out of range');
    }
    if (kdfParallelism == 0 ||
        kdfParallelism > BackupContainerCodec.maxAcceptedParallelism) {
      throw const BackupContainerFormatException(
        'KDF parallelism out of range',
      );
    }
    if (chunkSize == 0 || chunkSize > BackupContainerCodec.maxChunkSize) {
      throw const BackupContainerFormatException('chunk size out of range');
    }
    if (keyGuard != BackupContainerCodec.keyGuardUserPassphrase &&
        keyGuard != BackupContainerCodec.keyGuardDeviceKey) {
      throw const BackupContainerFormatException('unknown key guard class');
    }
    return BackupContainerHeader(
      kdfId: kdfId,
      aeadId: aeadId,
      salt: salt,
      kdfMemoryKiB: kdfMemoryKiB,
      kdfIterations: kdfIterations,
      kdfParallelism: kdfParallelism,
      chunkSize: chunkSize,
      baseNonce: baseNonce,
      keyGuard: keyGuard,
    );
  }

  Future<SecretKey> deriveKey(String passphrase) async {
    final argon2 = Argon2id(
      parallelism: kdfParallelism.clamp(1, 8),
      iterations: kdfIterations.clamp(1, 16),
      memory: kdfMemoryKiB.clamp(
        1024,
        BackupContainerCodec.maxAcceptedKdfMemoryKiB,
      ),
      hashLength: 32,
    );
    return argon2.deriveKeyFromPassword(password: passphrase, nonce: salt);
  }

  List<int> frameNonce(int frameIndex) {
    final counter = ByteData(8)..setUint64(0, frameIndex, Endian.little);
    final nonce = Uint8List.fromList(baseNonce);
    for (var i = 0; i < 8; i++) {
      nonce[i] ^= counter.getUint8(i);
    }
    return nonce;
  }

  List<int> frameAad(int frameIndex) {
    final counter = ByteData(8)..setUint64(0, frameIndex, Endian.little);
    return [...encode(), ...counter.buffer.asUint8List()];
  }
}

class BackupContainerFormatException implements Exception {
  const BackupContainerFormatException(this.message);

  final String message;

  @override
  String toString() => 'BackupContainerFormatException: $message';
}

/// Streaming writer producing an authenticated `.owntend-backup` container.
class BackupContainerWriter {
  BackupContainerWriter._({
    required this.header,
    required this.key,
    required this.sink,
  });

  static Future<BackupContainerWriter> start({
    required RandomAccessFile output,
    required String passphrase,
    required int keyGuard,
    bool fastProfile = false,
  }) async {
    final rand = _secureRandom(28); // 16-byte salt + 12-byte base nonce
    final salt = Uint8List.sublistView(rand, 0, 16);
    final baseNonce = Uint8List.sublistView(rand, 16, 28);
    final header = BackupContainerHeader(
      kdfId: BackupContainerCodec.kdfIdArgon2id,
      aeadId: BackupContainerCodec.aeadIdAes256Gcm,
      salt: salt,
      kdfMemoryKiB: fastProfile
          ? BackupContainerCodec.testKdfMemoryKiB
          : BackupContainerCodec.defaultKdfMemoryKiB,
      kdfIterations: fastProfile
          ? BackupContainerCodec.testKdfIterations
          : BackupContainerCodec.defaultKdfIterations,
      kdfParallelism: BackupContainerCodec.defaultKdfParallelism,
      chunkSize: fastProfile
          ? 256 * 1024
          : BackupContainerCodec.defaultChunkSize,
      baseNonce: baseNonce,
      keyGuard: keyGuard,
    );
    final key = await header.deriveKey(passphrase);
    await output.setPosition(0);
    await output.writeFrom(header.encode());
    return BackupContainerWriter._(header: header, key: key, sink: output);
  }

  final BackupContainerHeader header;
  final SecretKey key;
  final RandomAccessFile sink;
  int _frameIndex = 0;

  /// Encrypts one complete logical record (e.g. the manifest) as exactly one
  /// frame. Records larger than the chunk size are rejected because readers
  /// enforce a hard bound on the manifest frame.
  Future<void> writeFrame(List<int> plaintext) async {
    await _writeFrames(Stream.value(plaintext), singleFrame: true);
  }

  /// Streams [source] through chunked AEAD frames until EOF.
  Future<void> writeStream(Stream<List<int>> source) async {
    await _writeFrames(source);
  }

  Future<void> _writeFrames(
    Stream<List<int>> source, {
    bool singleFrame = false,
  }) async {
    final buffer = BytesBuilder(copy: true);
    var buffered = 0;
    await for (final chunk in source) {
      if (chunk.isEmpty) continue;
      buffer.add(chunk);
      buffered += chunk.length;
      while (!singleFrame && buffered >= header.chunkSize) {
        final frame = buffer.takeBytes();
        final take = frame.sublist(0, header.chunkSize);
        final rest = frame.sublist(header.chunkSize);
        await _emitFrame(take);
        buffer.add(rest);
        buffered = rest.length;
      }
    }
    if (buffered > 0) {
      await _emitFrame(buffer.takeBytes());
    } else if (singleFrame && buffered == 0) {
      await _emitFrame(const []);
    }
  }

  Future<void> _emitFrame(List<int> plaintext) async {
    if (plaintext.length > header.chunkSize) {
      throw StateError('frame exceeds negotiated chunk size');
    }
    final secretBox = await BackupContainerCodec._aead.encrypt(
      plaintext,
      secretKey: key,
      nonce: header.frameNonce(_frameIndex),
      aad: header.frameAad(_frameIndex),
    );
    final lenPrefix = ByteData(4)
      ..setUint32(0, secretBox.cipherText.length, Endian.little);
    await sink.writeFrom(lenPrefix.buffer.asUint8List());
    await sink.writeFrom(secretBox.cipherText);
    await sink.writeFrom(secretBox.mac.bytes);
    _frameIndex++;
  }

  /// Best-effort key material destruction.
  void destroyKey() {
    try {
      key.destroy();
    } on Object {
      // Best effort only.
    }
  }
}

/// Sequential authenticated reader for `.owntend-backup` containers.
class BackupContainerReader {
  BackupContainerReader._({required this.header, required this.key});

  static Future<BackupContainerReader> open({
    required RandomAccessFile input,
    required String passphrase,
  }) async {
    await input.setPosition(0);
    final headerBytes = await input.read(BackupContainerCodec.headerLength);
    final header = BackupContainerHeader.decode(headerBytes);
    final key = await header.deriveKey(passphrase);
    return BackupContainerReader._(header: header, key: key);
  }

  final BackupContainerHeader header;
  final SecretKey key;
  int _frameIndex = 0;
  bool _closed = false;

  /// Reads and authenticates the next frame's plaintext. Returns null at end
  /// of stream. Throws [BackupContainerFormatException] when authentication
  /// or framing fails.
  Future<Uint8List?> readFrame(RandomAccessFile input) async {
    if (_closed) return null;
    final lenBytes = await input.read(4);
    if (lenBytes.isEmpty) {
      _closed = true;
      return null;
    }
    if (lenBytes.length < 4) {
      throw const BackupContainerFormatException('truncated frame length');
    }
    final length = ByteData.sublistView(Uint8List.fromList(lenBytes))
        .getUint32(0, Endian.little);
    if (length == 0 || length > header.chunkSize) {
      throw const BackupContainerFormatException('frame length out of range');
    }
    final cipherPlusTag = await input.read(
      length + BackupContainerCodec.tagLength,
    );
    if (cipherPlusTag.length < length + BackupContainerCodec.tagLength) {
      throw const BackupContainerFormatException('truncated frame');
    }
    final cipherText = Uint8List.sublistView(
      Uint8List.fromList(cipherPlusTag),
      0,
      length,
    );
    final mac = Mac(
      Uint8List.sublistView(
        Uint8List.fromList(cipherPlusTag),
        length,
        length + BackupContainerCodec.tagLength,
      ),
    );
    final List<int> clearText;
    try {
      clearText = await BackupContainerCodec._aead.decrypt(
        SecretBox(cipherText, nonce: header.frameNonce(_frameIndex), mac: mac),
        secretKey: key,
        aad: header.frameAad(_frameIndex),
      );
    } on SecretBoxAuthenticationError {
      throw const BackupContainerFormatException('frame authentication failed');
    }
    _frameIndex++;
    return Uint8List.fromList(clearText);
  }

  void destroyKey() {
    try {
      key.destroy();
    } on Object {
      // Best effort only.
    }
  }
}

Uint8List _secureRandom(int length) {
  final out = Uint8List(length);
  final random = Random.secure();
  for (var i = 0; i < length; i++) {
    out[i] = random.nextInt(256);
  }
  return out;
}
